`timescale 1ns/1ps

module tb_dcache_axi_fifo;

	localparam int WIDTH  = 77;
	localparam int DEPTH  = 2;
	localparam int ADDR_W = 1;

	logic             clk_i;
	logic             rst_i;
	logic [WIDTH-1:0] data_in_i;
	logic             push_i;
	logic             pop_i;

	logic [WIDTH-1:0] data_out_o;
	logic             accept_o;
	logic             valid_o;

	dcache_axi_fifo #(
		.WIDTH (WIDTH),
		.DEPTH (DEPTH),
		.ADDR_W(ADDR_W)
	) dut (
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.data_in_i  (data_in_i),
		.push_i     (push_i),
		.pop_i      (pop_i),
		.data_out_o (data_out_o),
		.accept_o   (accept_o),
		.valid_o    (valid_o)
	);

	// ------------------------------------------------------------
	// Clock
	// ------------------------------------------------------------
	initial clk_i = 1'b0;
	always #5 clk_i = ~clk_i;

	// ------------------------------------------------------------
	// Reference model
	// ------------------------------------------------------------
	logic [WIDTH-1:0] model_q[$];

	int pass_count;
	int fail_count;

	// ------------------------------------------------------------
	// Coverage
	// ------------------------------------------------------------
	covergroup cg_fifo @(posedge clk_i);
		cp_push   : coverpoint push_i;
		cp_pop    : coverpoint pop_i;
		cp_valid  : coverpoint valid_o;
		cp_accept : coverpoint accept_o;
		cp_combo  : cross cp_push, cp_pop, cp_valid, cp_accept;
	endgroup

	cg_fifo cov_fifo = new();

	// ------------------------------------------------------------
	// Helpers
	// ------------------------------------------------------------
	task automatic tick();
		@(posedge clk_i);
		#1;
	endtask

	task automatic reset_dut();
		rst_i     = 1'b1;
		push_i    = 1'b0;
		pop_i     = 1'b0;
		data_in_i = '0;
		model_q.delete();
		repeat (3) tick();
		rst_i = 1'b0;
		tick();
	endtask

	task automatic check_outputs(string msg);
		logic [WIDTH-1:0] exp_data;
		logic             exp_valid;
		logic             exp_accept;

		exp_valid  = (model_q.size() != 0);
		exp_accept = (model_q.size() != DEPTH);
		exp_data   = exp_valid ? model_q[0] : 'x;

		if (valid_o !== exp_valid) begin
			$display("[FAIL] %s : valid_o got=%0b exp=%0b", msg, valid_o, exp_valid);
			fail_count++;
		end
		else if (accept_o !== exp_accept) begin
			$display("[FAIL] %s : accept_o got=%0b exp=%0b", msg, accept_o, exp_accept);
			fail_count++;
		end
		else if (exp_valid && data_out_o !== exp_data) begin
			$display("[FAIL] %s : data_out_o got=%h exp=%h", msg, data_out_o, exp_data);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic apply_cycle(
			input logic [WIDTH-1:0] din,
			input logic             do_push,
			input logic             do_pop,
			input [8*40-1:0]       name
		);
			integer old_size;
			bit can_push;
			bit can_pop;

			begin
				// Drive inputs for this cycle
				data_in_i = din;
				push_i    = do_push;
				pop_i     = do_pop;

				// Decide push/pop legality based on OLD model state
				old_size = model_q.size();
				can_push = do_push && (old_size < DEPTH);
				can_pop  = do_pop  && (old_size > 0);

				// Advance one clock
				tick();

				// Update model according to OLD state legality
				if (can_pop)
					model_q.pop_front();

				if (can_push)
					model_q.push_back(din);

				// Check DUT outputs after state update
				check_outputs(name);
			end
		endtask

	// ------------------------------------------------------------
	// Directed tests
	// ------------------------------------------------------------
	task automatic test_reset();
		$display("[TEST] fifo_reset");
		check_outputs("after reset");
	endtask

	task automatic test_push_pop_basic();
		logic [WIDTH-1:0] a, b;
		$display("[TEST] fifo_push_pop_basic");

		a = 77'h1234_5678_9abc_def0_11;
		b = 77'h0fed_cba9_8765_4321_22;

		apply_cycle(a, 1'b1, 1'b0, "push a");
		apply_cycle(b, 1'b1, 1'b0, "push b");
		apply_cycle('0, 1'b0, 1'b0, "hold full");
		apply_cycle('0, 1'b0, 1'b1, "pop a");
		apply_cycle('0, 1'b0, 1'b1, "pop b");
		apply_cycle('0, 1'b0, 1'b0, "empty hold");
	endtask

	task automatic test_simultaneous_push_pop();
		logic [WIDTH-1:0] a, b, c;
		$display("[TEST] fifo_simultaneous_push_pop");

		a = 77'h1;
		b = 77'h2;
		c = 77'h3;

		apply_cycle(a, 1'b1, 1'b0, "push a");
		apply_cycle(b, 1'b1, 1'b1, "push b pop a");
		apply_cycle(c, 1'b1, 1'b1, "push c pop b");
		apply_cycle('0,1'b0, 1'b1, "pop c");
	endtask

	// ------------------------------------------------------------
	// Random test
	// ------------------------------------------------------------
	task automatic test_random(int ncycles = 200);
		logic [WIDTH-1:0] rnd_data;
		logic rnd_push, rnd_pop;

		$display("[TEST] fifo_random");

		for (int i = 0; i < ncycles; i++) begin
			rnd_data = {$urandom, $urandom, $urandom} >> 19;
			rnd_push = $urandom_range(0,1);
			rnd_pop  = $urandom_range(0,1);
			apply_cycle(rnd_data, rnd_push, rnd_pop, $sformatf("rand_%0d", i));
		end
	endtask

	// ------------------------------------------------------------
	// Main
	// ------------------------------------------------------------
	initial begin
		pass_count = 0;
		fail_count = 0;

		reset_dut();

		test_reset();
		test_push_pop_basic();
		test_simultaneous_push_pop();
		test_random(300);

		$display("==================================================");
		$display("FIFO TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule