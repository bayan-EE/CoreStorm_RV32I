`timescale 1ns/1ps

module tb_riscv_regfile;

	localparam int RANDOM_ITERS = 1000;

	logic        clk_i;
	logic        rst_i;
	logic [4:0]  rd0_i;
	logic [4:0]  rd1_i;
	logic [31:0] rd0_value_i;
	logic [31:0] rd1_value_i;
	logic [4:0]  ra0_i;
	logic [4:0]  rb0_i;
	logic [4:0]  ra1_i;
	logic [4:0]  rb1_i;

	logic [31:0] ra0_value_o;
	logic [31:0] rb0_value_o;
	logic [31:0] ra1_value_o;
	logic [31:0] rb1_value_o;

	int test_count;
	int pass_count;
	int fail_count;

	logic [31:0] model_regs [0:31];

	riscv_regfile #(
		.SUPPORT_REGFILE_XILINX(1'b0),
		.SUPPORT_DUAL_ISSUE    (1'b1)
	) dut (
		.clk_i(clk_i),
		.rst_i(rst_i),
		.rd0_i(rd0_i),
		.rd1_i(rd1_i),
		.rd0_value_i(rd0_value_i),
		.rd1_value_i(rd1_value_i),
		.ra0_i(ra0_i),
		.rb0_i(rb0_i),
		.ra1_i(ra1_i),
		.rb1_i(rb1_i),
		.ra0_value_o(ra0_value_o),
		.rb0_value_o(rb0_value_o),
		.ra1_value_o(ra1_value_o),
		.rb1_value_o(rb1_value_o)
	);

	// ------------------------------------------------------------
	// Clock
	// ------------------------------------------------------------
	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	// ------------------------------------------------------------
	// FSDB
	// ------------------------------------------------------------
	initial begin
		$fsdbDumpfile("novas.fsdb");
		$fsdbDumpvars(0, tb_riscv_regfile, "+all");
	end

	// ------------------------------------------------------------
	// Coverage
	// ------------------------------------------------------------
	covergroup cg @(posedge clk_i);
		option.per_instance = 1;

		cp_rd0 : coverpoint rd0_i {
			bins x0   = {5'd0};
			bins low  = {[5'd1:5'd15]};
			bins high = {[5'd16:5'd31]};
		}

		cp_rd1 : coverpoint rd1_i {
			bins x0   = {5'd0};
			bins low  = {[5'd1:5'd15]};
			bins high = {[5'd16:5'd31]};
		}

		cp_ra0 : coverpoint ra0_i {
			bins x0   = {5'd0};
			bins regs[] = {[5'd1:5'd31]};
		}

		cp_rb0 : coverpoint rb0_i {
			bins x0   = {5'd0};
			bins regs[] = {[5'd1:5'd31]};
		}

		cp_ra1 : coverpoint ra1_i {
			bins x0   = {5'd0};
			bins regs[] = {[5'd1:5'd31]};
		}

		cp_rb1 : coverpoint rb1_i {
			bins x0   = {5'd0};
			bins regs[] = {[5'd1:5'd31]};
		}

		cp_same_dest : coverpoint (rd0_i == rd1_i) {
			bins no  = {0};
			bins yes = {1};
		}

		cp_both_nonzero : coverpoint ((rd0_i != 0) && (rd1_i != 0)) {
			bins no  = {0};
			bins yes = {1};
		}

		cross_same : cross cp_same_dest, cp_both_nonzero;
	endgroup

	cg cov = new();

	// ------------------------------------------------------------
	// Helpers
	// ------------------------------------------------------------
	task automatic init_inputs();
	begin
		rd0_i       = '0;
		rd1_i       = '0;
		rd0_value_i = '0;
		rd1_value_i = '0;
		ra0_i       = '0;
		rb0_i       = '0;
		ra1_i       = '0;
		rb1_i       = '0;
	end
	endtask

	task automatic reset_model();
		int i;
	begin
		for (i = 0; i < 32; i++)
			model_regs[i] = 32'h0;
	end
	endtask

	function automatic [31:0] model_read(input logic [4:0] addr);
	begin
		if (addr == 5'd0)
			model_read = 32'h00000000;
		else
			model_read = model_regs[addr];
	end
	endfunction

	task automatic model_write(
		input logic [4:0]  w0,
		input logic [31:0] v0,
		input logic [4:0]  w1,
		input logic [31:0] v1
	);
	begin
		// rd1 קודם, rd0 אחרון => rd0 עדיפות גבוהה יותר
		if (w1 != 5'd0)
			model_regs[w1] = v1;

		if (w0 != 5'd0)
			model_regs[w0] = v0;

		model_regs[5'd0] = 32'h00000000;
	end
	endtask

	task automatic check_reads(input string tag);
		logic [31:0] exp_ra0, exp_rb0, exp_ra1, exp_rb1;
	begin
		#1;
		exp_ra0 = model_read(ra0_i);
		exp_rb0 = model_read(rb0_i);
		exp_ra1 = model_read(ra1_i);
		exp_rb1 = model_read(rb1_i);

		if (ra0_value_o !== exp_ra0) begin
			$display("[FAIL] %s ra0 mismatch addr=%0d got=%h exp=%h",
					 tag, ra0_i, ra0_value_o, exp_ra0);
			fail_count++;
		end
		else pass_count++;

		if (rb0_value_o !== exp_rb0) begin
			$display("[FAIL] %s rb0 mismatch addr=%0d got=%h exp=%h",
					 tag, rb0_i, rb0_value_o, exp_rb0);
			fail_count++;
		end
		else pass_count++;

		if (ra1_value_o !== exp_ra1) begin
			$display("[FAIL] %s ra1 mismatch addr=%0d got=%h exp=%h",
					 tag, ra1_i, ra1_value_o, exp_ra1);
			fail_count++;
		end
		else pass_count++;

		if (rb1_value_o !== exp_rb1) begin
			$display("[FAIL] %s rb1 mismatch addr=%0d got=%h exp=%h",
					 tag, rb1_i, rb1_value_o, exp_rb1);
			fail_count++;
		end
		else pass_count++;
	end
	endtask

	task automatic drive_reads(
		input logic [4:0] a0,
		input logic [4:0] b0,
		input logic [4:0] a1,
		input logic [4:0] b1,
		input string      tag
	);
	begin
		@(negedge clk_i);
		ra0_i = a0;
		rb0_i = b0;
		ra1_i = a1;
		rb1_i = b1;
		check_reads(tag);
	end
	endtask

	task automatic do_write_cycle(
		input logic [4:0]  w0,
		input logic [31:0] v0,
		input logic [4:0]  w1,
		input logic [31:0] v1,
		input string       tag
	);
	begin
		@(negedge clk_i);
		rd0_i       = w0;
		rd1_i       = w1;
		rd0_value_i = v0;
		rd1_value_i = v1;

		@(posedge clk_i);
		model_write(w0, v0, w1, v1);

		@(negedge clk_i);
		rd0_i       = 5'd0;
		rd1_i       = 5'd0;
		rd0_value_i = 32'h0;
		rd1_value_i = 32'h0;

		test_count++;
	end
	endtask

	// ------------------------------------------------------------
	// Tests
	// ------------------------------------------------------------
	task automatic test_reset();
		int i;
	begin
		$display("\n[TEST] reset");

		init_inputs();
		reset_model();

		rst_i = 1'b1;
		repeat (3) @(posedge clk_i);
		rst_i = 1'b0;
		@(negedge clk_i);

		for (i = 0; i < 32; i++) begin
			ra0_i = i[4:0];
			rb0_i = 5'd0;
			ra1_i = 5'd0;
			rb1_i = 5'd0;
			check_reads($sformatf("reset_r%0d", i));
		end
	end
	endtask

	task automatic test_single_write_read();
	begin
		$display("\n[TEST] single_write_read");

		do_write_cycle(5'd5,  32'h11112222, 5'd0, 32'h0, "single_wr_x5");
		drive_reads    (5'd5,  5'd0,        5'd0, 5'd0, "read_x5");

		do_write_cycle(5'd10, 32'hA5A5F00D, 5'd0, 32'h0, "single_wr_x10");
		drive_reads    (5'd10, 5'd5,        5'd0, 5'd0, "read_x10_x5");
	end
	endtask

	task automatic test_dual_write_different_regs();
	begin
		$display("\n[TEST] dual_write_different_regs");

		do_write_cycle(5'd3, 32'h33333333, 5'd7, 32'h77777777, "dual_diff");
		drive_reads    (5'd3, 5'd7,        5'd0, 5'd0,        "dual_diff_read");
	end
	endtask

	task automatic test_same_dest_priority();
	begin
		$display("\n[TEST] same_dest_priority");

		do_write_cycle(5'd9, 32'hDEADBEEF, 5'd9, 32'h12345678, "same_dest");
		drive_reads    (5'd9, 5'd0,        5'd0, 5'd0,        "same_dest_read");
	end
	endtask

	task automatic test_x0_immutable();
	begin
		$display("\n[TEST] x0_immutable");

		do_write_cycle(5'd0, 32'hFFFFFFFF, 5'd0, 32'hAAAAAAAA, "x0_write");
		drive_reads    (5'd0, 5'd0,        5'd0, 5'd0,        "x0_read_all_zero");

		do_write_cycle(5'd0, 32'hFACEFACE, 5'd12, 32'h0C0FFEE0, "x0_plus_valid");
		drive_reads    (5'd0, 5'd12,       5'd0, 5'd0,         "x0_and_x12");
	end
	endtask

	task automatic test_async_reads();
	begin
		$display("\n[TEST] async_reads");

		do_write_cycle(5'd21, 32'h21212121, 5'd22, 32'h22222222, "prep_async");
		drive_reads    (5'd21, 5'd22,       5'd0,  5'd0,        "async_step0");
		drive_reads    (5'd22, 5'd21,       5'd21, 5'd22,       "async_step1");
		drive_reads    (5'd0,  5'd21,       5'd22, 5'd0,        "async_step2");
	end
	endtask

	task automatic test_random();
		int k;
		logic [4:0]  w0, w1;
		logic [31:0] v0, v1;
		logic [4:0]  a0, b0, a1, b1;
	begin
		$display("\n[TEST] random");

		for (k = 0; k < RANDOM_ITERS; k++) begin
			w0 = $urandom_range(0,31);
			w1 = $urandom_range(0,31);
			v0 = $urandom();
			v1 = $urandom();

			do_write_cycle(w0, v0, w1, v1, $sformatf("random_write_%0d", k));

			a0 = $urandom_range(0,31);
			b0 = $urandom_range(0,31);
			a1 = $urandom_range(0,31);
			b1 = $urandom_range(0,31);

			drive_reads(a0, b0, a1, b1, $sformatf("random_%0d", k));
		end
	end
	endtask

	// ------------------------------------------------------------
	// Main
	// ------------------------------------------------------------
	initial begin
		test_count = 0;
		pass_count = 0;
		fail_count = 0;

		init_inputs();
		reset_model();

		test_reset();
		test_single_write_read();
		test_dual_write_different_regs();
		test_same_dest_priority();
		test_x0_immutable();
		test_async_reads();
		test_random();

		$display("\n==================================================");
		$display("REGFILE TB SUMMARY");
		$display("  test_count = %0d", test_count);
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cov.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule