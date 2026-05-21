
/*
 * Shift register module with load and shift capabilities.
 * The module consists of a set of registers that can be loaded with input data or shifted to the right.
 * The shift_in input is loaded into the first register when shifting occurs, and the contents of the registers are shifted to the right.
 * The sr_out output provides the current contents of the registers.
 */

import DP_package::*;
 
module sr #(
    parameter REG_LEN = 8,
    parameter NUM_REGS = 5
)(
    input  logic                clk,
    input  logic                nrst,
    input  logic                shift,
    input  logic                load,
    input  logic [REG_LEN-1:0]  shift_in,
    input  DP_package::Bus5B_t  SR_in,
    output DP_package::Bus5B_t  SR_out
);

    DP_package::Bus5B_t data_reg;

    always_ff @(posedge clk) begin
        if (!nrst) begin
            data_reg <= '{default: '0};
        end
        else if (load) begin
                data_reg <= SR_in;
        end
        else if (shift) begin
            for (int i = 0; i < NUM_REGS-1; i++) begin
                data_reg.o[i] <= data_reg.o[i+1];
            end
            data_reg.o[NUM_REGS-1] <= shift_in;
        end
    end

    assign SR_out = data_reg;

endmodule
