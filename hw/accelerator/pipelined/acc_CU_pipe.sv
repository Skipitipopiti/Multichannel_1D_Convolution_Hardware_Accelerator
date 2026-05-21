/**
    * Note: I
    * contatori che non sono esplicitamente resettati utilizzano il wrap-around per farlo.
    *
    * always_latch non crea un latch “ovunque” automaticamente, ma dice al tool che tutti i segnali assegnati dentro quell’always possono legittimamente mantenere il valore precedente se un ramo non li assegna, e quindi il tool non darà più warning di latch impliciti.
*/

module acc_CU (
    input logic clk,
    input logic rst_n,

    // CU - MM interface
    input logic start_i,
    input logic ack_i, // acknowledgment from MM

    output logic done_o,
    output logic running_o,
    output logic k_req_o, // request to MM for kernel data
    output logic s_req_o, // request to MM for sample data
    output logic out_ready_o, // signal to MM that output data is ready to be read
    output logic pad_ready_o,

    output logic [3:0] be, // 4 bit mask for sample selection in SP access

    // CU - SP interface
    output logic cs, // chip select for SP access
    output logic wnr, // wr/nrd for SP access
    output logic [1:0] sel_SR, // shift register selection
    output logic [2:0] sel_s_SR, // shift register output sample selection

    // CU - DP interface
    output logic nrst_mac, // reset for MACs 
    output logic en_mac, // enable MACs
    output logic ld_mac, // load MACs - si risparmia la commutazione di reset delle MACs
    output logic nrst_SR, // reset for shift registers
    output logic sh_SR, // shift registers shift enable for
    output logic ld_SR0, ld_SR1, ld_SR2, ld_SR3, // shift registers load
    output logic [1:0] sel_acc, // accumulator selection for SPR write
    output logic [6:0] add, // address for SP access
    output logic sel_adder, // select signal for the adder that accumulates the output in the SP
    output logic sel_0
);

    // state encoding
    typedef enum logic [5:0] { 
        idle,
        send_k_req, // flag request to MM for kernel data
        wait_k, // enable writing kernel data into SP
        send_s_req, // flag request to MM for sample data
        wait_s, // wait for sample data to be written into SP
        rd_s, // read samples from SP for a SR
        ld_sr, // load samples into a SR
        rd_s_p, // read sample from SP for every SR
        sh, // shift samples in SRs in parallel
        rd_k, // read kernel column 0 from SP
        wr_acc_rd_k,
        wr_acc,
        rd_out, // read on output for outs accumulation
        acc_out, // accumulate output in SP
        send_out_ready, // flag to MM that output data is ready to be read
        wait_out, // send output data to MM

        // initial padding states
        rd_s_pad_i,
        ld_sr_pad_i,
        rd_k_pad_i,
        wr_acc_rd_k_pad_i0,
        wr_acc_rd_k_pad_i1,
        wr_acc_pad_i,
        clean_acc_pad_i,
        send_ready_pad_i,
        wait_out_pad_i,

        // final padding states
        rd_s_p_pad_o,
        sh_pad_o,
        sh_0,
        sh_00,
        rd_k_pad_o, // read kernel column 0 from SP
        wr_acc_rd_k_pad_o,
        wr_acc_pad_o,
        clean_acc_pad_o, // clean accumulators for the next sequence
        send_ready_pad_o, // flag to MM that padding is ready to be read
        wait_out_pad_o, // send padded output data to MM

        done_state
    } state_type;

    state_type state, next_state;

    // internal signals
    logic [1:0] i;
    logic [4:0] seq; // global sequence number
    logic [1:0] t; // tile sequennce number
    logic [1:0] cin; // input channel counter
    logic cout; // output channel counter
    logic [2:0] add_k; // k coefficient on kernel column
    logic [2:0] sel_s; // sample selection for MAC input, corresponds to the kernel coefficient selected by add_k
    logic [2:0] sel_s_pad; // sample selection for MAC input during padding, corresponds to the kernel coefficient selected by add_k
    logic [4:0] add_s; // address for sample loading
    logic [6:0] add_k_out; // address for kernel loading with offset
    logic [6:0] add_out; // address for output loading with offset
    logic [4:0] add_s_pad_i; // address for sample loading with offset for initial padding
    logic [4:0] add_s_pad_o; // address for sample loading with offset for final padding
    // SP-MM interaction management

    // state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= idle;
        else 
            state <= next_state;
    end

    // next state logic
    always_comb begin
        next_state = state;
        case (state)
            idle: begin
                if (start_i)
                    next_state = send_k_req;
                else
                    next_state = idle;
            end
            send_k_req: next_state = wait_k;
            wait_k: begin
                if (ack_i)
                    next_state = send_s_req;
                else
                    next_state = wait_k;
            end
            send_s_req: next_state = wait_s;
            wait_s: begin
                if (!ack_i)
                    next_state = wait_s;
                else if (seq == 0)
                    next_state = rd_s_pad_i; // if it's the first sequence, read samples with padding for the initial tile
                else
                    next_state = rd_s;
            end

            rd_s: next_state = ld_sr;
            ld_sr: begin
                if (i == 3)
                    next_state = rd_s_p;
                else
                    next_state = rd_s;
            end
            rd_s_p: next_state = sh;
            sh: next_state = rd_k;
            rd_k: next_state = wr_acc_rd_k;
            wr_acc_rd_k: begin
                if (add_k == 4)
                    next_state = wr_acc;
                else
                    next_state = wr_acc_rd_k;
            end
            wr_acc: begin
                if (i == 3)
                    if (cin == 0)
                        next_state = acc_out;
                    else 
                        next_state = rd_out;
                else
                    next_state = rd_k;
            end
            rd_out: next_state = acc_out;
            acc_out: begin
                if (i != 3)
                    if (t == 0 && cin == 0)
                        next_state = acc_out;
                    else
                        next_state = rd_out;
                else if (t != 3)
                    next_state = rd_s_p;
                else if (cin != 3)
                    next_state = rd_s;
                else
                    next_state = send_out_ready;
            end
            send_out_ready: next_state = wait_out;
            wait_out: begin
                if (!ack_i)
                    next_state = wait_out;
                else if(seq == 30)
                    next_state = rd_s_p_pad_o;
                else
                    next_state = send_s_req;
            end

            // in pad states
            rd_s_pad_i: next_state = ld_sr_pad_i;
            ld_sr_pad_i: begin
                if (i == 3)
                    next_state = rd_k_pad_i;
                else
                    next_state = rd_s_pad_i;
            end
            rd_k_pad_i: begin
                if(t == 0)
                    next_state = wr_acc_rd_k_pad_i0;
                else
                    next_state = wr_acc_rd_k_pad_i1;
            end
           wr_acc_rd_k_pad_i0: begin
                if (add_k == 2)
                    next_state = wr_acc_rd_k_pad_i1;
                else
                    next_state = wr_acc_rd_k_pad_i0;
           end
           wr_acc_rd_k_pad_i1: begin
                if (add_k == 4)
                    next_state = wr_acc_pad_i;
                else
                    next_state = wr_acc_rd_k_pad_i1;
            end
            wr_acc_pad_i: begin
                if (i != 3)
                    next_state = rd_k_pad_i;
                else if (cin == 3)
                    next_state = clean_acc_pad_i;
                else
                    next_state = rd_s_pad_i;
            end
            clean_acc_pad_i: begin
                if (i != 3)
                    next_state = clean_acc_pad_i;
                else if(t == 1)
                    next_state = send_ready_pad_i;
                else
                    next_state = rd_s_pad_i;
            end
            send_ready_pad_i: next_state = wait_out_pad_i;
            wait_out_pad_i: begin
                if (ack_i)
                    next_state = rd_s;
                else
                    next_state = wait_out_pad_i;
            end
            
            // out pad states
            rd_s_p_pad_o: next_state = sh_pad_o;
            sh_pad_o: begin
                if (i == 3)
                    next_state = sh_0;
                else
                    next_state = rd_s_p_pad_o;
            end
            sh_0: begin
                if (t == 0)
                    next_state = rd_k_pad_o;
                else
                    next_state = sh_00;
            end
            sh_00: next_state = rd_k_pad_o;
            rd_k_pad_o: next_state =wr_acc_rd_k_pad_o;
            wr_acc_rd_k_pad_o: begin
                if (add_k == 4)
                    next_state = wr_acc_pad_o;
                else
                    next_state =wr_acc_rd_k_pad_o;
            end
            wr_acc_pad_o: begin
                if (i != 3)
                    next_state = rd_k_pad_o;
                else if (cin != 3)
                    next_state = rd_s_p_pad_o;
                else
                    next_state = clean_acc_pad_o;
            end
            clean_acc_pad_o: begin
                if (i != 3)
                    next_state = clean_acc_pad_o;
                else if(t == 1)
                    next_state = send_ready_pad_o;
                else
                    next_state = rd_s_p_pad_o;
            end
            send_ready_pad_o: next_state = wait_out_pad_o;
            wait_out_pad_o: begin
                if (!ack_i)
                    next_state = wait_out_pad_o;
                else if (cout == 1)
                    next_state = done_state;
                else
                    next_state = send_k_req;
            end

            done_state: begin
                if (ack_i)
                    next_state = done_state;
                else
                    next_state = idle;
            end
            default: next_state = idle;
        endcase
    end
    
    
    // output logic and internal signals logic
    assign sel_SR = i;
    assign sel_acc = i;
    assign sel_s = 5-add_k; // compute kernel column k into the selected SR sample, -1 because add_k is incremented after the read
    assign sel_s_pad = 6-add_k; // for padding, select the zero sample for the first two kernel coefficients, then select the actual samples for the last three coefficients, this is because of the way the shift registers are loaded with padded samples (first the 4 samples from the current tile, then the 4 samples from the previous tile)

    always_comb begin
        // default values
        done_o = 0;
        running_o = 1;
        k_req_o = 0;
        s_req_o = 0;
        out_ready_o = 0;
        pad_ready_o = 0;
        
        be = 4'b1111;

        cs = 0;
        wnr = 0;
        sel_s_SR = sel_s;
        
        nrst_mac = 1;
        en_mac = 0;
        ld_mac = 0;
        nrst_SR = 1;
        sh_SR = 0;
        ld_SR0 = 0;
        ld_SR1 = 0;
        ld_SR2 = 0;
        ld_SR3 = 0;
        sel_adder = 0;
        sel_0 = 0;

        add = 0;
        

        case (state)
            idle: begin
                running_o = 0;
                nrst_mac = 0; // reset MACs in idle state
                nrst_SR = 0; // reset shift registers in idle state
            end
            send_k_req: begin
                running_o = 0;
                k_req_o = 1;
            end
            wait_k: begin
                running_o = 0;
                k_req_o = 1;
            end
            send_s_req: begin
                running_o = 0;
                s_req_o = 1;
            end
            wait_s: begin
                running_o = 0;
                s_req_o = 1;
            end
            rd_s: begin
                cs = 1;
                add = add_s;
                // add_s++;
            end
            ld_sr: begin
                ld_SR0 = (i == 0);
                ld_SR1 = (i == 1);
                ld_SR2 = (i == 2);
                ld_SR3 = (i == 3);
            end
            rd_s_p: begin
                cs = 1;
                add = add_s;
                // add_s++;
            end
            sh: begin
                sh_SR = 1;
            end
            rd_k: begin
                cs = 1;
                add = add_k_out;
                // add_k++;
            end
            wr_acc_rd_k: begin
                // rd_k
                cs = 1;
                add = add_k_out;
                // add_k++;

                // wr_acc
                en_mac = 1;
            end
            wr_acc: begin
                // sel_s_SR = 4;
                en_mac = 1;
                // i++;
            end
            rd_out: begin
                cs = 1;
                add = add_out;
            end
            acc_out: begin
                // sel_acc = i;
                cs = 1;
                wnr = 1;
                add = add_out;
                // add_out++;
                if (cin != 0) 
                    sel_adder = 1; // enable the fifth adder to accumulate partial sums in the output region of the SP
                
                nrst_mac = !(i == 3);
            end
            send_out_ready: begin
                running_o = 0;
                out_ready_o = 1;
            end
            wait_out: begin
                running_o = 0;
                out_ready_o = 1;
                //cs = 1;
             end


            // pad in logic
            rd_s_pad_i: begin
                cs = 1;
                add = add_s_pad_i;
            end
            ld_sr_pad_i: begin
                ld_SR0 = (i == 0);
                ld_SR1 = (i == 1);
                ld_SR2 = (i == 2);
                ld_SR3 = (i == 3);
            end
            rd_k_pad_i: begin
                cs = 1;
                wnr = 0;
                add = add_k_out;
            end
           wr_acc_rd_k_pad_i0: begin
                // rd_k
                cs = 1;
                wnr = 0;
                add = add_k_out;
                // add_k++;
                // wr_acc
                en_mac = 1;
                sel_s_SR = 4; // select the zero sample for multiplication with the first two kernel coefficients for padding
            end
           wr_acc_rd_k_pad_i1: begin
                // rd_k
                cs = 1;
                wnr = 0;
                add = add_k_out;
                // add_k++;
                // wr_acc
                en_mac = 1;

                if (t == 0)
                    sel_s_SR = sel_s_pad;
                else if (add_k == 1)
                    sel_s_SR = 4; // select the zero sample for multiplication with the last kernel coefficient for padding
            end
            wr_acc_pad_i: begin
                en_mac = 1;
                // i++;

                if (t == 0)
                    sel_s_SR = sel_s_pad;
            end
            clean_acc_pad_i: begin
                cs = 1;
                wnr = 1;
                add = add_out;
                // add_out++;
                nrst_mac = !(i == 3);
            end
            send_ready_pad_i: begin
                running_o = 0;
                
                pad_ready_o = 1;
            end
            wait_out_pad_i: begin
                running_o = 0;
                pad_ready_o = 1;
            end

            // pad out logic
            rd_s_p_pad_o: begin
                cs = 1;
                wnr = 0;
                add = add_s_pad_o;
            end
            sh_pad_o: begin
                sh_SR = 1;
                // i++
            end
            sh_0: begin
                sh_SR = 1;
                sel_0 = 1; // select signal for shifting in zeros in the shift registers for padding
                // i = 0;
            end
            sh_00: begin
                sh_SR = 1;
                sel_0 = 1;
                // i = 0;
            end
            rd_k_pad_o: begin
                cs = 1;
                wnr = 0;
                add = add_k_out;
                // add_k++;
            end
            wr_acc_rd_k_pad_o: begin
                // rd_k
                cs = 1;
                wnr = 0;
                add = add_k_out;
                // add_k++;

                // wr_acc
                en_mac = 1;
            end
            wr_acc_pad_o: begin
                // sel_s_SR = 4;
                en_mac = 1;
            end
            clean_acc_pad_o: begin
                cs = 1;
                wnr = 1;
                add = add_out;
                // add_out++;
                nrst_mac = !(i == 3);
            end
            send_ready_pad_o: begin
                running_o = 0;
                
                pad_ready_o = 1;
            end
            wait_out_pad_o: begin
                running_o = 0;
                pad_ready_o = 1;
            end
            done_state: begin
                running_o = 0;
                done_o = 1;
            end
            default: ;
        endcase
    end
endmodule
