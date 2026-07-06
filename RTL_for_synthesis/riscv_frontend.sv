//==============================================================
// riscv_frontend.sv
//
// Glue module: FETCH + DECODE (2-way frontend)
//
// - FETCH brings 64b bundles {inst1,inst0} from I$
// - DECODE splits to 2 lanes and provides coarse flags
//
// Currently: no branch predictor + no faults, so:
//   pred_branch = 2'b00
//   fault_fetch/page = 0
//==============================================================
`timescale 1ns/1ps

module riscv_frontend #(
  parameter int unsigned XLEN = 32,
  parameter int unsigned ILEN = 32,
  parameter logic [XLEN-1:0] RESET_PC = 32'h0000_0000,
  parameter bit SUPPORT_MMU = 1'b1,
  parameter bit SUPPORT_MULDIV = 1'b1,
  parameter bit EXTRA_DECODE_STAGE = 1'b0,
  parameter int unsigned FIFO_DEPTH = 2
)(
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 icache_accept_i,
  input  logic                 icache_valid_i,
  input  logic [2*ILEN-1:0]    icache_bundle_i,

  input  logic                 fetch0_accept_i,
  input  logic                 fetch1_accept_i,

  input  logic                 branch_request_i,
  input  logic [XLEN-1:0]      branch_pc_i,

  output logic                 icache_rd_o,
  output logic                 icache_flush_o,
  output logic                 icache_invalidate_o,
  output logic [XLEN-1:0]      icache_pc_o,
  output logic [1:0]           icache_priv_o,

  output logic                 fetch0_valid_o,
  output logic [ILEN-1:0]      fetch0_instr_o,
  output logic [XLEN-1:0]      fetch0_pc_o,
  output logic                 fetch0_fault_fetch_o,
  output logic                 fetch0_fault_page_o,
  output logic                 fetch0_instr_exec_o,
  output logic                 fetch0_instr_lsu_o,
  output logic                 fetch0_instr_branch_o,
  output logic                 fetch0_instr_mul_o,
  output logic                 fetch0_instr_div_o,
  output logic                 fetch0_instr_csr_o,
  output logic                 fetch0_instr_rd_valid_o,
  output logic                 fetch0_instr_invalid_o,

  output logic                 fetch1_valid_o,
  output logic [ILEN-1:0]      fetch1_instr_o,
  output logic [XLEN-1:0]      fetch1_pc_o,
  output logic                 fetch1_fault_fetch_o,
  output logic                 fetch1_fault_page_o,
  output logic                 fetch1_instr_exec_o,
  output logic                 fetch1_instr_lsu_o,
  output logic                 fetch1_instr_branch_o,
  output logic                 fetch1_instr_mul_o,
  output logic                 fetch1_instr_div_o,
  output logic                 fetch1_instr_csr_o,
  output logic                 fetch1_instr_rd_valid_o,
  output logic                 fetch1_instr_invalid_o
);

  //============================================================
  // Internal wires: FETCH -> DECODE
  //============================================================
  logic                 f_valid;
  logic [2*ILEN-1:0]    f_bundle;
  logic [XLEN-1:0]      f_pc;
  logic [1:0]           f_pred_branch;
  logic                 f_fault_fetch;
  logic                 f_fault_page;
  logic                 f_accept;

  //============================================================
  // Internal wires: simple sequential NPC
  //============================================================
  logic [XLEN-1:0]      pc_f;
  logic                 pc_accept;
  logic [XLEN-1:0]      next_pc_f;
  logic [1:0]           next_taken_f;

  //============================================================
  // Internal constant/default signals
  //============================================================
  logic [1:0]           branch_priv;
  logic                 fetch_invalidate;
  logic                 icache_error;
  logic                 icache_page_fault;

  // No predictor yet: always fetch the next 64-bit bundle
  assign next_pc_f    = pc_f + XLEN'(8);
  assign next_taken_f = 2'b00;

  // No MMU fault/flush generation from frontend yet
  assign branch_priv       = 2'b00;
  assign fetch_invalidate  = 1'b0;
  assign icache_error      = 1'b0;
  assign icache_page_fault = 1'b0;

  //============================================================
  // FETCH instance
  //============================================================
  riscv_fetch #(
	.XLEN        (XLEN),
	.ILEN        (ILEN),
	.SUPPORT_MMU (SUPPORT_MMU),
	.RESET_PC    (RESET_PC)
  ) u_fetch (
	.clk_i                (clk_i),
	.rst_ni               (rst_ni),

	.fetch_accept_i       (f_accept),

	.fetch_valid_o        (f_valid),
	.fetch_pc_o           (f_pc),
	.fetch_bundle_o       (f_bundle),
	.fetch_pred_branch_o  (f_pred_branch),
	.fetch_fault_fetch_o  (f_fault_fetch),
	.fetch_fault_page_o   (f_fault_page),

	.branch_request_i     (branch_request_i),
	.branch_pc_i          (branch_pc_i),
	.branch_priv_i        (branch_priv),

	.fetch_invalidate_i   (fetch_invalidate),

	.icache_accept_i      (icache_accept_i),
	.icache_valid_i       (icache_valid_i),
	.icache_error_i       (icache_error),
	.icache_page_fault_i  (icache_page_fault),
	.icache_bundle_i      (icache_bundle_i),

	.icache_rd_o          (icache_rd_o),
	.icache_pc_o          (icache_pc_o),
	.icache_flush_o       (icache_flush_o),
	.icache_invalidate_o  (icache_invalidate_o),
	.icache_priv_o        (icache_priv_o),

	.next_pc_f_i          (next_pc_f),
	.next_taken_f_i       (next_taken_f),

	.pc_f_o               (pc_f),
	.pc_accept_o          (pc_accept)
  );

  //============================================================
  // DECODE instance
  //============================================================
  riscv_decode #(
	.XLEN               (XLEN),
	.ILEN               (ILEN),
	.LANES              (2),
	.FIFO_DEPTH         (FIFO_DEPTH),
	.SUPPORT_MULDIV     (SUPPORT_MULDIV),
	.EXTRA_DECODE_STAGE (EXTRA_DECODE_STAGE)
  ) u_decode (
	.clk_i                   (clk_i),
	.rst_ni                  (rst_ni),

	.fetch_in_valid_i        (f_valid),
	.fetch_in_bundle_i       (f_bundle),
	.fetch_in_pred_branch_i  (f_pred_branch),
	.fetch_in_fault_fetch_i  (f_fault_fetch),
	.fetch_in_fault_page_i   (f_fault_page),
	.fetch_in_pc_i           (f_pc),
	.fetch_in_accept_o       (f_accept),

	.branch_request_i        (branch_request_i),
	.branch_pc_i             (branch_pc_i),
	.branch_priv_i           (branch_priv),

	.out0_accept_i           (fetch0_accept_i),
	.out1_accept_i           (fetch1_accept_i),

	.out0_valid_o            (fetch0_valid_o),
	.out0_instr_o            (fetch0_instr_o),
	.out0_pc_o               (fetch0_pc_o),
	.out0_fault_fetch_o      (fetch0_fault_fetch_o),
	.out0_fault_page_o       (fetch0_fault_page_o),
	.out0_instr_exec_o       (fetch0_instr_exec_o),
	.out0_instr_lsu_o        (fetch0_instr_lsu_o),
	.out0_instr_branch_o     (fetch0_instr_branch_o),
	.out0_instr_mul_o        (fetch0_instr_mul_o),
	.out0_instr_div_o        (fetch0_instr_div_o),
	.out0_instr_csr_o        (fetch0_instr_csr_o),
	.out0_instr_rd_valid_o   (fetch0_instr_rd_valid_o),
	.out0_instr_invalid_o    (fetch0_instr_invalid_o),

	.out1_valid_o            (fetch1_valid_o),
	.out1_instr_o            (fetch1_instr_o),
	.out1_pc_o               (fetch1_pc_o),
	.out1_fault_fetch_o      (fetch1_fault_fetch_o),
	.out1_fault_page_o       (fetch1_fault_page_o),
	.out1_instr_exec_o       (fetch1_instr_exec_o),
	.out1_instr_lsu_o        (fetch1_instr_lsu_o),
	.out1_instr_branch_o     (fetch1_instr_branch_o),
	.out1_instr_mul_o        (fetch1_instr_mul_o),
	.out1_instr_div_o        (fetch1_instr_div_o),
	.out1_instr_csr_o        (fetch1_instr_csr_o),
	.out1_instr_rd_valid_o   (fetch1_instr_rd_valid_o),
	.out1_instr_invalid_o    (fetch1_instr_invalid_o)
  );

endmodule