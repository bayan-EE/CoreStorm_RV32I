`timescale 1ns/1ps

module tb_riscv_decode_cr;

  // ============================================================
  // Clock / Reset
  // ============================================================
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_ni;

  // ============================================================
  // Choose EXTRA here (0 or 1) – same TB works for both
  // ============================================================
  localparam bit EXTRA  = 1'b1;   //Toggle between 0/1 to test both cases/states
  localparam bit MULDIV = 1'b1;

  // ============================================================
  // DUT signals
  // ============================================================
  logic        fetch_in_valid_i;
  logic [63:0] fetch_in_bundle_i;
  logic [1:0]  fetch_in_pred_branch_i;
  logic        fetch_in_fault_fetch_i;
  logic        fetch_in_fault_page_i;
  logic [31:0] fetch_in_pc_i;
  logic        fetch_in_accept_o;

  logic        branch_request_i;
  logic [31:0] branch_pc_i;
  logic [1:0]  branch_priv_i;

  logic        out0_accept_i, out1_accept_i;

  logic        out0_valid_o, out1_valid_o;
  logic [31:0] out0_instr_o, out1_instr_o;
  logic [31:0] out0_pc_o,    out1_pc_o;
  logic        out0_fault_fetch_o, out0_fault_page_o;
  logic        out1_fault_fetch_o, out1_fault_page_o;

  logic out0_instr_exec_o, out0_instr_lsu_o, out0_instr_branch_o, out0_instr_mul_o, out0_instr_div_o, out0_instr_csr_o;
  logic out0_instr_rd_valid_o, out0_instr_invalid_o;

  logic out1_instr_exec_o, out1_instr_lsu_o, out1_instr_branch_o, out1_instr_mul_o, out1_instr_div_o, out1_instr_csr_o;
  logic out1_instr_rd_valid_o, out1_instr_invalid_o;


  // ============================================================
  // DUT
  // ============================================================
  riscv_decode #(
	.SUPPORT_MULDIV(MULDIV),
	.EXTRA_DECODE_STAGE(EXTRA)
  ) dut (
	.clk_i(clk),
	.rst_ni(rst_ni),

	.fetch_in_valid_i(fetch_in_valid_i),
	.fetch_in_bundle_i(fetch_in_bundle_i),
	.fetch_in_pred_branch_i(fetch_in_pred_branch_i),
	.fetch_in_fault_fetch_i(fetch_in_fault_fetch_i),
	.fetch_in_fault_page_i(fetch_in_fault_page_i),
	.fetch_in_pc_i(fetch_in_pc_i),
	.fetch_in_accept_o(fetch_in_accept_o),

	.branch_request_i(branch_request_i),
	.branch_pc_i(branch_pc_i),
	.branch_priv_i(branch_priv_i),

	.out0_accept_i(out0_accept_i),
	.out1_accept_i(out1_accept_i),

	.out0_valid_o(out0_valid_o),
	.out0_instr_o(out0_instr_o),
	.out0_pc_o(out0_pc_o),
	.out0_fault_fetch_o(out0_fault_fetch_o),
	.out0_fault_page_o(out0_fault_page_o),
	.out0_instr_exec_o(out0_instr_exec_o),
	.out0_instr_lsu_o(out0_instr_lsu_o),
	.out0_instr_branch_o(out0_instr_branch_o),
	.out0_instr_mul_o(out0_instr_mul_o),
	.out0_instr_div_o(out0_instr_div_o),
	.out0_instr_csr_o(out0_instr_csr_o),
	.out0_instr_rd_valid_o(out0_instr_rd_valid_o),
	.out0_instr_invalid_o(out0_instr_invalid_o),

	.out1_valid_o(out1_valid_o),
	.out1_instr_o(out1_instr_o),
	.out1_pc_o(out1_pc_o),
	.out1_fault_fetch_o(out1_fault_fetch_o),
	.out1_fault_page_o(out1_fault_page_o),
	.out1_instr_exec_o(out1_instr_exec_o),
	.out1_instr_lsu_o(out1_instr_lsu_o),
	.out1_instr_branch_o(out1_instr_branch_o),
	.out1_instr_mul_o(out1_instr_mul_o),
	.out1_instr_div_o(out1_instr_div_o),
	.out1_instr_csr_o(out1_instr_csr_o),
	.out1_instr_rd_valid_o(out1_instr_rd_valid_o),
	.out1_instr_invalid_o(out1_instr_invalid_o)
  );

  // ============================================================
  // Expect helper
  // ============================================================
  task automatic tb_expect(input bit cond, input string msg);
	if (!cond) $fatal("TB_FAIL: %s (t=%0t)", msg, $time);
  endtask

  // ============================================================
  // Classify helper (matches riscv_uop_decoder)
  // ============================================================
  task automatic classify_instr(
	input  logic [31:0] inst,
	input  bit          valid,
	input  bit          fault,
	input  bit          enable_muldiv,
	output bit invalid,
	output bit exec,
	output bit lsu,
	output bit branch,
	output bit mul,
	output bit div,
	output bit csr,
	output bit rd_valid
  );
	logic [6:0] opcode;
	logic [2:0] funct3;
	logic [6:0] funct7;
	begin
	  opcode = inst[6:0];
	  funct3 = inst[14:12];
	  funct7 = inst[31:25];

	  invalid = 0; exec=0; lsu=0; branch=0; mul=0; div=0; csr=0; rd_valid=0;

	  if (!valid || fault) begin
		// all zeros
	  end else begin
		unique case (opcode)
		  7'b0110011: begin
			rd_valid = 1;
			if (enable_muldiv && (funct7 == 7'b0000001)) begin
			  if (funct3[2]) div = 1; else mul = 1;
			end else begin
			  exec = 1;
			end
		  end
		  7'b0010011: begin exec = 1; rd_valid = 1; end
		  7'b0000011: begin lsu  = 1; rd_valid = 1; end
		  7'b0100011: begin lsu  = 1; rd_valid = 0; end
		  7'b1100011: begin branch = 1; rd_valid = 0; end
		  7'b1101111: begin branch = 1; rd_valid = 1; end
		  7'b1100111: begin branch = 1; rd_valid = 1; end
		  7'b0110111: begin exec = 1; rd_valid = 1; end
		  7'b0010111: begin exec = 1; rd_valid = 1; end
		  7'b1110011: begin
			csr = 1;
			rd_valid = (funct3 != 3'b000) && (inst[11:7] != 5'd0);
		  end
		  default: begin invalid = 1; end
		endcase
	  end
	end
  endtask

  // ============================================================
  // Transaction (constraints)
  // ============================================================
  class decode_txn;
	rand bit        do_push;
	rand bit        do_flush;

	rand bit [31:0] pc_base;
	rand bit [1:0]  pred;
	rand bit        fault_fetch;
	rand bit        fault_page;

	rand logic [31:0] inst0;
	rand logic [31:0] inst1;

	constraint c_prob {
	  do_push  dist {1 := 70, 0 := 30};
	  do_flush dist {1 := 10, 0 := 90};

	  fault_fetch dist {1 := 5, 0 := 95};
	  fault_page  dist {1 := 5, 0 := 95};

	  // pred[0]=1 kills lane1 sometimes
	  pred dist {2'b00 := 70, 2'b01 := 30};
	}

	constraint c_pc_align { pc_base[2:0] == 3'b000; }

	constraint c_instr_pool {
	  inst0 inside {
		32'h00000033, // OP
		32'h00000013, // OP-IMM
		32'h00002003, // LOAD
		32'h00002023, // STORE
		32'h00000063, // BRANCH
		32'h0000006F, // JAL
		32'h00000067, // JALR
		32'h00000037, // LUI
		32'h00000073  // SYSTEM
	  };
	  inst1 inside {
		32'h00000033,
		32'h00000013,
		32'h00002003,
		32'h00002023,
		32'h00000063,
		32'h0000006F,
		32'h00000067,
		32'h00000037,
		32'h00000073
	  };
	}
  endclass

  // ============================================================
  // Pending packet (single driver model for fetch_in_*)
  // ============================================================
  typedef struct packed {
	logic        valid;
	logic [31:0] pc;
	logic [63:0] bundle;
	logic [1:0]  pred;
	logic        ff;
	logic        fp;
  } in_pkt_t;

  in_pkt_t pend_q;

  // ============================================================
  // Output stall snapshot (for stability checks)
  // ============================================================
  typedef struct packed {
	bit          v;
	logic [31:0] pc;
	logic [31:0] instr;
	bit          ff, fp;
	bit          exec, lsu, br, mul, div, csr, rdv, inv;
  } lane_snap_t;

  lane_snap_t snap0, snap1;

  task automatic take_snapshot();
	snap0.v     = out0_valid_o;
	snap0.pc    = out0_pc_o;
	snap0.instr = out0_instr_o;
	snap0.ff    = out0_fault_fetch_o;
	snap0.fp    = out0_fault_page_o;
	snap0.exec  = out0_instr_exec_o;
	snap0.lsu   = out0_instr_lsu_o;
	snap0.br    = out0_instr_branch_o;
	snap0.mul   = out0_instr_mul_o;
	snap0.div   = out0_instr_div_o;
	snap0.csr   = out0_instr_csr_o;
	snap0.rdv   = out0_instr_rd_valid_o;
	snap0.inv   = out0_instr_invalid_o;

	snap1.v     = out1_valid_o;
	snap1.pc    = out1_pc_o;
	snap1.instr = out1_instr_o;
	snap1.ff    = out1_fault_fetch_o;
	snap1.fp    = out1_fault_page_o;
	snap1.exec  = out1_instr_exec_o;
	snap1.lsu   = out1_instr_lsu_o;
	snap1.br    = out1_instr_branch_o;
	snap1.mul   = out1_instr_mul_o;
	snap1.div   = out1_instr_div_o;
	snap1.csr   = out1_instr_csr_o;
	snap1.rdv   = out1_instr_rd_valid_o;
	snap1.inv   = out1_instr_invalid_o;
  endtask

  task automatic check_stability_if_stalled();
	if (snap0.v && !out0_accept_i) begin
	  tb_expect(out0_valid_o == snap0.v,     "lane0 valid changed during stall");
	  tb_expect(out0_pc_o    == snap0.pc,    "lane0 pc changed during stall");
	  tb_expect(out0_instr_o == snap0.instr, "lane0 instr changed during stall");
	  tb_expect(out0_fault_fetch_o == snap0.ff, "lane0 fault_fetch changed during stall");
	  tb_expect(out0_fault_page_o  == snap0.fp, "lane0 fault_page changed during stall");

	  tb_expect(out0_instr_exec_o == snap0.exec, "lane0 exec flag changed during stall");
	  tb_expect(out0_instr_lsu_o  == snap0.lsu,  "lane0 lsu flag changed during stall");
	  tb_expect(out0_instr_branch_o==snap0.br,   "lane0 branch flag changed during stall");
	  tb_expect(out0_instr_mul_o  == snap0.mul,  "lane0 mul flag changed during stall");
	  tb_expect(out0_instr_div_o  == snap0.div,  "lane0 div flag changed during stall");
	  tb_expect(out0_instr_csr_o  == snap0.csr,  "lane0 csr flag changed during stall");
	  tb_expect(out0_instr_rd_valid_o == snap0.rdv, "lane0 rd_valid changed during stall");
	  tb_expect(out0_instr_invalid_o  == snap0.inv, "lane0 invalid changed during stall");
	end

	if (snap1.v && !out1_accept_i) begin
	  tb_expect(out1_valid_o == snap1.v,     "lane1 valid changed during stall");
	  tb_expect(out1_pc_o    == snap1.pc,    "lane1 pc changed during stall");
	  tb_expect(out1_instr_o == snap1.instr, "lane1 instr changed during stall");
	  tb_expect(out1_fault_fetch_o == snap1.ff, "lane1 fault_fetch changed during stall");
	  tb_expect(out1_fault_page_o  == snap1.fp, "lane1 fault_page changed during stall");

	  tb_expect(out1_instr_exec_o == snap1.exec, "lane1 exec flag changed during stall");
	  tb_expect(out1_instr_lsu_o  == snap1.lsu,  "lane1 lsu flag changed during stall");
	  tb_expect(out1_instr_branch_o==snap1.br,   "lane1 branch flag changed during stall");
	  tb_expect(out1_instr_mul_o  == snap1.mul,  "lane1 mul flag changed during stall");
	  tb_expect(out1_instr_div_o  == snap1.div,  "lane1 div flag changed during stall");
	  tb_expect(out1_instr_csr_o  == snap1.csr,  "lane1 csr flag changed during stall");
	  tb_expect(out1_instr_rd_valid_o == snap1.rdv, "lane1 rd_valid changed during stall");
	  tb_expect(out1_instr_invalid_o  == snap1.inv, "lane1 invalid changed during stall");
	end
  endtask

  task automatic check_functional_rules();
	bit fault0, fault1;
	bit inv, ex, ls, br, mu, di, cs, rdv;

	fault0 = (out0_fault_fetch_o | out0_fault_page_o);
	fault1 = (out1_fault_fetch_o | out1_fault_page_o);

	if (out0_valid_o && fault0)
	  tb_expect(out0_instr_o == 32'b0, "lane0 instr not forced 0 on fault");
	if (out1_valid_o && fault1)
	  tb_expect(out1_instr_o == 32'b0, "lane1 instr not forced 0 on fault");

	if (out0_valid_o) begin
	  classify_instr(out0_instr_o, 1'b1, fault0, MULDIV, inv, ex, ls, br, mu, di, cs, rdv);
	  tb_expect(out0_instr_invalid_o == inv, "lane0 invalid flag mismatch");
	  tb_expect(out0_instr_exec_o    == ex,  "lane0 exec flag mismatch");
	  tb_expect(out0_instr_lsu_o     == ls,  "lane0 lsu flag mismatch");
	  tb_expect(out0_instr_branch_o  == br,  "lane0 branch flag mismatch");
	  tb_expect(out0_instr_mul_o     == mu,  "lane0 mul flag mismatch");
	  tb_expect(out0_instr_div_o     == di,  "lane0 div flag mismatch");
	  tb_expect(out0_instr_csr_o     == cs,  "lane0 csr flag mismatch");
	  tb_expect(out0_instr_rd_valid_o== rdv, "lane0 rd_valid flag mismatch");
	end

	if (out1_valid_o) begin
	  classify_instr(out1_instr_o, 1'b1, fault1, MULDIV, inv, ex, ls, br, mu, di, cs, rdv);
	  tb_expect(out1_instr_invalid_o == inv, "lane1 invalid flag mismatch");
	  tb_expect(out1_instr_exec_o    == ex,  "lane1 exec flag mismatch");
	  tb_expect(out1_instr_lsu_o     == ls,  "lane1 lsu flag mismatch");
	  tb_expect(out1_instr_branch_o  == br,  "lane1 branch flag mismatch");
	  tb_expect(out1_instr_mul_o     == mu,  "lane1 mul flag mismatch");
	  tb_expect(out1_instr_div_o     == di,  "lane1 div flag mismatch");
	  tb_expect(out1_instr_csr_o     == cs,  "lane1 csr flag mismatch");
	  tb_expect(out1_instr_rd_valid_o== rdv, "lane1 rd_valid flag mismatch");
	end
  endtask

  // ============================================================
  // Output accepts: randomized stalls (SINGLE driver - always_comb)
  // ============================================================
  always_comb begin
	out0_accept_i = 1'b0;
	out1_accept_i = 1'b0;

	if (out0_valid_o) out0_accept_i = ($urandom_range(0,99) < 70);
	if (out1_valid_o) out1_accept_i = ($urandom_range(0,99) < 70);
  end




  // -----------------------------
  // Random transaction object
  // -----------------------------
  decode_txn tr;
  
  // ============================================================
  // SINGLE DRIVER for fetch_in_* and branch_* (always_ff only!)
  // ============================================================
  always_ff @(posedge clk or negedge rst_ni) begin
	if (!rst_ni) begin
	  fetch_in_valid_i       <= 1'b0;
	  fetch_in_pc_i          <= '0;
	  fetch_in_bundle_i      <= '0;
	  fetch_in_pred_branch_i <= 2'b00;
	  fetch_in_fault_fetch_i <= 1'b0;
	  fetch_in_fault_page_i  <= 1'b0;

	  branch_request_i <= 1'b0;
	  branch_pc_i      <= '0;
	  branch_priv_i    <= '0;

	  pend_q <= '0;
	end else begin
	  // default: no flush
	  branch_request_i <= 1'b0;
	  branch_pc_i      <= '0;
	  branch_priv_i    <= 2'b00;

	  // if pending: drive stable until accept
	  if (pend_q.valid) begin
		fetch_in_valid_i       <= 1'b1;
		fetch_in_pc_i          <= pend_q.pc;
		fetch_in_bundle_i      <= pend_q.bundle;
		fetch_in_pred_branch_i <= pend_q.pred;
		fetch_in_fault_fetch_i <= pend_q.ff;
		fetch_in_fault_page_i  <= pend_q.fp;

		if (fetch_in_accept_o) begin
		  pend_q.valid <= 1'b0;
		end
	  end else begin
		  // idle: no pending packet being held
		  fetch_in_valid_i <= 1'b0;

		  void'(tr.randomize());

		  // optional flush (independent of accept)
		  if (tr.do_flush) begin
			branch_request_i <= 1'b1;
		  end

		  // optional push -> create pending
		  // (pending is what will actually be driven until accepted)
		  if (tr.do_push) begin
			pend_q.valid  <= 1'b1;
			pend_q.pc     <= tr.pc_base;
			pend_q.bundle <= {tr.inst1, tr.inst0};
			pend_q.pred   <= tr.pred;
			pend_q.ff     <= tr.fault_fetch;
			pend_q.fp     <= tr.fault_page;
		  end
		end

	end
  end

  // ============================================================
  // Main
  // ============================================================
  int cycles = 2000;

  initial begin
	// reset only touches rst_ni (does NOT assign fetch_in_* here)
	rst_ni = 1'b0;
	repeat (5) @(posedge clk);
	rst_ni = 1'b1;
	
	tr = new();

	// warm-up
	repeat (5) @(posedge clk);

	take_snapshot();

	for (int t = 0; t < cycles; t++) begin
	  // check stability relative to previous snapshot
	  check_stability_if_stalled();

	  @(posedge clk);

	  // check functional behavior
	  check_functional_rules();

	  take_snapshot();
	end

	$display("\nCONSTRAINED-RANDOM TEST PASSED ✅ (cycles=%0d, EXTRA=%0d)\n", cycles, EXTRA);
	$finish;
  end

endmodule
