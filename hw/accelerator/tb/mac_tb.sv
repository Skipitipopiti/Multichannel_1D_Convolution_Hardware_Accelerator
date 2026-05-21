`timescale 1ns/1ps // Definisce l'unità di tempo e la precisione

module mac_tb;

    // 1. Parametri e segnali
    localparam ALEN   = 8;
    localparam BLEN   = 8;
    localparam ACCLEN = 32;

    logic              clk;
    logic              rst_n;
    logic              load;
    logic              en;
    logic signed [ALEN-1:0]   a;
    logic signed [BLEN-1:0]   b;
    logic signed [ACCLEN-1:0] acc_in;
    logic signed [ACCLEN-1:0] acc_out;

    // 2. Istanziazione del modulo (DUT - Device Under Test)
    // Usiamo la sintassi .* per connettere automaticamente i nomi identici
    mac #(
        .ALEN(ALEN),
        .BLEN(BLEN),
        .ACCLEN(ACCLEN)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .load_i(load),
        .en_i(en),
        .a_i(a),
        .b_i(b),
        .acc_i(acc_in),
        .acc_o(acc_out)
    );

    // 3. Generazione del Clock (periodo 10ns -> 100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // 4. Sequenza di Stimoli
    initial begin
        // Inizializzazione segnali
        rst_n  = 0;
        load   = 0;
        en     = 0;
        a      = 0;
        b      = 0;
        acc_in = 0;

        // Reset del sistema
        #20 rst_n = 1;
        #10;

        // Test 1: Load di un valore iniziale (10)
        @(negedge clk);
        acc_in = 32'sd10; // 'sd' indica signed decimal
        load   = 1;
        @(negedge clk);
        load   = 0;

        // Test 2: Operazione MAC (10 + 2 * 3 = 16)
        a  = 8'sd2;
        b  = 8'sd3;
        en = 1;
        @(negedge clk);
        en = 0;

        // Aspetta un po' e controlla il risultato
        #10;
        if (acc_out === 32'sd16) 
            $display("[SUCCESS] Risultato corretto: %d", acc_out);
        else 
            $display("[FAILURE] Errore: atteso 16, ottenuto %d", acc_out);

        // Test 3: Numeri negativi (16 + (-5 * 2) = 6)
        @(negedge clk);
        a  = -8'sd5;
        b  = 8'sd2;
        en = 1;
        @(negedge clk);
        en = 0;

        #20;
        $finish; // Termina la simulazione
    end

endmodule