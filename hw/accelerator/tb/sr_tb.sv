`timescale 1ns/1ps

module sr_tb;

    parameter RL = 8;
    parameter NR = 5;

    logic clk = 0; 
    logic nrst;
    logic shift;
    logic load;
    logic [RL-1:0] shift_in;
    logic [RL-1:0] sr_in  [0:NR-1];
    logic [RL-1:0] sr_out [0:NR-1];

    sr #(.REG_LEN(RL), .NUM_REGS(NR)) dut (.*);

    always #5 clk = ~clk;

    // Task migliorato per il reset
    task drive_reset();
        nrst     <= 0;
        shift    <= 0;
        load     <= 0;
        shift_in <= 0;
        sr_in    <= '{default: '0};
        repeat(5) @(posedge clk);
        nrst     <= 1;
        $display("T=%t [RESET] Sistema pronto.", $time);
    endtask

    initial begin
        drive_reset();

        // --- TEST 1: Load iniziale ---
        $display("T=%t [LOAD] Carico AA BB CC DD EE", $time);
        @(negedge clk);
        load  <= 1;
        sr_in <= '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE};
        @(negedge clk);
        load  <= 0;
        #1; $display("Stato SR: %p", sr_out);

        // --- TEST 2: Sequenza di Shift lunga ---
        $display("T=%t [SHIFT] Inserisco 11, 22, 33", $time);
        @(negedge clk);
        shift    <= 1;
        shift_in <= 8'h11; @(negedge clk);
        shift_in <= 8'h22; @(negedge clk);
        shift_in <= 8'h33; @(negedge clk);
        shift    <= 0;
        #1; $display("Stato SR dopo 3 shift: %p", sr_out);

        // --- TEST 3: Nuovo Load (sovrascrive tutto) ---
        $display("T=%t [LOAD] Sovrascrittura con 01 02 03 04 05", $time);
        @(negedge clk);
        load  <= 1;
        sr_in <= '{8'h01, 8'h02, 8'h03, 8'h04, 8'h05};
        @(negedge clk);
        load  <= 0;
        #1; $display("Stato SR: %p", sr_out);

        // --- TEST 4: Riempimento totale (NR shift) ---
        $display("T=%t [SHIFT] Riempio con FF", $time);
        @(negedge clk);
        shift <= 1;
        shift_in <= 8'hFF;
        repeat(NR) @(negedge clk); // Shifto FF per 5 volte
        shift <= 0;
        #1; $display("Stato SR (dovrebbe essere tutto FF): %p", sr_out);

        // --- TEST 5: Reset Asincrono Improvviso ---
        // Verifichiamo che il reset azzeri subito, senza aspettare il clock
        $display("T=%t [RESET] Reset asincrono di prova...", $time);
        #3; // Siamo a metà del ciclo di clock
        nrst <= 0;
        #1; 
        if (sr_out[0] == 0) $display("T=%t [OK] Reset immediato confermato.", $time);
        else $display("T=%t [ERRORE] Reset non immediato!", $time);
        
        repeat(2) @(posedge clk);
        nrst <= 1;

        // --- TEST 6: Load e Shift combinati (Priorità) ---
        // Se nel modulo hai usato 'else if (load)', il load ha priorità
        $display("T=%t [MIX] Test priorità Load vs Shift", $time);
        @(negedge clk);
        load <= 1;
        shift <= 1;
        sr_in <= '{8'h10, 8'h20, 8'h30, 8'h40, 8'h50};
        shift_in <= 8'h99;
        @(negedge clk);
        load <= 0;
        shift <= 0;
        #1; $display("Stato SR (Priorità Load): %p", sr_out);

        repeat(5) @(posedge clk);
        $display("T=%t [FINE] Tutti i test completati.", $time);
        $stop; 
    end

endmodule