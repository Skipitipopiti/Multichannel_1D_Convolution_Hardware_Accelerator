/*
 * Multiply-Accumulate (MAC) module.
 * This module performs a multiply-accumulate operation on two signed inputs A and B, and an accumulator input.
 * The result of A * B is added to the accumulator input when the enable signal is high, and the result is stored in the accumulator output.
 * The accumulator can also be loaded with a new value when the load signal is high.
 */

module mac #(
    parameter ALEN   =  8,  // Length of the input A
    parameter BLEN   =  8,  // Length of the input B
    parameter ACCLEN = 32  // Length of the output (accumulator)
)(

input logic  clk_i,
input logic  rst_ni,
input logic  load_i,                 // Load signal to update accumulator
input logic   en_i,                   // Enable signal for the MAC operation
input logic signed  [ALEN-1:0] a_i,         // Input A
input logic signed  [BLEN-1:0] b_i,         // Input B
input logic signed  [ACCLEN-1:0] acc_i,     // Accumulator input
output logic signed [ACCLEN-1:0] acc_o      // Accumulator output
);

    logic signed [ALEN + BLEN - 1:0] mult_result;  // Result of A * B
    logic signed [ACCLEN-1:0] sum_result;         // Result of acc_i + mult_result

    assign mult_result = a_i * b_i;        // Multiply A and B
    assign sum_result = acc_o + mult_result;  // Add the multiplication result to the accumulator input

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            acc_o <= '0; 
        end 
        else if (load_i) begin
            acc_o <= acc_i;
        end
        else if (en_i) begin
            acc_o <= sum_result;  // Accumulate the result
        end
    end

endmodule

