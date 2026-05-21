/**
 * Calcola le migliori combinazioni di tile per minimizzare i cicli di elaborazione
 */

#include <iostream>
#include <vector>
#include <iostream>
#include <fstream> 
using namespace std;

#define K 5 // kernel size (fixed)
#define Nmax 128 // max SP size
#define L_out 128 // total length of the signal
#define total_C_in 16 // total input channels
#define total_C_out 8 // total output channels

struct TileConfig {
    int T;
    int Cin;
    int Cout;
    int Ntile;
    int ch_factor; // eleborazioni necessarie a coprire tutti i canali
};

/**
 * Elabora un tile di dimensione T, con C_in canali di ingresso e C_out canali di uscita.
 * @param T dimensione del tile
 * @param C_in numero di canali di ingresso
 * @param C_out numero di canali di uscita
 * @return numero di cicli impiegati per elaborare il tile
 */
int tile(int T, int C_in, int C_out);

/**
 * Genera tutte le combinazioni valide di tile e le scrive su un file.
 * @param outFile file di output
 * @return vettore di configurazioni di tile valide
 */
std::vector<TileConfig> generateTileConfigs(std::ofstream& outFile);


int main()
{
    std::string filename = "tile_configs.txt";
    std::ofstream outFile(filename); // apre il file in scrittura
    if (!outFile) {
        cerr << "Error opening file: " << filename << endl;
        return 1;
    }
    cout << "T\tCin\tCout\tNtile\n";
    std::vector<TileConfig> configs = generateTileConfigs(outFile);
    outFile.close();
}


std::vector<TileConfig> generateTileConfigs(std::ofstream& outFile) {
    std::vector<TileConfig> configs;

    for (int Cout = 1; Cout <= total_C_out; Cout++) {
        for (int Cin = 1; Cin <= total_C_in; Cin++) {

            for (int T = 1; T <= L_out; T++) {

                int Ntile = Cin * (T + K - 1)/4
                          + Cout * Cin * K/4
                          + Cout * T;
                
                if (Ntile > Nmax)
                    break; // no need to check larger T values

                TileConfig tile;
                tile.T = T;
                tile.Cin = Cin;
                tile.Cout = Cout;
                tile.Ntile = Ntile;
                int ch_factor = ((total_C_in + tile.Cin - 1) / tile.Cin) * ((total_C_out + tile.Cout - 1) / tile.Cout);
                // calcolo il fattore di canali per ogni configurazione, arrondando per eccesso
                tile.ch_factor = ch_factor;
                configs.push_back(tile); // stack-allocated

                outFile << T << "\t" << Cin << "\t" << Cout << "\t" << Ntile << "\n";
                
            }
        }
    }
    return configs;
}

