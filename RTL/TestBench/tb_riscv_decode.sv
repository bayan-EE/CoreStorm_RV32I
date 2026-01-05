`timescale 1ns/1ps

module tb_riscv_decode;

  // -----------------------------
  // Clock / Reset
  // -----------------------------
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_ni;

  // -----------------------------
  // DUT signals
  // -----------------------------
  logic        fetch_in_valid_i;
  logic [63:0] fetch_in_bundle_i;      // {inst1,inst0}
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

  // -----------------------------
  // DUT instance (choose extra stage here)
  // -----------------------------
  riscv_decode #(
	.SUPPORT_MULDIV(1'b1),
	.EXTRA_DECODE_STAGE(1'b0)   // תחליף ל-1 אם אתה רוצה לבדוק גם extra stage
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

  // -----------------------------
  // Tiny helpers
  // -----------------------------
  task automatic init_signals();
	begin
	  fetch_in_valid_i       = 0;
	  fetch_in_bundle_i      = '0;
	  fetch_in_pred_branch_i = 2'b00;
	  fetch_in_fault_fetch_i = 0;
	  fetch_in_fault_page_i  = 0;
	  fetch_in_pc_i          = '0;

	  branch_request_i = 0;
	  branch_pc_i      = '0;
	  branch_priv_i    = '0;

	  out0_accept_i = 0;
	  out1_accept_i = 0;
	end
  endtask

  task automatic wait_accept_and_transfer();
	begin
	  // hold valid until accepted
	  while (!fetch_in_accept_o) @(posedge clk);
	  // transfer happens on this cycle (valid&accept)
	  @(posedge clk);
	  fetch_in_valid_i <= 0;
	end
  endtask

  task automatic push_bundle(
	input logic [31:0] pc_base,
	input logic [31:0] inst0,
	input logic [31:0] inst1,
	input logic [1:0]  pred,
	input logic        fault_fetch,
	input logic        fault_page
  );
	begin
	  fetch_in_pc_i          <= pc_base;
	  fetch_in_bundle_i      <= {inst1, inst0};
	  fetch_in_pred_branch_i <= pred;
	  fetch_in_fault_fetch_i <= fault_fetch;
	  fetch_in_fault_page_i  <= fault_page;
	  fetch_in_valid_i       <= 1'b1;

	  wait_accept_and_transfer();
	end
  endtask

  task automatic pop_both_if_valid();
	begin
	  @(posedge clk);
	  out0_accept_i <= out0_valid_o;
	  out1_accept_i <= out1_valid_o;
	  @(posedge clk);
	  out0_accept_i <= 0;
	  out1_accept_i <= 0;
	end
  endtask

  task automatic tb_expect(input bit cond, input string msg);
	if (!cond) begin
	  $fatal("TB_FAIL: %s (t=%0t)", msg, $time);
	end
  endtask

  // ------------------------------------------------------------
  // TESTS
  // ------------------------------------------------------------

  // simple encodings (only opcode bits matter for your classifier)
  localparam logic [31:0] OP_ADD   = 32'h00000033; // opcode 0110011
  localparam logic [31:0] OP_ADDI  = 32'h00000013; // opcode 0010011
  localparam logic [31:0] OP_LW    = 32'h00002003; // opcode 0000011
  localparam logic [31:0] OP_SW    = 32'h00002023; // opcode 0100011
  localparam logic [31:0] OP_BEQ   = 32'h00000063; // opcode 1100011
  localparam logic [31:0] OP_JAL   = 32'h0000006F; // opcode 1101111
  localparam logic [31:0] OP_JALR  = 32'h00000067; // opcode 1100111
  localparam logic [31:0] OP_LUI   = 32'h00000037; // opcode 0110111
  localparam logic [31:0] OP_SYS   = 32'h00000073; // opcode 1110011 (ecall-like)

  // -----------------------------
  // TEST 1: Basic push/pop + PC split
  // -----------------------------
  task automatic test_basic();
	logic [31:0] base;
	begin
	  $display("[T1] basic push/pop + pc split");
	  base = 32'h0000_1000;

	  push_bundle(base, OP_ADD, OP_LW, 2'b00, 1'b0, 1'b0);

	  // wait until outputs appear
	  @(posedge clk);
	  tb_expect(out0_valid_o == 1, "lane0 should be valid after push");
	  tb_expect(out0_pc_o    == {base[31:3],3'b000}, "lane0 PC should be base aligned");
	  tb_expect(out0_instr_o == OP_ADD, "lane0 instr mismatch");

	  // lane1 should also be valid
	  tb_expect(out1_valid_o == 1, "lane1 should be valid when pred[0]=0");
	  tb_expect(out1_pc_o    == {base[31:3],3'b100}, "lane1 PC should be base+4");
	  tb_expect(out1_instr_o == OP_LW, "lane1 instr mismatch");

	  pop_both_if_valid();
	end
  endtask

  // -----------------------------
  // TEST 2: pred[0]=1 kills lane1
  // -----------------------------
  task automatic test_pred_kill();
	logic [31:0] base;
	begin
	  $display("[T2] pred kill lane1");
	  base = 32'h0000_2000;

	  push_bundle(base, OP_JAL, OP_ADDI, 2'b01 /*pred[0]=1*/, 1'b0, 1'b0);

	  @(posedge clk);
	  tb_expect(out0_valid_o == 1, "lane0 valid expected");
	  tb_expect(out1_valid_o == 0, "lane1 must be invalid when pred[0]=1");
	  // pop lane0 only (lane1 isn't valid)
	  out0_accept_i <= 1'b1;
	  @(posedge clk);
	  out0_accept_i <= 1'b0;
	end
  endtask

  // -----------------------------
  // TEST 3: stall stability on lane1 (partial consume)
  // -----------------------------
  task automatic test_stall_stability();
	logic [31:0] base;
	logic [31:0] pc1_hold, i1_hold;
	begin
	  $display("[T3] stall stability lane1");
	  base = 32'h0000_3000;

	  push_bundle(base, OP_SW, OP_BEQ, 2'b00, 1'b0, 1'b0);

	  @(posedge clk);
	  tb_expect(out0_valid_o == 1, "lane0 valid expected");
	  tb_expect(out1_valid_o == 1, "lane1 valid expected");

	  // pop lane0 only, stall lane1
	  pc1_hold = out1_pc_o;
	  i1_hold  = out1_instr_o;

	  out0_accept_i <= 1'b1;
	  out1_accept_i <= 1'b0;
	  @(posedge clk);
	  out0_accept_i <= 1'b0;

	  // lane1 must remain stable for a few cycles
	  repeat (3) begin
		@(posedge clk);
		tb_expect(out1_valid_o == 1, "lane1 should remain valid while not accepted");
		tb_expect(out1_pc_o    == pc1_hold, "lane1 PC changed during stall");
		tb_expect(out1_instr_o == i1_hold,  "lane1 INSTR changed during stall");
	  end

	  // now accept lane1
	  out1_accept_i <= 1'b1;
	  @(posedge clk);
	  out1_accept_i <= 1'b0;
	end
  endtask

  // -----------------------------
  // TEST 4: FIFO full/backpressure (DEPTH=2)
  // -----------------------------
  task automatic test_fifo_full();
	logic [31:0] base0, base1, base2;
	bit          saw_backpressure;
	begin
	  $display("[T4] fifo full/backpressure");
	  base0 = 32'h0000_4000;
	  base1 = 32'h0000_5000;
	  base2 = 32'h0000_6000;

	  // Do NOT pop anything, push 2 entries (depth=2)
	  push_bundle(base0, OP_ADD, OP_LW, 2'b00, 1'b0, 1'b0);
	  push_bundle(base1, OP_ADD, OP_LW, 2'b00, 1'b0, 1'b0);

	  // Now try to push third entry; accept should go low until we pop
	  fetch_in_pc_i          <= base2;
	  fetch_in_bundle_i      <= {OP_LW, OP_ADD};
	  fetch_in_pred_branch_i <= 2'b00;
	  fetch_in_fault_fetch_i <= 0;
	  fetch_in_fault_page_i  <= 0;
	  fetch_in_valid_i       <= 1'b1;

	  // Wait a couple cycles and verify accept is 0 at least once
	  saw_backpressure = 1'b0;
	  repeat (6) begin
		@(posedge clk);
		if (!fetch_in_accept_o) saw_backpressure = 1'b1;
	  end
	  tb_expect(saw_backpressure, "did not observe accept_o low when FIFO should be full");

	  // Pop to free space
	  repeat (4) begin
		@(posedge clk);
		out0_accept_i <= out0_valid_o;
		out1_accept_i <= out1_valid_o;
	  end
	  @(posedge clk);
	  out0_accept_i <= 0;
	  out1_accept_i <= 0;

	  // Now it should eventually accept the pending valid
	  while (!fetch_in_accept_o) @(posedge clk);
	  @(posedge clk);
	  fetch_in_valid_i <= 0;

	  // Drain remaining
	  repeat (10) begin
		@(posedge clk);
		out0_accept_i <= out0_valid_o;
		out1_accept_i <= out1_valid_o;
	  end
	  out0_accept_i <= 0;
	  out1_accept_i <= 0;
	end
  endtask

  // -----------------------------
  // TEST 5: flush clears FIFO
  // -----------------------------
  task automatic test_flush();
	logic [31:0] base0, base1;
	begin
	  $display("[T5] flush clears fifo");
	  base0 = 32'h0000_7000;
	  base1 = 32'h0000_8000;

	  push_bundle(base0, OP_ADD, OP_LW, 2'b00, 1'b0, 1'b0);
	  push_bundle(base1, OP_ADD, OP_LW, 2'b00, 1'b0, 1'b0);

	  // Assert flush
	  @(posedge clk);
	  branch_request_i <= 1'b1;
	  @(posedge clk);
	  branch_request_i <= 1'b0;

	  // After a short time, outputs should be invalid (FIFO empty)
	  repeat (3) @(posedge clk);
	  tb_expect(out0_valid_o == 0, "lane0 should be invalid after flush");
	  tb_expect(out1_valid_o == 0, "lane1 should be invalid after flush");
	end
  endtask

  // -----------------------------
  // TEST 6: faults propagate; instruction forced to 0
  // -----------------------------
  task automatic test_faults();
	logic [31:0] base;
	begin
	  $display("[T6] faults propagate");
	  base = 32'h0000_9000;

	  push_bundle(base, OP_ADD, OP_LW, 2'b00, 1'b1 /*fault_fetch*/, 1'b0);

	  @(posedge clk);
	  tb_expect(out0_valid_o == 1, "lane0 valid expected with fault entry");
	  tb_expect(out0_fault_fetch_o == 1, "lane0 fault_fetch should be 1");
	  tb_expect(out0_instr_o == 32'b0, "lane0 instr should be forced to 0 on fault");

	  // lane1 valid depends on pred; here pred[0]=0 so it should be valid but instr=0
	  tb_expect(out1_valid_o == 1, "lane1 valid expected (pred[0]=0)");
	  tb_expect(out1_fault_fetch_o == 1, "lane1 fault_fetch should be 1");
	  tb_expect(out1_instr_o == 32'b0, "lane1 instr should be forced to 0 on fault");

	  pop_both_if_valid();
	end
  endtask

  // ------------------------------------------------------------
  // Main
  // ------------------------------------------------------------
  initial begin
	rst_ni = 0;
	init_signals();

	repeat (5) @(posedge clk);
	rst_ni = 1;
	repeat (2) @(posedge clk);

	test_basic();
	test_pred_kill();
	test_stall_stability();
	test_fifo_full();
	test_flush();
	test_faults();

	$display("\nALL DECODE TESTS PASSED ✅");
	$finish;
  end

endmodule
