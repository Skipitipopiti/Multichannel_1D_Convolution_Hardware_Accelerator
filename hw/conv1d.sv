// Copyright 2024 Politecnico di Torino.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File: conv1d.sv
// Author(s):
//   Luigi Giuffrida
//   Michele Caon
// Date: 08/11/2024
// Description: conv1d accelerator top module

module conv1d (
  /* verilator lint_off UNUSED */  // TODO0: Remove this line when the signal is used
  input logic clk_i,
  input logic rst_ni,

  // Interface towards internal memory
  input  croc_pkg::sbr_obi_req_t mem_req_i, // richiesta di scrittura da parte del uC allo SP (scrittura dalla MM)
  output croc_pkg::sbr_obi_rsp_t mem_rsp_o, // risposta di scrittura da parte dello SP al uC (scrittura in MM)

  // TODO1: add here other interface signals (e.g., from the config. registers)
  input  logic start_i,
  input  logic ack_i,

  output logic running_o,
  output logic done_o,
  output logic out_ready_o,
  output logic pad_ready_o,
  output logic s_req_o,
  output logic k_req_o
);
  // PARAMETERS
  localparam int unsigned NumWords = 32'd128;  // DO NOT CHANGE THIS!
  localparam int unsigned AddrWidth = (NumWords > 32'd1) ? unsigned'($clog2(NumWords)) : 32'd1;

  // INTERNAL SIGNALS
  // ----------------
  // Memory multiplexer signals
  conv1d_sram_pkg::sram_req_t int_mem_req, ext_mem_req, mem_req;
  conv1d_sram_pkg::sram_rsp_t mem_rsp;
  logic                       ext_mem_gnt;

  // internal signals from the control unit to the datapath
  logic SP_cs;
  logic [3:0] SP_be;
  logic SP_wnr;
  logic [31:0] SP_add;

  logic sel_adder;
  logic [1:0] sel_SR;
  logic [2:0] sel_s_SR;
  logic [1:0] sel_acc;
  logic nrst_mac;
  logic en_mac;
  logic ld_mac;
  logic nrst_SR;
  logic sh_SR;
  logic ld_SR0, ld_SR1, ld_SR2, ld_SR3;
  logic sel_0;

  // input and output data of the datapath
  logic [31:0] SP_wdata, SP_rdata;

  // ---------------------
  // INTERNAL ARCHITECTURE
  // ---------------------
  // TODO2: write here your code, you are encouraged to use a hierarchical (but not too hierarchical) approach.
  // The internal memory available to the accelerator as a data buffer has been
  // already instantiated below.
  acc_CU u_acc_CU (
    .clk        (clk_i),
    .rst_n      (rst_ni),
    // control register signals
    .start_i      (start_i),
    .ack_i        (ack_i),
    .done_o       (done_o),
    .running_o    (running_o),
    .k_req_o      (k_req_o),
    .s_req_o      (s_req_o),
    .out_ready_o  (out_ready_o),
    .pad_ready_o  (pad_ready_o),

    // output signals to control the internal memory (SP)
    .cs         (SP_cs),
    .be         (SP_be),
    .wnr        (SP_wnr),
    .add        (SP_add),

    // output signals to control the datapath
    .sel_adder  (sel_adder),
    .sel_SR     (sel_SR),
    .sel_s_SR   (sel_s_SR),
    .sel_0      (sel_0),
    .nrst_mac   (nrst_mac),
    .en_mac     (en_mac),
    .ld_mac     (ld_mac),
    .nrst_SR    (nrst_SR),
    .sh_SR      (sh_SR),
    .ld_SR0     (ld_SR0),
    .ld_SR1     (ld_SR1),
    .ld_SR2     (ld_SR2),
    .ld_SR3     (ld_SR3),
    .sel_acc    (sel_acc)
  );

  acc_DP u_acc_DP (
    .clk_i      (clk_i),
    .nrst_MAC   (nrst_mac),
    .nrst_SR    (nrst_SR),

    // control signals from the control unit
    .sel_0      (sel_0),
    .sel_adder  (sel_adder),
    .sel_SR     (sel_SR),
    .sel_s_SR   (sel_s_SR),
    .sel_acc    (sel_acc),
    .en_MAC     (en_mac),
    .ld_MAC     (ld_mac),
    .sh_SR      (sh_SR),
    .ld_SR      ({ld_SR3, ld_SR2, ld_SR1, ld_SR0}),

    // input data from to be read from the internal memory
    .data_i     (SP_rdata),

    // output data to be written back to the internal memory
    .data_o     (SP_wdata)
  );

  // TODO3: connect the following signal to the accelerator's memory request
  // generation logic.
  assign SP_rdata = mem_rsp.rdata; // scratchpad output assigned to the datapath input
  //assign int_mem_req = '{req: SP_cs, we: SP_wnr, be: SP_be, 25'b0, SP_add, wdata: SP_wdata}; // be: 4'hF means that all the 4 bytes of the word are written (32 bit word)
  assign int_mem_req = {SP_cs, SP_wnr, SP_be, SP_add, SP_wdata};
  // Internal memory
  // ---------------
  // Internal memory request multiplexer
  // Because the same, single-port memory must be accessed both through the
  // GR-HEEP bus (host CPU/DMA) and by the accelerator internal hardware, a
  // multiplexer is used to arbitrate between the two.
  // TODO4: change the following assignment to be low when the internal memory is
  // being used by the accelerator, so that external requests are not granted npr
  // propagated to the memory instance.

  // Internal memory multiplexer
  assign ext_mem_gnt = !running_o;
  always_comb begin : mem_req_mux
    if (ext_mem_gnt) begin
      mem_req = ext_mem_req;
    end else begin
      mem_req = int_mem_req;
    end
  end

  // OBI to SRAM bridge
  obi_sram_shim #(
    .ObiCfg    (croc_pkg::SbrObiCfg),
    .obi_req_t (croc_pkg::sbr_obi_req_t),
    .obi_rsp_t (croc_pkg::sbr_obi_rsp_t)
  ) u_obi_bridge (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .obi_req_i (mem_req_i),
    .obi_rsp_o (mem_rsp_o),
    .req_o     (ext_mem_req.req),
    .we_o      (ext_mem_req.we),
    .addr_o    (ext_mem_req.addr),
    .wdata_o   (ext_mem_req.wdata),
    .be_o      (ext_mem_req.be),
    .gnt_i     (ext_mem_gnt),
    .rdata_i   (mem_rsp.rdata)
  );

  // Internal memory instance (SP)
  // NOTE: you may choose to instantiate two internal memories, each half the
  // size of this one (i.e., 64 words as the first parameter) to implement
  // double buffering.
  conv1d_sram_wrapper #(
    .NUM_WORDS (NumWords),
    .DATA_WIDTH(32'd32)
  ) u_internal_mem (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .req_i  (mem_req.req),
    .we_i   (mem_req.we),
    .addr_i (mem_req.addr[AddrWidth+1:2]),
    .wdata_i(mem_req.wdata),
    .be_i   (mem_req.be), // i.e. be_i = 4'b0101; => solo i byte 1 e 3 vengono scritti.
    .rdata_o(mem_rsp.rdata)
  );

endmodule
