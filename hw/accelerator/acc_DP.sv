`define WORD_LEN 32
`define BYTE_LEN 8


module acc_DP (

    input logic clk_i,                                                      // clock
    // input contrls
    input logic nrst_MAC,                                                     // active low reset for MACs
    input logic nrst_SR,                                                     // active low reset for Shift regs
    input logic sel_adder,                                                  // adder selection for the accumulators
    input logic [1:0] sel_SR,                                               // shift register selection
    input logic [2:0] sel_s_SR,                                                // shift register input sample selection
    input logic [1:0] sel_acc,                                              // accumulator selection   
    input logic sel_0,                                                       // select zero for the DP input                                             
    input logic en_MAC,                                                     // enable MACs
    input logic ld_MAC,                                                     // load MACs
    input logic sh_SR,                                                      // shift registers shift enable for
    input logic ld_SR [3:0],                                                      // shift registers load

    //input data
    input logic signed [31:0] data_i,                                              // sample input to be fed to the shift registers

    //output data
    output logic signed [31:0] data_o
);
import DP_package::*;

Bus4B_t SP_out;                                                             // Output Bus of the Scratchpad
Bus4B_t SP_out_0;                                                              // Input Bus of the Scratchpad
Bus5B_t SR_out[3:0];                                                          // Output Buses of the Shift Registers
logic signed [31:0] Acc [3:0];                                              // Output of the Accumulators 
logic signed [7:0] Sa;                                                      // Samples to be fed to the MACs
logic signed [31:0] SP_in;                                                  // Internal Input bus of the Scratchpad
logic signed [31:0] Acc_2_SP;                                                 // Output of the Accumulator Mux

assign SP_out = data_i;
assign data_o = SP_in;

always_comb begin
    if (!sel_0) begin
        SP_out_0 = SP_out; 
    end else begin
        SP_out_0 = '0; 
    end
end


generate 
    for (genvar i = 0; i < 4; i++) begin : gen_SRs
        sr #(8, 5) i_SR (
            .clk      (clk_i),
            .nrst     (nrst_SR),
            .shift    (sh_SR),
            .load     (ld_SR[i]),
            .shift_in (SP_out_0.o[i]),
            .SR_in    ('{o: {SP_out.o[3], SP_out.o[2], SP_out.o[1], SP_out.o[0], 8'h00}}), 
            .SR_out   (SR_out[i])
        );
    end
endgenerate

// MACs instantiation
generate 
    for (genvar i = 0; i < 4; i++) begin : gen_MACs
        mac i_mac (
            .clk_i   (clk_i),
            .rst_ni  (nrst_MAC),
            .load_i  (ld_MAC),
            .en_i    (en_MAC),
            .a_i     (Sa),                          //samples
            .b_i     (SP_out.o[3-i]),                 //weights
            .acc_i   (32'(SP_out)), 
            .acc_o   (Acc[i])
        );
    end
endgenerate


always_comb begin 

    Bus5B_t SR_now;  
    SR_now  = '0; 
    Sa      = '0;
    
    // Mux selezione SR
    SR_now = SR_out[sel_SR];

    // Mux selezione campione Sa
    if (sel_s_SR < 5) begin
        Sa = SR_now.o[4-sel_s_SR];
    end else begin
        Sa = '0;
    end
end

// Mux selezione Accumulatore verso Scratchpad
always_comb begin
    Acc_2_SP = Acc[sel_acc]; 
end

always_comb begin
    // Mux selezione adder
    if (sel_adder) 
        SP_in = Acc_2_SP + SP_out;
    else 
        SP_in = Acc_2_SP;
end
endmodule