//==============================================================
// riscv_decode.sv
//
// Two-way decode front-end helper:
// - Input: 64-bit bundle {inst1, inst0} + base PC
// - Output: 2 lanes (0/1) each with instr/pc/flags
// - Uses small FIFO to hold bundles across stalls
// - Optional EXTRA_DECODE_STAGE adds 1 register stage before FIFO
//
// Handshake concept:
//   - Upstream (FETCH -> DECODE): fetch_in_valid_i / fetch_in_accept_o
//   - Downstream (DECODE -> ID/ISSUE): out_valid_o / out_accept_i (per lane)
//
// Flush on branch_request_i (redirect)
//==============================================================

`timescale 1ns/1ps

module riscv_decode #(
	// -------------------------
	// Same "base" widths as FETCH
	// -------------------------
	parameter int unsigned XLEN      = 32,   // PC width / register width (RV32)
	parameter int unsigned ILEN      = 32,   // instruction width (RV32I)
	parameter int unsigned LANES     = 2,    // two-way frontend
	parameter int unsigned PC_W      = XLEN, // PC width

	// Derived
	parameter int unsigned BUNDLE_W  = LANES * ILEN, // 64 when LANES=2, ILEN=32

	// FIFO
	parameter int unsigned FIFO_DEPTH = 2,
	parameter int unsigned FIFO_ADDR_W = $clog2(FIFO_DEPTH),

	// Features
	parameter bit SUPPORT_MULDIV      = 1'b1,
	parameter bit EXTRA_DECODE_STAGE  = 1'b0,

	// Info widths
	// When EXTRA_DECODE_STAGE=1: we store full decode flags in FIFO (10 bits)
	// When EXTRA_DECODE_STAGE=0: we store only faults (2 bits) and decode after FIFO
	parameter int unsigned INFO_W_FULL = 10,
	parameter int unsigned INFO_W_MIN  = 2
  )(
	input  logic                   clk_i,
	input  logic                   rst_ni,

	// From FETCH
	input  logic                   fetch_in_valid_i,
	input  logic [BUNDLE_W-1:0]    fetch_in_bundle_i,     // {inst1,inst0} when LANES=2
	input  logic [1:0]             fetch_in_pred_branch_i,
	input  logic                   fetch_in_fault_fetch_i,
	input  logic                   fetch_in_fault_page_i,
	input  logic [PC_W-1:0]        fetch_in_pc_i,

	output logic                   fetch_in_accept_o,

	// Redirect / flush
	input  logic                   branch_request_i,
	input  logic [PC_W-1:0]        branch_pc_i,
	input  logic [1:0]             branch_priv_i,

	// To next stage (2 lanes)
	input  logic                   out0_accept_i,
	input  logic                   out1_accept_i,

	output logic                   out0_valid_o,
	output logic [ILEN-1:0]        out0_instr_o,
	output logic [PC_W-1:0]        out0_pc_o,
	output logic                   out0_fault_fetch_o,
	output logic                   out0_fault_page_o,
	output logic                   out0_instr_exec_o,
	output logic                   out0_instr_lsu_o,
	output logic                   out0_instr_branch_o,
	output logic                   out0_instr_mul_o,
	output logic                   out0_instr_div_o,
	output logic                   out0_instr_csr_o,
	output logic                   out0_instr_rd_valid_o,
	output logic                   out0_instr_invalid_o,

	output logic                   out1_valid_o,
	output logic [ILEN-1:0]        out1_instr_o,
	output logic [PC_W-1:0]        out1_pc_o,
	output logic                   out1_fault_fetch_o,
	output logic                   out1_fault_page_o,
	output logic                   out1_instr_exec_o,
	output logic                   out1_instr_lsu_o,
	output logic                   out1_instr_branch_o,
	output logic                   out1_instr_mul_o,
	output logic                   out1_instr_div_o,
	output logic                   out1_instr_csr_o,
	output logic                   out1_instr_rd_valid_o,
	output logic                   out1_instr_invalid_o
  );


  //============================================================
  // Internal enables
  //============================================================
  logic enable_muldiv_w;
  assign enable_muldiv_w = SUPPORT_MULDIV;

  //============================================================
  // Optional extra stage (to model 2-cycle front-end latency)
  //
  // Idea:
  // - We keep a small "skid register" for the incoming bundle.
  // - If downstream FIFO accepts, we can move forward.
  // - On branch_request_i we flush it to avoid wrong-path bundles.
  //============================================================

  // Signals that feed the FIFO (either direct from fetch, or from buffered stage)
  logic         in_valid_w;
  logic [63:0]  in_bundle_w;
  logic [1:0]   in_pred_w;
  logic         in_fault_fetch_w, in_fault_page_w;
  logic [31:0]  in_pc_w;

  generate
	if (EXTRA_DECODE_STAGE) begin : g_extra_stage

	  typedef struct packed {
		logic         fault_page;
		logic         fault_fetch;
		logic [1:0]   pred;
		logic [63:0]  bundle_raw;
		logic [31:0]  pc;
		logic         valid;
	  } fetch_buf_t;

	  fetch_buf_t fetch_buf_q;

	  // in_valid_w represents "what is currently in the buffer" 
	  // and not necessarily what is arriving directly from FETCH
	  assign in_valid_w       = fetch_buf_q.valid;
	  assign in_pred_w        = fetch_buf_q.pred;
	  assign in_fault_page_w  = fetch_buf_q.fault_page;
	  assign in_fault_fetch_w = fetch_buf_q.fault_fetch;
	  assign in_pc_w          = fetch_buf_q.pc;

	  // If there is a fault, clear the instructions
	  assign in_bundle_w      = (fetch_buf_q.fault_page | fetch_buf_q.fault_fetch)
								? 64'b0 : fetch_buf_q.bundle_raw;

	  // Conditions for updating the buffer:
	  // - reset / flush => clear
	  // - if buffer empty OR FIFO accepted current buffer => load new from fetch
	  always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
		  fetch_buf_q <= '0;
		end else if (branch_request_i) begin
		  fetch_buf_q <= '0;
		end else if (!fetch_buf_q.valid || fetch_in_accept_o) begin
		  fetch_buf_q.fault_page  <= fetch_in_fault_page_i;
		  fetch_buf_q.fault_fetch <= fetch_in_fault_fetch_i;
		  fetch_buf_q.pred        <= fetch_in_pred_branch_i;
		  fetch_buf_q.bundle_raw  <= fetch_in_bundle_i;
		  fetch_buf_q.pc          <= fetch_in_pc_i;
		  fetch_buf_q.valid       <= fetch_in_valid_i;
		end
	  end

	end else begin : g_no_extra_stage
	  // 1-cycle: feed FIFO directly from fetch
	  assign in_valid_w       = fetch_in_valid_i;
	  assign in_pred_w        = fetch_in_pred_branch_i;
	  assign in_fault_page_w  = fetch_in_fault_page_i;
	  assign in_fault_fetch_w = fetch_in_fault_fetch_i;
	  assign in_pc_w          = fetch_in_pc_i;

	  assign in_bundle_w      = (fetch_in_fault_page_i | fetch_in_fault_fetch_i)
								? 64'b0 : fetch_in_bundle_i;
	end
  endgenerate

  //============================================================
  // Pre-decode for 2-cycle mode
  // Decode BEFORE FIFO (only when EXTRA stage is on),
  // storing flags in FIFO info fields.
  // We'll follow exactly that approach:
  // - If EXTRA_DECODE_STAGE=1 => decode on in_bundle_w and push flags into FIFO.
  // - Else => push only faults into FIFO and decode AFTER FIFO.
  //============================================================

  // info fields for each lane
  // [9:0] layout:
  // { invalid, exec, lsu, branch, mul, div, csr, rd_valid, fault_page, fault_fetch }
  localparam int INFO_W = 10;

  logic [7:0] info0_core_w, info1_core_w;
  logic [INFO_W-1:0] info0_in_w, info1_in_w;

  // default pack (for EXTRA stage)
  assign info0_in_w = {info0_core_w, in_fault_page_w, in_fault_fetch_w};
  assign info1_in_w = {info1_core_w, in_fault_page_w, in_fault_fetch_w};

  // Pre-decode blocks (combinational)
  riscv_uop_decoder u_predec0 (
	.valid_i        (in_valid_w),
	.fetch_fault_i  (in_fault_fetch_w | in_fault_page_w),
	.enable_muldiv_i(enable_muldiv_w),
	.opcode_i       (in_bundle_w[31:0]),
	.invalid_o      (info0_core_w[7]),
	.exec_o         (info0_core_w[6]),
	.lsu_o          (info0_core_w[5]),
	.branch_o       (info0_core_w[4]),
	.mul_o          (info0_core_w[3]),
	.div_o          (info0_core_w[2]),
	.csr_o          (info0_core_w[1]),
	.rd_valid_o     (info0_core_w[0])
  );

  riscv_uop_decoder u_predec1 (
	.valid_i        (in_valid_w),
	.fetch_fault_i  (in_fault_fetch_w | in_fault_page_w),
	.enable_muldiv_i(enable_muldiv_w),
	.opcode_i       (in_bundle_w[63:32]),
	.invalid_o      (info1_core_w[7]),
	.exec_o         (info1_core_w[6]),
	.lsu_o          (info1_core_w[5]),
	.branch_o       (info1_core_w[4]),
	.mul_o          (info1_core_w[3]),
	.div_o          (info1_core_w[2]),
	.csr_o          (info1_core_w[1]),
	.rd_valid_o     (info1_core_w[0])
  );

  //============================================================
  // FIFO (holds bundles until both lanes consumed)
  // - Each entry is one 64-bit bundle + base PC + per-lane info.
  // - Lane1 validity can be masked by prediction bit pred[0] (like ref):
  //   valid1 = ~pred_in_i[0]
  //============================================================
  logic [INFO_W-1:0] fifo_info0_out_w, fifo_info1_out_w;

  fetch_fifo_sv #(
	.WIDTH      (64),
	.DEPTH      (2),
	.ADDR_W     (1),
	.OPC_INFO_W (EXTRA_DECODE_STAGE ? INFO_W : 2) // when no extra stage, store only faults
  ) u_fifo (
	.clk_i      (clk_i),
	.rst_ni     (rst_ni),

	.flush_i    (branch_request_i),

	// push side
	.push_i     (in_valid_w),
	.pc_in_i    (in_pc_w),
	.pred_in_i  (in_pred_w),
	.data_in_i  (in_bundle_w),

	.info0_in_i (EXTRA_DECODE_STAGE ? info0_in_w : {in_fault_page_w, in_fault_fetch_w}),
	.info1_in_i (EXTRA_DECODE_STAGE ? info1_in_w : {in_fault_page_w, in_fault_fetch_w}),

	.accept_o   (fetch_in_accept_o),

	// pop side (lane0 / lane1)
	.valid0_o   (out0_valid_o),
	.pc0_out_o  (out0_pc_o),
	.data0_out_o(out0_instr_o),
	.info0_out_o(fifo_info0_out_w),
	.pop0_i     (out0_accept_i),

	.valid1_o   (out1_valid_o),
	.pc1_out_o  (out1_pc_o),
	.data1_out_o(out1_instr_o),
	.info1_out_o(fifo_info1_out_w),
	.pop1_i     (out1_accept_i)
  );

  //============================================================
  // If EXTRA_DECODE_STAGE=1:
  //  - Flags already stored in FIFO (10 bits per lane).
  // Else:
  //  - Only faults stored in FIFO; we decode after FIFO (like ref)
  //============================================================

  generate
	if (EXTRA_DECODE_STAGE) begin : g_flags_from_fifo
	  // unpack from fifo_info
	  assign {
		out0_instr_invalid_o,
		out0_instr_exec_o,
		out0_instr_lsu_o,
		out0_instr_branch_o,
		out0_instr_mul_o,
		out0_instr_div_o,
		out0_instr_csr_o,
		out0_instr_rd_valid_o,
		out0_fault_page_o,
		out0_fault_fetch_o
	  } = fifo_info0_out_w;

	  assign {
		out1_instr_invalid_o,
		out1_instr_exec_o,
		out1_instr_lsu_o,
		out1_instr_branch_o,
		out1_instr_mul_o,
		out1_instr_div_o,
		out1_instr_csr_o,
		out1_instr_rd_valid_o,
		out1_fault_page_o,
		out1_fault_fetch_o
	  } = fifo_info1_out_w;

	end else begin : g_decode_after_fifo
	  // Here FIFO only provides faults:
	  assign {out0_fault_page_o, out0_fault_fetch_o} = fifo_info0_out_w[1:0];
	  assign {out1_fault_page_o, out1_fault_fetch_o} = fifo_info1_out_w[1:0];

	  // Decode on outputs
	  riscv_uop_decoder u_dec0 (
		.valid_i        (out0_valid_o),
		.fetch_fault_i  (out0_fault_fetch_o | out0_fault_page_o),
		.enable_muldiv_i(enable_muldiv_w),
		.opcode_i       (out0_instr_o),
		.invalid_o      (out0_instr_invalid_o),
		.exec_o         (out0_instr_exec_o),
		.lsu_o          (out0_instr_lsu_o),
		.branch_o       (out0_instr_branch_o),
		.mul_o          (out0_instr_mul_o),
		.div_o          (out0_instr_div_o),
		.csr_o          (out0_instr_csr_o),
		.rd_valid_o     (out0_instr_rd_valid_o)
	  );

	  riscv_uop_decoder u_dec1 (
		.valid_i        (out1_valid_o),
		.fetch_fault_i  (out1_fault_fetch_o | out1_fault_page_o),
		.enable_muldiv_i(enable_muldiv_w),
		.opcode_i       (out1_instr_o),
		.invalid_o      (out1_instr_invalid_o),
		.exec_o         (out1_instr_exec_o),
		.lsu_o          (out1_instr_lsu_o),
		.branch_o       (out1_instr_branch_o),
		.mul_o          (out1_instr_mul_o),
		.div_o          (out1_instr_div_o),
		.csr_o          (out1_instr_csr_o),
		.rd_valid_o     (out1_instr_rd_valid_o)
	  );
	end
  endgenerate

endmodule


//==============================================================
// Simple RV32I/RV32M "uop classifier" decoder
// Returns coarse flags only (not full control decode)
//==============================================================
module riscv_uop_decoder (
  input  logic        valid_i,
  input  logic        fetch_fault_i,
  input  logic        enable_muldiv_i,
  input  logic [31:0] opcode_i,

  output logic invalid_o,
  output logic exec_o,
  output logic lsu_o,
  output logic branch_o,
  output logic mul_o,
  output logic div_o,
  output logic csr_o,
  output logic rd_valid_o
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = opcode_i[6:0];
  assign funct3 = opcode_i[14:12];
  assign funct7 = opcode_i[31:25];

  always_comb begin
	// defaults
	invalid_o  = 1'b0;
	exec_o     = 1'b0;
	lsu_o      = 1'b0;
	branch_o   = 1'b0;
	mul_o      = 1'b0;
	div_o      = 1'b0;
	csr_o      = 1'b0;
	rd_valid_o = 1'b0;

	// if not valid or there is a fetch fault: treat as non-executable bubble
	if (!valid_i || fetch_fault_i) begin
	  // everything stays 0
	end else begin
	  unique case (opcode)
		7'b0110011: begin // OP (R-type)
		  // RV32M is also here with funct7=0000001
		  rd_valid_o = 1'b1;

		  if (enable_muldiv_i && (funct7 == 7'b0000001)) begin
			// MUL/DIV group uses funct3
			// MUL=000, MULH=001, MULHSU=010, MULHU=011
			// DIV=100, DIVU=101, REM=110, REMU=111
			if (funct3[2]) begin
			  // 1xx -> DIV/REM
			  div_o  = 1'b1;
			end else begin
			  // 0xx -> MUL*
			  mul_o  = 1'b1;
			end
		  end else begin
			exec_o = 1'b1; // regular ALU ops
		  end
		end

		7'b0010011: begin // OP-IMM
		  exec_o     = 1'b1;
		  rd_valid_o = 1'b1;
		end

		7'b0000011: begin // LOAD
		  lsu_o      = 1'b1;
		  rd_valid_o = 1'b1;
		end

		7'b0100011: begin // STORE
		  lsu_o      = 1'b1;
		  rd_valid_o = 1'b0;
		end

		7'b1100011: begin // BRANCH
		  branch_o   = 1'b1;
		  rd_valid_o = 1'b0;
		end

		7'b1101111: begin // JAL
		  branch_o   = 1'b1;
		  rd_valid_o = 1'b1;
		end

		7'b1100111: begin // JALR
		  branch_o   = 1'b1;
		  rd_valid_o = 1'b1;
		end

		7'b0110111: begin // LUI
		  exec_o     = 1'b1;
		  rd_valid_o = 1'b1;
		end

		7'b0010111: begin // AUIPC
		  exec_o     = 1'b1;
		  rd_valid_o = 1'b1;
		end

		7'b1110011: begin // SYSTEM (CSR/ECALL/EBREAK/MRET...)
		  csr_o      = 1'b1;
		  // rd_valid depends on CSR instruction (some write rd)
		  // We'll mark rd_valid if rd!=x0 and it's CSR* type (funct3 != 000)
		  rd_valid_o = (funct3 != 3'b000) && (opcode_i[11:7] != 5'd0);
		end

		default: begin
		  invalid_o = 1'b1;
		end
	  endcase
	end
  end
endmodule


//==============================================================
// fetch_fifo_sv
// Holds bundle entries and allows 2 lanes to be popped independently.
// Entry considered completed when:
//  - lane0 popped and lane1 not valid
//  - lane1 popped and lane0 not valid
//  - both popped
//
// pred_in_i[0] is used to mask lane1 validity.
//==============================================================
module fetch_fifo_sv #(
  parameter int WIDTH      = 64,
  parameter int DEPTH      = 2,
  parameter int ADDR_W     = 1,
  parameter int OPC_INFO_W = 10
)(
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 flush_i,

  // push side
  input  logic                 push_i,
  input  logic [31:0]          pc_in_i,
  input  logic [1:0]           pred_in_i,
  input  logic [WIDTH-1:0]     data_in_i,
  input  logic [OPC_INFO_W-1:0] info0_in_i,
  input  logic [OPC_INFO_W-1:0] info1_in_i,
  output logic                 accept_o,

  // lane0
  output logic                 valid0_o,
  output logic [31:0]          pc0_out_o,
  output logic [(WIDTH/2)-1:0] data0_out_o,
  output logic [OPC_INFO_W-1:0] info0_out_o,
  input  logic                 pop0_i,

  // lane1
  output logic                 valid1_o,
  output logic [31:0]          pc1_out_o,
  output logic [(WIDTH/2)-1:0] data1_out_o,
  output logic [OPC_INFO_W-1:0] info1_out_o,
  input  logic                 pop1_i
);

  localparam int COUNT_W = ADDR_W + 1;

  logic [31:0]            pc_q     [DEPTH];
  logic                   v0_q     [DEPTH];
  logic                   v1_q     [DEPTH];
  logic [OPC_INFO_W-1:0]  info0_q  [DEPTH];
  logic [OPC_INFO_W-1:0]  info1_q  [DEPTH];
  logic [WIDTH-1:0]       ram_q    [DEPTH];

  logic [ADDR_W-1:0]      rd_ptr_q, wr_ptr_q;
  logic [COUNT_W-1:0]     count_q;

  // handshake helpers
  logic push_w;
  logic pop0_w, pop1_w;
  logic pop_complete_w;

  assign accept_o = (count_q != DEPTH[COUNT_W-1:0]);
  assign push_w   = push_i & accept_o;

  // Pop only if valid is asserted
  assign pop0_w = pop0_i & valid0_o;
  assign pop1_w = pop1_i & valid1_o;

  // Entry is completed if:
  // - popped lane0 and lane1 is not valid
  // - popped lane1 and lane0 is not valid
  // - both popped
  assign pop_complete_w =
	  (pop0_w && !valid1_o) ||
	  (pop1_w && !valid0_o) ||
	  (pop0_w && pop1_w);

  integer i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
	if (!rst_ni) begin
	  count_q  <= '0;
	  rd_ptr_q <= '0;
	  wr_ptr_q <= '0;
	  for (i = 0; i < DEPTH; i++) begin
		ram_q[i]   <= '0;
		pc_q[i]    <= '0;
		info0_q[i] <= '0;
		info1_q[i] <= '0;
		v0_q[i]    <= 1'b0;
		v1_q[i]    <= 1'b0;
	  end
	end else if (flush_i) begin
	  // On redirect: clear FIFO completely (important!)
	  count_q  <= '0;
	  rd_ptr_q <= '0;
	  wr_ptr_q <= '0;
	  for (i = 0; i < DEPTH; i++) begin
		info0_q[i] <= '0;
		info1_q[i] <= '0;
		v0_q[i]    <= 1'b0;
		v1_q[i]    <= 1'b0;
	  end
	end else begin
	  // -------------------
	  // Push
	  // -------------------
	  if (push_w) begin
		ram_q[wr_ptr_q]   <= data_in_i;
		pc_q[wr_ptr_q]    <= pc_in_i;
		info0_q[wr_ptr_q] <= info0_in_i;
		info1_q[wr_ptr_q] <= info1_in_i;

		// lane0 always valid when pushing an entry
		v0_q[wr_ptr_q]    <= 1'b1;

		// lane1 validity masked by prediction bit
		// If pred_in_i[0]==1 => second instruction is "killed"
		v1_q[wr_ptr_q]    <= ~pred_in_i[0];

		wr_ptr_q          <= wr_ptr_q + 1'b1;
	  end

	  // -------------------
	  // Pop per lane
	  // -------------------
	  if (pop0_w) v0_q[rd_ptr_q] <= 1'b0;
	  if (pop1_w) v1_q[rd_ptr_q] <= 1'b0;

	  // advance read pointer when entry completed
	  if (pop_complete_w)
		rd_ptr_q <= rd_ptr_q + 1'b1;

	  // update count
	  if (push_w && !pop_complete_w)
		count_q <= count_q + 1'b1;
	  else if (!push_w && pop_complete_w)
		count_q <= count_q - 1'b1;
	end
  end

  // outputs (combinational)
  assign valid0_o = (count_q != 0) & v0_q[rd_ptr_q];
  assign valid1_o = (count_q != 0) & v1_q[rd_ptr_q];

  // PCs for lane0/lane1 within the bundle:
  // lane0: base aligned to 8, lane1: base+4
  assign pc0_out_o = {pc_q[rd_ptr_q][31:3], 3'b000};
  assign pc1_out_o = {pc_q[rd_ptr_q][31:3], 3'b100};

  // split bundle
  assign data0_out_o = ram_q[rd_ptr_q][(WIDTH/2)-1:0];
  assign data1_out_o = ram_q[rd_ptr_q][WIDTH-1:(WIDTH/2)];

  assign info0_out_o = info0_q[rd_ptr_q];
  assign info1_out_o = info1_q[rd_ptr_q];

endmodule
