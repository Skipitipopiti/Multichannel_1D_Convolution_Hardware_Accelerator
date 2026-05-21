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
// File: conv1d_control_reg.sv
// Author(s):
//   Michele Caon
// Date: 07/11/2024
// Description: Conv1d control register wrapper

module conv1d_control_reg (
  input  logic                      clk_i,
  input  logic                      rst_ni,
  /* verilator lint_off UNUSED */  // TODO: Remove this line when the signal is used
  /* verilator lint_off UNDRIVEN */  // TODO: Remove this line when the signal is driven
  // Register interface
  input  conv1d_reg_pkg::reg_req_t req_i,   // from host system
  output conv1d_reg_pkg::reg_rsp_t rsp_o,    // to host system

  // TODO1: Add here the interface from the registers to the accelerator

  //output status signals to the accellerator CU
  output logic start_o,
  output logic ack_o,

  
  // input status signals from the accellerator CU
  input  logic running_i,
  input  logic done_i,
  input  logic out_ready_i,
  input  logic pad_ready_i,
  input  logic s_req_i,
  input  logic k_req_i
);
  // INTERNAL SIGNALS
  // ----------------
  // Registers <--> Accelerator
  conv1d_control_reg_pkg::conv1d_control_reg2hw_t reg2hw;
  conv1d_control_reg_pkg::conv1d_control_hw2reg_t hw2reg;

  // signal assignment
  // control signals from reg2hw
  assign start_o = reg2hw.control.start.q ;

  assign ack_o = reg2hw.control.ack.q;

  // status signal hw2reg
  assign hw2reg.status.running.d  = running_i;
  assign hw2reg.status.running.de = 1'b1;

  assign hw2reg.status.done.d     = done_i;
  assign hw2reg.status.done.de    = 1'b1;

  assign hw2reg.status.out_ready.d  = out_ready_i;
  assign hw2reg.status.out_ready.de = 1'b1;

  assign hw2reg.status.pad_ready.d  = pad_ready_i;
  assign hw2reg.status.pad_ready.de = 1'b1;

  assign hw2reg.status.s_req.d  = s_req_i;
  assign hw2reg.status.s_req.de = 1'b1;

  assign hw2reg.status.k_req.d  = k_req_i;
  assign hw2reg.status.k_req.de = 1'b1;

  // -----------------
  // CONTROL REGISTERS
  // -----------------

  // Registers top module
  conv1d_control_reg_top #(
    .reg_req_t(conv1d_reg_pkg::reg_req_t),
    .reg_rsp_t(conv1d_reg_pkg::reg_rsp_t)
  ) u_conv1d_control_reg_top (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .reg_req_i(req_i),
    .reg_rsp_o(rsp_o),
    .reg2hw   (reg2hw),
    .hw2reg   (hw2reg),
    .devmode_i(1'b0)
  );


endmodule
