#include <iostream>
#include <cstdlib>

using namespace std;

#define K 5 // kernel size (fixed)
#define T 4 // tile size
#define Cin 4 // input channels
#define Cout 4 // output channels
#define Ntile 128 // number of tiles
#define Cin_tot 16 // total input channels
#define Cout_tot 8 // total output channels and kernel sets
#define out_samples 128 // total output samples
#define in_samples 128 // total input samples

// contatori
int Cin_cnt = 0; // contatore canali di input
int offset_Cin = 0;
int Cout_cnt = 0; // contatore canali di output
int in_samples_cnt = 0; // contatore campioni di input

// MM structure
int MM_res[Cout_tot][out_samples] = {0}; // memoria principale per i campioni di uscita
int MM_in_samples[Cin_tot][in_samples] = {0}; // memoria principale per i campioni di ingresso
int MM_in_kernels[Cout_tot][Cin_tot][K] = {0}; // memoria principale per i coefficienti dei kernel

// accumulatori "esterni"
int acc[4];

// SP structure
int SP_out[Cout][T] = {0}; //riferita al canale e al campione di uscita corrente
int SP_in_samples[Cin][T] = {0}; //riferita al canale ingresso e al campione di uscita corrente
int SP_in_kernels[Cout][Cin][K] = {0}; //riferita al canale di output, canale di input e coefficiente del kernel

// SR structure
int SR[Cin][K] = {0}; //shift register per i campioni di input

int main() {
    //Combinazione scelta:
    //T = 8; Cin = 3; Cout = 4; Ntile = 128

    while (in_samples_cnt < in_samples) { // ciclo sui campioni di ingresso
        while (Cout_cnt < Cout_tot) { // ciclo sulle quadruple di canali di output
            while (Cin_cnt < Cin_tot) { // ciclo sulle triplette di canali di input
                if (Cin_cnt == Cin_tot - 1) {
                    offset_Cin = 2;
                } else {
                    offset_Cin = 0;
                }

                // caricamento nello SP dei campioni di ingresso dalla MM
                for (int i = 0; i < Cin - offset_Cin; i++) {
                    for (int n = 0; n < T; n++) {
                        SP_in_samples[i][n] = MM_in_samples[i + Cin_cnt][n + in_samples_cnt];
                    }
                }

                // caricamento nello SP dei kernel dalla MM
                for (int u = 0; u < Cout; u++) { 
                    for (int i = 0; i < Cin - offset_Cin; i++) {
                        for (int k = 0; k < K; k++) {
                            SP_in_kernels[u][i][k] = MM_in_kernels[u + Cout_cnt][i + Cin_cnt][k];
                        }
                    }
                }

                // per ogni campione di uscita nel tile
                for (int n = 0; n < T; n++) {
                    // per ogni canale di input
                    for (int i = 0; i < Cin - offset_Cin; i++) { 
                        // ricarico le variabili di uscita (parziali) dallo SP
                        for (int u = 0; u < Cout; u++) { // per ogni canale di output. @SP_load
                            acc[u] = SP_out[u][n];
                        }
                        // SR <= {0;C_i^{IN}[0-3]}
                        if (n + in_samples_cnt == 0) { //@SR_load_0
                            SR[i][0] = 0; // lo zero serve per le prime due elaborazioni
                            SR[i][1] = SP_in_samples[i + Cin_cnt][0];
                            SR[i][2] = SP_in_samples[i + Cin_cnt][1];
                            SR[i][3] = SP_in_samples[i + Cin_cnt][2];
                            SR[i][4] = SP_in_samples[i + Cin_cnt][3];
                        } else if (n + in_samples_cnt == 126 || n + in_samples_cnt == 127) { // per gli ultimi due campioni, padding con zero. @SR_load_1
                            // shift del registro
                            for (int k = K-1; k > 0; k--) {
                                SR[i][k] = SR[i][k-1];
                            }
                            SR[i][K-1] = 0; // caricamento zero su SR
                        } else if (n + in_samples_cnt != 1) { // per n=1 non si fa nulla, hai già i valori giusti. @SR_shift
                            // shift del registro
                            for (int k = K-1; k > 0; k--) {
                                SR[i][k] = SR[i][k-1];
                            }
                            SR[i][K-1] = SP_in_samples[i + Cin_cnt][n+3]; // caricamento nuovo campione su SR
                        }

                        // elaborazione:
                        for (int k = 0; k < K; k++) { // per ogni coefficiente del kernel
                            // Acc[0-4] += $SR[i][k]*SP\_in\_kernels[0-4][i][k]$
                            if (n + in_samples_cnt == 0) {
                                if (k == 1) {
                                    acc[0] += SR[i][0] * SP_in_kernels[0][i + Cin_cnt][k];
                                    acc[1] += SR[i][0] * SP_in_kernels[1][i + Cin_cnt][k];
                                    acc[2] += SR[i][0] * SP_in_kernels[2][i + Cin_cnt][k];
                                    acc[3] += SR[i][0] * SP_in_kernels[3][i + Cin_cnt][k];
                                } else {
                                    acc[0] += SR[i][k] * SP_in_kernels[0][i + Cin_cnt][k];
                                    acc[1] += SR[i][k] * SP_in_kernels[1][i + Cin_cnt][k];
                                    acc[2] += SR[i][k] * SP_in_kernels[2][i + Cin_cnt][k];
                                    acc[3] += SR[i][k] * SP_in_kernels[3][i + Cin_cnt][k];
                                }
                            }
                            acc[0] += SR[i][k] * SP_in_kernels[0][i + Cin_cnt][k];
                            acc[1] += SR[i][k] * SP_in_kernels[1][i + Cin_cnt][k];
                            acc[2] += SR[i][k] * SP_in_kernels[2][i + Cin_cnt][k];
                            acc[3] += SR[i][k] * SP_in_kernels[3][i + Cin_cnt][k];
                        }
                    }
                    // alla fine dell'elaborazione di un campione di uscita per tutti i canali di input:
                    // salvo i risultati parziali nello SP
                    for (int u = 0; u < Cout; u++) {
                        SP_out[u][n] = acc[u];
                    }
                }
            // fine tile
            Cin_cnt += Cin;
            }
        // caricamento nella MM dei risultati finiti dallo SP, riferiti ai 32 campioni di uscita (T campioni x Cout canali di uscita)
        for (int u = 0; u < Cout; u++) {
            for (int n = 0; n < T; n++) {
                MM_res[u + Cout_cnt][n + in_samples_cnt] = SP_out[u][n];
            }
        }
        Cout_cnt += Cout;
        }
        in_samples_cnt += T;
    }
}



