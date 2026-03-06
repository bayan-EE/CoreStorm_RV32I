`timescale 1ns/1ps



module tb_riscv_multiplier;

  localparam int CLK_PERIOD  = 10;
  localparam int RANDOM_TESTS = 500;
  localparam int MULT_STAGES  = 2; // Must match DUT localparam

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
  logic         hold_i;

  logic [31:0]  writeback_value_o;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv_multiplier dut (
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
	  .hold_i             (hold_i),
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
	OP_MUL    = 0,
	OP_MULH   = 1,
	OP_MULHSU = 2,
	OP_MULHU  = 3
  } mul_op_e;

  int cov_op;
  bit cov_a_neg;
  bit cov_b_neg;
  bit cov_a_zero;
  bit cov_b_zero;
  bit cov_a_all1;
  bit cov_b_all1;

  covergroup cg_mul;
	  option.per_instance = 1;

	  cp_op: coverpoint cov_op {
		bins mul    = {OP_MUL};
		bins mulh   = {OP_MULH};
		bins mulhsu = {OP_MULHSU};
		bins mulhu  = {OP_MULHU};
	  }

	  cp_a_neg: coverpoint cov_a_neg;
	  cp_b_neg: coverpoint cov_b_neg;
	  cp_a_zero: coverpoint cov_a_zero;
	  cp_b_zero: coverpoint cov_b_zero;
	  cp_a_all1: coverpoint cov_a_all1;
	  cp_b_all1: coverpoint cov_b_all1;

	  cross_op_signs: cross cp_op, cp_a_neg, cp_b_neg;
	  cross_op_zero : cross cp_op, cp_a_zero, cp_b_zero;
	endgroup

  cg_mul mul_cov = new();

  // ------------------------------------------------------------
  // Helper functions
  // ------------------------------------------------------------
  function automatic [31:0] expected_mul_result(
	  input mul_op_e op_sel,
	  input logic [31:0] a,
	  input logic [31:0] b
  );
	logic signed [31:0] sa;
	logic signed [31:0] sb;
	logic signed [63:0] ss_prod;
	logic signed [63:0] su_prod;
	logic        [63:0] uu_prod;

	begin
	  sa = a;
	  sb = b;

	  ss_prod = sa * sb;
	  su_prod = sa * $signed({1'b0, b});
	  uu_prod = a * b;

	  case (op_sel)
		OP_MUL   : expected_mul_result = uu_prod[31:0];
		OP_MULH  : expected_mul_result = ss_prod[63:32];
		OP_MULHSU: expected_mul_result = su_prod[63:32];
		OP_MULHU : expected_mul_result = uu_prod[63:32];
		default  : expected_mul_result = '0;
	  endcase
	end
  endfunction

  function automatic logic [31:0] opcode_from_sel(input mul_op_e op_sel);
	begin
	  case (op_sel)
		OP_MUL   : opcode_from_sel = `INST_MUL;
		OP_MULH  : opcode_from_sel = `INST_MULH;
		OP_MULHSU: opcode_from_sel = `INST_MULHSU;
		OP_MULHU : opcode_from_sel = `INST_MULHU;
		default  : opcode_from_sel = `INST_MUL;
	  endcase
	end
  endfunction

  task automatic sample_cov(
	  input mul_op_e op_sel,
	  input logic [31:0] a,
	  input logic [31:0] b
  );
	begin
	  cov_op     = op_sel;
	  cov_a_neg  = a[31];
	  cov_b_neg  = b[31];
	  cov_a_zero = (a == 32'h0);
	  cov_b_zero = (b == 32'h0);
	  cov_a_all1 = (a == 32'hFFFF_FFFF);
	  cov_b_all1 = (b == 32'hFFFF_FFFF);
	  mul_cov.sample();
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
	  hold_i              = 1'b0;
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
  // Main checker
  // ------------------------------------------------------------
  task automatic run_one_test(
	  input mul_op_e op_sel,
	  input logic [31:0] a,
	  input logic [31:0] b,
	  input string test_name
  );
	logic [31:0] exp;
	logic [31:0] got;
	int k;
	begin
	  exp = expected_mul_result(op_sel, a, b);
	  test_count++;

	  // Drive one-cycle request
	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b1;
	  opcode_opcode_i     <= opcode_from_sel(op_sel);
	  opcode_ra_operand_i <= a;
	  opcode_rb_operand_i <= b;
	  opcode_pc_i         <= 32'h1000 + test_count;
	  opcode_invalid_i    <= 1'b0;
	  opcode_rd_idx_i     <= 5'd1;
	  opcode_ra_idx_i     <= 5'd2;
	  opcode_rb_idx_i     <= 5'd3;
	  hold_i              <= 1'b0;

	  sample_cov(op_sel, a, b);

	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b0;
	  opcode_opcode_i     <= '0;
	  opcode_ra_operand_i <= '0;
	  opcode_rb_operand_i <= '0;

	  // Wait for actual output latency.
	  // For this DUT:
	  //   MULT_STAGES=2 -> output is valid after 1 cycle
	  //   MULT_STAGES=3 -> output is valid after 2 cycles
	  for (k = 0; k < (MULT_STAGES - 1); k++)
		@(posedge clk_i);

	  #1;
	  got = writeback_value_o;

	  if (got !== exp) begin
		fail_count++;
		$display("[FAIL][MUL] %s op=%0d a=%h b=%h got=%h exp=%h time=%0t",
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
	  $display("\n[TEST] Multiplier directed tests");

	  run_one_test(OP_MUL   , 32'd0         , 32'd0         , "MUL zero_zero");
	  run_one_test(OP_MUL   , 32'd1         , 32'd1         , "MUL one_one");
	  run_one_test(OP_MUL   , 32'd3         , 32'd7         , "MUL small_pos");
	  run_one_test(OP_MUL   , 32'hFFFF_FFFF , 32'd2         , "MUL all1_x2");

	  run_one_test(OP_MULH  , 32'h0000_0002 , 32'h0000_0003 , "MULH small");
	  run_one_test(OP_MULH  , 32'hFFFF_FFFF , 32'd2         , "MULH neg_x_pos");
	  run_one_test(OP_MULH  , 32'h8000_0000 , 32'h0000_0002 , "MULH minint_x2");
	  run_one_test(OP_MULH  , 32'h8000_0000 , 32'hFFFF_FFFF , "MULH minint_x_minus1");

	  run_one_test(OP_MULHSU, 32'hFFFF_FFFF , 32'd2         , "MULHSU neg_x_u2");
	  run_one_test(OP_MULHSU, 32'h8000_0000 , 32'hFFFF_FFFF , "MULHSU minint_x_umax");

	  run_one_test(OP_MULHU , 32'hFFFF_FFFF , 32'hFFFF_FFFF , "MULHU max_x_max");
	  run_one_test(OP_MULHU , 32'h8000_0000 , 32'h0000_0002 , "MULHU msb_x_2");
	end
  endtask

  // ------------------------------------------------------------
  // Random tests
  // ------------------------------------------------------------
  task automatic run_random_tests;
	mul_op_e op_sel;
	logic [31:0] a;
	logic [31:0] b;
	int i;
	begin
	  $display("\n[TEST] Multiplier random tests");

	  for (i = 0; i < RANDOM_TESTS; i++) begin
		op_sel = mul_op_e'($urandom_range(0, 3));
		a      = $urandom();
		b      = $urandom();

		// Inject corner cases periodically
		case (i % 12)
		  0: a = 32'h0000_0000;
		  1: b = 32'h0000_0000;
		  2: a = 32'hFFFF_FFFF;
		  3: b = 32'hFFFF_FFFF;
		  4: a = 32'h8000_0000;
		  5: b = 32'h8000_0000;
		  6: a = 32'h0000_0001;
		  7: b = 32'h0000_0001;
		  default: ;
		endcase

		run_one_test(op_sel, a, b, $sformatf("random_%0d", i));
	  end
	end
  endtask

  // ------------------------------------------------------------
  // Optional hold test
  // ------------------------------------------------------------
  task automatic run_hold_test;
	  logic [31:0] exp;
	  logic [31:0] got;
	begin
	  $display("\n[TEST] Multiplier hold test");

	  exp = expected_mul_result(OP_MULH, 32'h8000_0000, 32'h0000_0002);

	  // Drive request
	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b1;
	  opcode_opcode_i     <= `INST_MULH;
	  opcode_ra_operand_i <= 32'h8000_0000;
	  opcode_rb_operand_i <= 32'h0000_0002;
	  opcode_pc_i         <= 32'h3000;
	  opcode_invalid_i    <= 1'b0;
	  opcode_rd_idx_i     <= 5'd1;
	  opcode_ra_idx_i     <= 5'd2;
	  opcode_rb_idx_i     <= 5'd3;
	  hold_i              <= 1'b0;

	  sample_cov(OP_MULH, 32'h8000_0000, 32'h0000_0002);

	  // Remove request
	  @(posedge clk_i);
	  opcode_valid_i      <= 1'b0;
	  opcode_opcode_i     <= '0;
	  opcode_ra_operand_i <= '0;
	  opcode_rb_operand_i <= '0;

	  // Stall the pipeline for one cycle
	  hold_i <= 1'b1;
	  @(posedge clk_i);

	  // Release hold
	  hold_i <= 1'b0;

	  // On the very next clock, E2 should capture the held multiply result
	  @(posedge clk_i);
	  #1;
	  got = writeback_value_o;

	  if (got !== exp) begin
		fail_count++;
		$display("[FAIL][MUL] hold_test got=%h exp=%h", got, exp);
	  end
	  else begin
		pass_count++;
	  end
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
	run_hold_test();

	$display("\n==================================================");
	$display("MULTIPLIER TB SUMMARY");
	$display("  test_count = %0d", test_count);
	$display("  pass_count = %0d", pass_count);
	$display("  fail_count = %0d", fail_count);
	$display("  coverage   = %0.2f %%", mul_cov.get_inst_coverage());
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