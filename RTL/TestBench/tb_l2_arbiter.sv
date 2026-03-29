`timescale 1ns/1ps

module tb_l2_arbiter;

	localparam int NUM_PORTS = 4;
	localparam int IDX_W     = (NUM_PORTS <= 1) ? 1 : $clog2(NUM_PORTS);

	logic                 clk_i;
	logic                 rst_i;
	logic [NUM_PORTS-1:0] req_i;
	logic                 accept_i;
	logic                 grant_valid_o;
	logic [IDX_W-1:0]     grant_idx_o;
	logic [NUM_PORTS-1:0] grant_onehot_o;

	l2_arbiter #(
		.NUM_PORTS(NUM_PORTS)
	) dut (
		.clk_i          (clk_i),
		.rst_i          (rst_i),
		.req_i          (req_i),
		.accept_i       (accept_i),
		.grant_valid_o  (grant_valid_o),
		.grant_idx_o    (grant_idx_o),
		.grant_onehot_o (grant_onehot_o)
	);

	logic [IDX_W-1:0] model_rr_ptr_q;

	int pass_count;
	int fail_count;
	int test_count;

	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	task automatic check_bit(
		input string name,
		input logic  got,
		input logic  exp
	);
		begin
			test_count++;
			if (got !== exp) begin
				fail_count++;
				$display("[FAIL] %s got=%b exp=%b t=%0t", name, got, exp, $time);
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic check_idx(
		input string        name,
		input [IDX_W-1:0]   got,
		input [IDX_W-1:0]   exp
	);
		begin
			test_count++;
			if (got !== exp) begin
				fail_count++;
				$display("[FAIL] %s got=%0d exp=%0d t=%0t", name, got, exp, $time);
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic check_onehot(
		input string              name,
		input [NUM_PORTS-1:0]     got,
		input [NUM_PORTS-1:0]     exp
	);
		begin
			test_count++;
			if (got !== exp) begin
				fail_count++;
				$display("[FAIL] %s got=%b exp=%b t=%0t", name, got, exp, $time);
			end
			else begin
				pass_count++;
			end
		end
	endtask

	function automatic logic model_grant_valid(
		input logic [NUM_PORTS-1:0] req,
		input logic [IDX_W-1:0]     ptr
	);
		int j;
		int idx;
		begin
			model_grant_valid = 1'b0;
			for (j = 0; j < NUM_PORTS; j++) begin
				idx = ptr + j;
				if (idx >= NUM_PORTS)
					idx = idx - NUM_PORTS;
				if (req[idx]) begin
					model_grant_valid = 1'b1;
				end
			end
		end
	endfunction

	function automatic [IDX_W-1:0] model_grant_idx(
		input logic [NUM_PORTS-1:0] req,
		input logic [IDX_W-1:0]     ptr
	);
		int j;
		int idx;
		begin
			model_grant_idx = ptr;
			for (j = 0; j < NUM_PORTS; j++) begin
				idx = ptr + j;
				if (idx >= NUM_PORTS)
					idx = idx - NUM_PORTS;
				if (req[idx]) begin
					model_grant_idx = idx[IDX_W-1:0];
					return model_grant_idx;
				end
			end
		end
	endfunction

	function automatic [NUM_PORTS-1:0] model_grant_onehot(
		input logic [NUM_PORTS-1:0] req,
		input logic [IDX_W-1:0]     ptr
	);
		automatic logic [NUM_PORTS-1:0] tmp;
		automatic logic [IDX_W-1:0]     idx;
		begin
			tmp = '0;
			if (model_grant_valid(req, ptr)) begin
				idx = model_grant_idx(req, ptr);
				tmp[idx] = 1'b1;
			end
			return tmp;
		end
	endfunction

	task automatic drive_and_check(
			input logic [NUM_PORTS-1:0] req,
			input logic                 accept
		);
			automatic logic                 exp_valid;
			automatic logic [IDX_W-1:0]     exp_idx;
			automatic logic [NUM_PORTS-1:0] exp_onehot;
			begin
				exp_valid  = model_grant_valid(req, model_rr_ptr_q);
				exp_idx    = model_grant_idx(req, model_rr_ptr_q);
				exp_onehot = model_grant_onehot(req, model_rr_ptr_q);

				@(negedge clk_i);
				req_i    = req;
				accept_i = accept;
				#1;

				// Check combinational outputs BEFORE pointer update on posedge
				check_bit("grant_valid", grant_valid_o, exp_valid);

				if (exp_valid) begin
					check_idx("grant_idx", grant_idx_o, exp_idx);
					check_onehot("grant_onehot", grant_onehot_o, exp_onehot);
				end
				else begin
					check_onehot("grant_onehot_idle", grant_onehot_o, '0);
				end

				@(posedge clk_i);
				#1;

				if (exp_valid && accept) begin
					if (exp_idx == NUM_PORTS-1)
						model_rr_ptr_q = '0;
					else
						model_rr_ptr_q = exp_idx + 1'b1;
				end
			end
	endtask
	
	task automatic advance_ptr_to(
			input logic [IDX_W-1:0] target_ptr
		);
			begin
				while (model_rr_ptr_q !== target_ptr) begin
					// Force an accepted grant so both DUT and model advance together
					drive_and_check({NUM_PORTS{1'b1}}, 1'b1);
				end
			end
		endtask

	task automatic reset_dut();
		begin
			rst_i = 1'b1;
			req_i = '0;
			accept_i = 1'b0;
			model_rr_ptr_q = '0;

			repeat (3) @(posedge clk_i);
			#1;

			rst_i = 1'b0;
			@(posedge clk_i);
			#1;

			check_bit("reset_grant_valid_zero", grant_valid_o, 1'b0);
			check_onehot("reset_grant_onehot_zero", grant_onehot_o, '0);
		end
	endtask

	task automatic test_no_request();
		begin
			$display("[TEST] no_request");
			drive_and_check(4'b0000, 1'b0);
			drive_and_check(4'b0000, 1'b1);
		end
	endtask

	task automatic test_single_request_each_port();
		begin
			$display("[TEST] single_request_each_port");
			drive_and_check(4'b0001, 1'b1);
			drive_and_check(4'b0010, 1'b1);
			drive_and_check(4'b0100, 1'b1);
			drive_and_check(4'b1000, 1'b1);
		end
	endtask

	task automatic test_round_robin_rotation();
		begin
			$display("[TEST] round_robin_rotation");
			model_rr_ptr_q = '0;

			drive_and_check(4'b1111, 1'b1); // expect 0
			drive_and_check(4'b1111, 1'b1); // expect 1
			drive_and_check(4'b1111, 1'b1); // expect 2
			drive_and_check(4'b1111, 1'b1); // expect 3
			drive_and_check(4'b1111, 1'b1); // expect 0
		end
	endtask

	task automatic test_hold_when_not_accepted();
		begin
			$display("[TEST] hold_when_not_accepted");

			advance_ptr_to(2'd1);

			drive_and_check(4'b1111, 1'b0); // expect 1, ptr stays 1
			drive_and_check(4'b1111, 1'b0); // expect 1 again
			drive_and_check(4'b1111, 1'b1); // accept now, ptr becomes 2
			drive_and_check(4'b1111, 1'b1); // expect 2
		end
	endtask

	task automatic test_sparse_patterns();
		begin
			$display("[TEST] sparse_patterns");

			advance_ptr_to(2'd2);

			drive_and_check(4'b0101, 1'b1);
			drive_and_check(4'b0101, 1'b1);
			drive_and_check(4'b1010, 1'b1);
			drive_and_check(4'b1001, 1'b1);
			drive_and_check(4'b0011, 1'b1);
		end
	endtask

	task automatic test_cov_directed();
		begin
			$display("[TEST] cov_directed");

			advance_ptr_to(2'd0);
			drive_and_check(4'b0001, 1'b1);
			drive_and_check(4'b0010, 1'b1);
			drive_and_check(4'b0100, 1'b1);
			drive_and_check(4'b1000, 1'b1);

			advance_ptr_to(2'd0);
			drive_and_check(4'b1111, 1'b0);
			drive_and_check(4'b1111, 1'b1);

			advance_ptr_to(2'd1);
			drive_and_check(4'b1111, 1'b1);

			advance_ptr_to(2'd2);
			drive_and_check(4'b1111, 1'b1);

			advance_ptr_to(2'd3);
			drive_and_check(4'b1111, 1'b1);

			drive_and_check(4'b0000, 1'b0);
		end
	endtask
	
	
	task automatic test_random(int iterations);
		logic [NUM_PORTS-1:0] rand_req;
		logic                 rand_accept;
		int                   i;
		begin
			$display("[TEST] random");
			for (i = 0; i < iterations; i++) begin
				rand_req    = $urandom_range(0, (1 << NUM_PORTS) - 1);
				rand_accept = $urandom_range(0, 1);
				drive_and_check(rand_req, rand_accept);
			end
		end
	endtask

	// -------------------------------------------------------------------------
	// Coverage
	// -------------------------------------------------------------------------
	logic [NUM_PORTS-1:0] cov_req_q;
	logic                 cov_accept_q;
	logic                 cov_grant_valid_q;
	logic [IDX_W-1:0]     cov_grant_idx_q;

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			cov_req_q         <= '0;
			cov_accept_q      <= 1'b0;
			cov_grant_valid_q <= 1'b0;
			cov_grant_idx_q   <= '0;
		end
		else begin
			cov_req_q         <= req_i;
			cov_accept_q      <= accept_i;
			cov_grant_valid_q <= grant_valid_o;
			cov_grant_idx_q   <= grant_idx_o;
		end
	end

	covergroup cg_l2_arbiter @(posedge clk_i);
		option.per_instance = 1;

		cp_req_count: coverpoint $countones(cov_req_q) {
			bins zero = {0};
			bins one  = {1};
			bins two  = {2};
			bins three = {3};
			bins four = {4};
		}

		cp_accept: coverpoint cov_accept_q {
			bins no  = {0};
			bins yes = {1};
		}

		cp_grant_valid: coverpoint cov_grant_valid_q {
			bins no  = {0};
			bins yes = {1};
		}

		cp_grant_idx: coverpoint cov_grant_idx_q iff (cov_grant_valid_q) {
			bins p0 = {0};
			bins p1 = {1};
			bins p2 = {2};
			bins p3 = {3};
		}

		x_req_accept: cross cp_req_count, cp_accept;
		x_grant_accept: cross cp_grant_idx, cp_accept;
	endgroup

	cg_l2_arbiter cg_inst;

	initial begin
		pass_count = 0;
		fail_count = 0;
		test_count = 0;
		cg_inst = new();

		$display("[TEST] l2_arbiter_reset");
		reset_dut();

		test_no_request();
		test_single_request_each_port();
		test_round_robin_rotation();
		test_hold_when_not_accepted();
		test_sparse_patterns();
		test_cov_directed();
		test_random(1000);

		$display("==================================================");
		$display("L2_ARBITER TB SUMMARY");
		$display("  test_count = %0d", test_count);
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cg_inst.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

	initial begin
		$dumpfile("tb_l2_arbiter.vcd");
		$dumpvars(0, tb_l2_arbiter);
	end

endmodule