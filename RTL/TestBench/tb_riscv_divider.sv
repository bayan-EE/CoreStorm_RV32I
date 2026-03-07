`timescale 1ns/1ps


module tb_riscv_divider;

  localparam int CLK_PERIOD   = 10;
  localparam int RANDOM_TESTS = 400;

  // ------------------------------------------------------------
  // DUT signals
  // ------------------------------------------------------------
  logic         clk_i;
  logic         rst_i;
  logic         opcode_valid_i;
  logic [31:0]  opcode_opcode_i;
  logic [31:0]  opcode_pc_i;
  logic         opcode_invalid_i;
  logic [4:0]   opcode_rd_idx_i;
  logic [4:0]   opcode_ra_idx_i;
  logic [4:0]   opcode_rb_idx_i;
  logic [31:0]  opcode_ra_operand_i;
  logic [31:0]  opcode_rb_operand_i;

  logic         writeback_valid_o;
  logic [31:0]  writeback_value_o;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv_divider dut (
	  .clk_i              (clk_i),
	  .rst_i              (rst_i),
	  .opcode_valid_i     (opcode_valid_i),
	  .opcode_opcode_i    (opcode_opcode_i),
	  .opcode_pc_i        (opcode_pc_i),
	  .opcode_invalid_i   (opcode_invalid_i),
	  .opcode_rd_idx_i    (opcode_rd_idx_i),
	  .opcode_ra_idx_i    (opcode_ra_idx_i),
	  .opcode_rb_idx_i    (opcode_rb_idx_i),
	  .opcode_ra_operand_i(opcode_ra_operand_i),
	  .opcode_rb_operand_i(opcode_rb_operand_i),
	  .writeback_valid_o  (writeback_valid_o),
	  .writeback_value_o  (writeback_value_o)
  );

  // ------------------------------------------------------------
  // Clock generation
  // ------------------------------------------------------------
  initial clk_i = 1'b0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // ------------------------------------------------------------
  // Statistics
  // ------------------------------------------------------------
  int pass_count;
  int fail_count;
  int test_count;

  // ------------------------------------------------------------
  // Coverage helpers
  // ------------------------------------------------------------
  typedef enum int {
	OP_DIV  = 0,
	OP_DIVU = 1,
	OP_REM  = 2,
	OP_REMU = 3
  } div_op_e;

  int cov_op;
  bit cov_a_neg;
  bit cov_b_neg;
  bit cov_a_zero;
  bit cov_b_zero;
  bit cov_b_is_one;
  bit cov_overflow_case;

  covergroup cg_div ;
	option.per_instance = 1;

	cp_op: coverpoint cov_op {
	  bins div_  = {OP_DIV};
	  bins divu  = {OP_DIVU};
	  bins rem_  = {OP_REM};
	  bins remu  = {OP_REMU};
	}

	cp_a_neg : coverpoint cov_a_neg;
	cp_b_neg : coverpoint cov_b_neg;
	cp_a_zero: coverpoint cov_a_zero;
	cp_b_zero: coverpoint cov_b_zero;
	cp_b_one : coverpoint cov_b_is_one;
	cp_ovf   : coverpoint cov_overflow_case;

	cross_op_signs : cross cp_op, cp_a_neg, cp_b_neg;
	cross_op_zero  : cross cp_op, cp_a_zero, cp_b_zero;
  endgroup

  cg_div div_cov = new();

  // ------------------------------------------------------------
  // Helper functions
  // ------------------------------------------------------------
  function automatic logic [31:0] opcode_from_sel(input div_op_e op_sel);
	begin
	  case (op_sel)
		OP_DIV : opcode_from_sel = `INST_DIV;
		OP_DIVU: opcode_from_sel = `INST_DIVU;
		OP_REM : opcode_from_sel = `INST_REM;
		OP_REMU: opcode_from_sel = `INST_REMU;
		default: opcode_from_sel = `INST_DIV;
	  endcase
	end
  endfunction

  function automatic [31:0] expected_div_result(
	  input div_op_e op_sel,
	  input logic [31:0] a,
	  input logic [31:0] b
  );
	logic signed [31:0] sa;
	logic signed [31:0] sb;
	logic [31:0] ua;
	logic [31:0] ub;

	begin
	  sa = a;
	  sb = b;
	  ua = a;
	  ub = b;

	  case (op_sel)
		OP_DIV: begin
		  if (b == 32'h0)
			expected_div_result = 32'hFFFF_FFFF;
		  else if ((a == 32'h8000_0000) && (b == 32'hFFFF_FFFF))
			expected_div_result = 32'h8000_0000;
		  else
			expected_div_result = sa / sb;
		end

		OP_DIVU: begin
		  if (b == 32'h0)
			expected_div_result = 32'hFFFF_FFFF;
		  else
			expected_div_result = ua / ub;
		end

		OP_REM: begin
		  if (b == 32'h0)
			expected_div_result = a;
		  else if ((a == 32'h8000_0000) && (b == 32'hFFFF_FFFF))
			expected_div_result = 32'h0;
		  else
			expected_div_result = sa % sb;
		end

		OP_REMU: begin
		  if (b == 32'h0)
			expected_div_result = a;
		  else
			expected_div_result = ua % ub;
		end

		default: expected_div_result = '0;
	  endcase
	end
  endfunction

  task automatic sample_cov(
	  input div_op_e op_sel,
	  input logic [31:0] a,
	  input logic [31:0] b
  );
	begin
	  cov_op            = op_sel;
	  cov_a_neg         = a[31];
	  cov_b_neg         = b[31];
	  cov_a_zero        = (a == 32'h0);
	  cov_b_zero        = (b == 32'h0);
	  cov_b_is_one      = (b == 32'h1);
	  cov_overflow_case = (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);
	  div_cov.sample();
	end
  endtask

  // ------------------------------------------------------------
  // Reset / init
  // ------------------------------------------------------------
  task automatic init_signals;
	begin
	  opcode_valid_i      = 1'b0;
	  opcode_opcode_i     = '0;
	  opcode_pc_i         = '0;
	  opcode_invalid_i    = 1'b0;
	  opcode_rd_idx_i     = '0;
	  opcode_ra_idx_i     = '0;
	  opcode_rb_idx_i     = '0;
	  opcode_ra_operand_i = '0;
	  opcode_rb_operand_i = '0;
	end
  endtask

  task automatic reset_dut;
	begin
	  rst_i = 1'b1;
	  init_signals();
	  repeat (5) @(posedge clk_i);
	  rst_i = 1'b0;
	  repeat (2) @(posedge clk_i);
	end
  endtask

  // ------------------------------------------------------------
  // Wait for writeback valid
  // ------------------------------------------------------------
  task automatic wait_for_done(output logic [31:0] got);
	int timeout;
	begin
	  timeout = 0;
	  while (writeback_valid_o !== 1'b1 && timeout < 100) begin
		@(posedge clk_i);
		timeout++;
	  end

	  #1;
	  got = writeback_value_o;

	  if (timeout >= 100) begin
		$display("[FAIL][DIV] timeout waiting for writeback_valid_o at time=%0t", $time);
		fail_count++;
	  end
	end
  endtask

  // ------------------------------------------------------------
  // Main checker
  // ------------------------------------------------------------
  task automatic run_one_test(
	  input div_op_e op_sel,
	  input logic [31:0] a,
	  input logic [31:0] b,
	  input string test_name
  );
	logic [31:0] exp;
	logic [31:0] got;
	begin
	  exp = expected_div_result(op_sel, a, b);
	  test_count++;

	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b1;
	  opcode_opcode_i     <= opcode_from_sel(op_sel);
	  opcode_ra_operand_i <= a;
	  opcode_rb_operand_i <= b;
	  opcode_pc_i         <= 32'h2000 + test_count;
	  opcode_invalid_i    <= 1'b0;
	  opcode_rd_idx_i     <= 5'd1;
	  opcode_ra_idx_i     <= 5'd2;
	  opcode_rb_idx_i     <= 5'd3;

	  sample_cov(op_sel, a, b);

	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b0;
	  opcode_opcode_i     <= '0;
	  opcode_ra_operand_i <= '0;
	  opcode_rb_operand_i <= '0;

	  wait_for_done(got);

	  if (got !== exp) begin
		fail_count++;
		$display("[FAIL][DIV] %s op=%0d a=%h b=%h got=%h exp=%h time=%0t",
				 test_name, op_sel, a, b, got, exp, $time);
	  end
	  else begin
		pass_count++;
	  end
	end
  endtask

  // ------------------------------------------------------------
  // Directed tests
  // ------------------------------------------------------------
  task automatic run_directed_tests;
	begin
	  $display("\n[TEST] Divider directed tests");

	  // DIV
	  run_one_test(OP_DIV , 32'd10        , 32'd2         , "DIV 10/2");
	  run_one_test(OP_DIV , -32'sd10      , 32'd2         , "DIV -10/2");
	  run_one_test(OP_DIV , 32'd10        , -32'sd2       , "DIV 10/-2");
	  run_one_test(OP_DIV , -32'sd10      , -32'sd2       , "DIV -10/-2");
	  run_one_test(OP_DIV , 32'h8000_0000 , 32'hFFFF_FFFF , "DIV overflow");
	  run_one_test(OP_DIV , 32'd123       , 32'd0         , "DIV by zero");

	  // DIVU
	  run_one_test(OP_DIVU, 32'd10        , 32'd3         , "DIVU 10/3");
	  run_one_test(OP_DIVU, 32'hFFFF_FFFF , 32'd2         , "DIVU max/2");
	  run_one_test(OP_DIVU, 32'd123       , 32'd0         , "DIVU by zero");

	  // REM
	  run_one_test(OP_REM , 32'd10        , 32'd3         , "REM 10%3");
	  run_one_test(OP_REM , -32'sd10      , 32'd3         , "REM -10%3");
	  run_one_test(OP_REM , 32'd10        , -32'sd3       , "REM 10%-3");
	  run_one_test(OP_REM , -32'sd10      , -32'sd3       , "REM -10%-3");
	  run_one_test(OP_REM , 32'h8000_0000 , 32'hFFFF_FFFF , "REM overflow");
	  run_one_test(OP_REM , 32'd123       , 32'd0         , "REM by zero");

	  // REMU
	  run_one_test(OP_REMU, 32'd10        , 32'd3         , "REMU 10%3");
	  run_one_test(OP_REMU, 32'hFFFF_FFFF , 32'd256       , "REMU max%256");
	  run_one_test(OP_REMU, 32'd123       , 32'd0         , "REMU by zero");
	end
  endtask

  // ------------------------------------------------------------
  // Random tests
  // ------------------------------------------------------------
  task automatic run_random_tests;
	div_op_e op_sel;
	logic [31:0] a;
	logic [31:0] b;
	int i;
	begin
	  $display("\n[TEST] Divider random tests");

	  for (i = 0; i < RANDOM_TESTS; i++) begin
		op_sel = div_op_e'($urandom_range(0, 3));
		a      = $urandom();
		b      = $urandom();

		// Inject useful corner cases
		case (i % 16)
		  0 : b = 32'h0;
		  1 : b = 32'h1;
		  2 : a = 32'h0;
		  3 : a = 32'h8000_0000;
		  4 : b = 32'hFFFF_FFFF;
		  5 : begin a = 32'h8000_0000; b = 32'hFFFF_FFFF; end
		  6 : a = 32'hFFFF_FFFF;
		  7 : b = 32'h8000_0000;
		  default: ;
		endcase

		run_one_test(op_sel, a, b, $sformatf("random_%0d", i));
	  end
	end
  endtask

  // ------------------------------------------------------------
  // Back-to-back test
  // ------------------------------------------------------------
  task automatic run_back_to_back_test;
	logic [31:0] got;
	logic [31:0] exp;
	begin
	  $display("\n[TEST] Divider back-to-back test");

	  // First operation
	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b1;
	  opcode_opcode_i     <= `INST_DIV;
	  opcode_ra_operand_i <= 32'd100;
	  opcode_rb_operand_i <= 32'd9;
	  sample_cov(OP_DIV, 32'd100, 32'd9);

	  @(posedge clk_i);
	  opcode_valid_i <= 1'b0;

	  wait_for_done(got);
	  exp = expected_div_result(OP_DIV, 32'd100, 32'd9);
	  if (got !== exp) begin
		fail_count++;
		$display("[FAIL][DIV] back_to_back first got=%h exp=%h", got, exp);
	  end else pass_count++;

	  // Second operation immediately after completion
	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b1;
	  opcode_opcode_i     <= `INST_REMU;
	  opcode_ra_operand_i <= 32'hFFFF_FFFF;
	  opcode_rb_operand_i <= 32'd16;
	  sample_cov(OP_REMU, 32'hFFFF_FFFF, 32'd16);

	  @(posedge clk_i);
	  opcode_valid_i <= 1'b0;

	  wait_for_done(got);
	  exp = expected_div_result(OP_REMU, 32'hFFFF_FFFF, 32'd16);
	  if (got !== exp) begin
		fail_count++;
		$display("[FAIL][DIV] back_to_back second got=%h exp=%h", got, exp);
	  end else pass_count++;
	end
  endtask

  // ------------------------------------------------------------
  // Run
  // ------------------------------------------------------------
  initial begin
	pass_count = 0;
	fail_count = 0;
	test_count = 0;

	reset_dut();

	run_directed_tests();
	run_random_tests();
	run_back_to_back_test();

	$display("\n==================================================");
	$display("DIVIDER TB SUMMARY");
	$display("  test_count = %0d", test_count);
	$display("  pass_count = %0d", pass_count);
	$display("  fail_count = %0d", fail_count);
	$display("  coverage   = %0.2f %%", div_cov.get_inst_coverage());
	$display("==================================================");

	if (fail_count == 0) begin
	  $display("TB PASSED");
	end
	else begin
	  $display("TB FAILED");
	end

	$finish;
  end

endmodule