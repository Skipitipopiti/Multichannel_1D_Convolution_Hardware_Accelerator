#include <iostream>
#include <cstdlib>

using namespace std;

int main(int argc, char* argv[])
{
    const int K = 5; // kernel size (fixed)

    if (argc != 4) {
        cout << "Usage: " << argv[0] << " T Cin Cout\n";
        return 1;
    }

    int T    = atoi(argv[1]); // tile size
    int Cin  = atoi(argv[2]); // input channels
    int Cout = atoi(argv[3]); // output channels

    int Nin   = Cin * (T + K - 1)/4;   // #input samples in a tile
    int Nker  = Cout * Cin * K/4;      // #kernel coefficients
    int Nout  = Cout * T;            // #output samples in a tile
    int Ntile = Nin + Nker + Nout;   // total SP usage

    cout << "K: "     << K     << "\n";
    cout << "T: "     << T     << "\n";
    cout << "Cin: "   << Cin   << "\n";
    cout << "Cout: "  << Cout  << "\n\n";

    cout << "Nin: "   << Nin   << "\n";
    cout << "Nker: "  << Nker  << "\n";
    cout << "Nout: "  << Nout  << "\n";
    cout << "Ntile: " << Ntile << "\n";

    return 0;
}
