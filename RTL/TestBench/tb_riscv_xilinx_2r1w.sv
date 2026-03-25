`timescale 1ns/1ps

module tb_riscv_xilinx_2r1w;

	localparam int RANDOM_ITERS = 1000;

	logic        clk_i;
	logic        rst_i;
	logic [4:0]  rd0_i;
	logic [31:0] rd0_value_i;
	logic [4:0]  ra_i;
	logic [4:0]  rb_i;
	logic [31:0] ra_value_o;
	logic [31:0] rb_value_o;

	int test_count;
	int pass_count;
	int fail_count;

	logic [31:0] model_regs [0:31];

	riscv_xilinx_2r1w dut (
		.clk_i(clk_i),
		.rst_i(rst_i),
		.rd0_i(rd0_i),
		.rd0_value_i(rd0_value_i),
		.ra_i(ra_i),
		.rb_i(rb_i),
		.ra_value_o(ra_value_o),
		.rb_value_o(rb_value_o)
	);

	// ------------------------------------------------------------
	// Clock
	// ------------------------------------------------------------
	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	// ------------------------------------------------------------
	// FSDB / Waves
	// ------------------------------------------------------------
	initial begin
		$fsdbDumpfile("tb_riscv_xilinx_2r1w.fsdb");
		$fsdbDumpvars(0, tb_riscv_xilinx_2r1w, "+all");
	end

	// ------------------------------------------------------------
	// Coverage
	// ------------------------------------------------------------
	covergroup cg @(posedge clk_i);
		option.per_instance = 1;

		cp_wr : coverpoint rd0_i {
			bins x0   = {5'd0};
			bins low  = {[5'd1:5'd15]};
			bins high = {[5'd16:5'd31]};
		}

		cp_ra : coverpoint ra_i {
			bins x0   = {5'd0};
			bins low  = {[5'd1:5'd15]};
			bins high = {[5'd16:5'd31]};
		}

		cp_rb : coverpoint rb_i {
			bins x0   = {5'd0};
			bins low  = {[5'd1:5'd15]};
			bins high = {[5'd16:5'd31]};
		}

		cp_same_read : coverpoint (ra_i == rb_i) {
			bins no  = {0};
			bins yes = {1};
		}

		cp_write_zero : coverpoint (rd0_i == 5'd0) {
			bins no  = {0};
			bins yes = {1};
		}

		wr_x_ra : cross cp_wr, cp_ra;
		wr_x_rb : cross cp_wr, cp_rb;
	endgroup

	cg cov = new();

	// ------------------------------------------------------------
	// Helpers
	// ------------------------------------------------------------
	task automatic init_inputs();
	begin
		rd0_i       = '0;
		rd0_value_i = '0;
		ra_i        = '0;
		rb_i        = '0;
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
		input logic [4:0]  wr_addr,
		input logic [31:0] wr_data
	);
	begin
		if (wr_addr != 5'd0)
			model_regs[wr_addr] = wr_data;

		model_regs[0] = 32'h00000000;
	end
	endtask

	task automatic check_outputs(input string tag);
		logic [31:0] exp_ra;
		logic [31:0] exp_rb;
	begin
		#1;
		exp_ra = model_read(ra_i);
		exp_rb = model_read(rb_i);

		if (ra_value_o !== exp_ra) begin
			$display("[FAIL] %s ra mismatch addr=%0d got=%h exp=%h",
					 tag, ra_i, ra_value_o, exp_ra);
			fail_count++;
		end
		else begin
			pass_count++;
		end

		if (rb_value_o !== exp_rb) begin
			$display("[FAIL] %s rb mismatch addr=%0d got=%h exp=%h",
					 tag, rb_i, rb_value_o, exp_rb);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	end
	endtask

	task automatic do_write_cycle(
		input logic [4:0]  wr_addr,
		input logic [31:0] wr_data,
		input logic [4:0]  ra_after,
		input logic [4:0]  rb_after,
		input string       tag
	);
	begin
		rd0_i       = wr_addr;
		rd0_value_i = wr_data;

		@(posedge clk_i);
		#1;
		model_write(wr_addr, wr_data);

		rd0_i       = 5'd0;
		rd0_value_i = 32'h0;

		ra_i = ra_after;
		rb_i = rb_after;

		test_count++;
		check_outputs(tag);
	end
	endtask

	task automatic do_read_check(
		input logic [4:0] ra,
		input logic [4:0] rb,
		input string      tag
	);
	begin
		ra_i = ra;
		rb_i = rb;
		check_outputs(tag);
	end
	endtask

	// ------------------------------------------------------------
	// Tests
	// ------------------------------------------------------------
	task automatic test_reset();
		int i;
	begin
		$display("\n[TEST] reset");

		rst_i = 1'b1;
		init_inputs();
		reset_model();

		repeat (3) @(posedge clk_i);
		#1;
		rst_i = 1'b0;
		@(posedge clk_i);
		#1;

		for (i = 0; i < 32; i++) begin
			do_read_check(i[4:0], 5'd0, $sformatf("reset_r%0d", i));
		end
	end
	endtask

	task automatic test_single_write_read();
	begin
		$display("\n[TEST] single_write_read");

		do_write_cycle(5'd5,  32'h12345678, 5'd5,  5'd0, "wr_x5");
		do_read_check (5'd5,  5'd0, "rd_x5");

		do_write_cycle(5'd20, 32'hAABBCCDD, 5'd20, 5'd5, "wr_x20");
		do_read_check (5'd20, 5'd5, "rd_x20_x5");
	end
	endtask

	task automatic test_x0_immutable();
	begin
		$display("\n[TEST] x0_immutable");

		do_write_cycle(5'd0, 32'hFFFFFFFF, 5'd0, 5'd0, "wr_x0");
		do_read_check(5'd0, 5'd0, "rd_x0");
	end
	endtask

	task automatic test_bank_a_bank_b();
	begin
		$display("\n[TEST] bank_a_bank_b");

		do_write_cycle(5'd3,  32'h03030303, 5'd3,  5'd0,  "wr_bank_a");
		do_write_cycle(5'd19, 32'h19191919, 5'd19, 5'd0,  "wr_bank_b");

		do_read_check(5'd3,  5'd19, "rd_a_b");
		do_read_check(5'd19, 5'd3,  "rd_b_a");
	end
	endtask

	task automatic test_same_read_ports();
	begin
		$display("\n[TEST] same_read_ports");

		do_write_cycle(5'd11, 32'h1111AAAA, 5'd11, 5'd11, "wr_x11");
		do_read_check(5'd11, 5'd11, "same_port_read");
	end
	endtask

	task automatic test_overwrite();
	begin
		$display("\n[TEST] overwrite");

		do_write_cycle(5'd7, 32'h11111111, 5'd7, 5'd0, "wr1_x7");
		do_write_cycle(5'd7, 32'h22222222, 5'd7, 5'd0, "wr2_x7");
		do_read_check(5'd7, 5'd0, "rd_overwrite_x7");
	end
	endtask

	task automatic test_async_read_changes();
	begin
		$display("\n[TEST] async_read_changes");

		do_write_cycle(5'd8,  32'h88888888, 5'd8,  5'd0, "wr_x8");
		do_write_cycle(5'd24, 32'h24242424, 5'd24, 5'd0, "wr_x24");

		ra_i = 5'd8;  rb_i = 5'd24; check_outputs("async0");
		ra_i = 5'd24; rb_i = 5'd8;  check_outputs("async1");
		ra_i = 5'd0;  rb_i = 5'd8;  check_outputs("async2");
	end
	endtask

	task automatic test_random();
		int k;
		logic [4:0]  wr_addr;
		logic [31:0] wr_data;
		logic [4:0]  ra_rand;
		logic [4:0]  rb_rand;
	begin
		$display("\n[TEST] random");

		for (k = 0; k < RANDOM_ITERS; k++) begin
			wr_addr = $urandom_range(0,31);
			wr_data = $urandom();
			ra_rand = $urandom_range(0,31);
			rb_rand = $urandom_range(0,31);

			rd0_i       = wr_addr;
			rd0_value_i = wr_data;

			@(posedge clk_i);
			#1;
			model_write(wr_addr, wr_data);

			rd0_i       = 5'd0;
			rd0_value_i = 32'h0;

			ra_i = ra_rand;
			rb_i = rb_rand;

			test_count++;
			check_outputs($sformatf("random_%0d", k));
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
		test_x0_immutable();
		test_bank_a_bank_b();
		test_same_read_ports();
		test_overwrite();
		test_async_read_changes();
		test_random();

		$display("\n==================================================");
		$display("XILINX 2R1W TB SUMMARY");
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