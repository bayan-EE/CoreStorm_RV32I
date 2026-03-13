`timescale 1ns/1ps

module tb_dport_axi_fifo;

	localparam int WIDTH  = 8;
	localparam int DEPTH  = 2;
	localparam int ADDR_W = 1;

	logic             clk;
	logic             rst;
	logic [WIDTH-1:0] data_in;
	logic             push;
	logic             pop;
	logic [WIDTH-1:0] data_out;
	logic             accept;
	logic             valid;

	int pass_count;
	int fail_count;

	dport_axi_fifo #(
		.WIDTH(WIDTH),
		.DEPTH(DEPTH),
		.ADDR_W(ADDR_W)
	) dut (
		.clk_i(clk),
		.rst_i(rst),
		.data_in_i(data_in),
		.push_i(push),
		.pop_i(pop),
		.data_out_o(data_out),
		.accept_o(accept),
		.valid_o(valid)
	);

	initial begin
		clk = 0;
		forever #5 clk = ~clk;
	end

	covergroup cg_fifo @(posedge clk);
		cp_push   : coverpoint push;
		cp_pop    : coverpoint pop;
		cp_valid  : coverpoint valid;
		cp_accept : coverpoint accept;
		cross cp_push, cp_pop;
	endgroup
	cg_fifo cov = new();

	task tick(input int n = 1);
		repeat (n) @(posedge clk);
	endtask

	task check_bit(input string name, input logic got, input logic exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0b exp=%0b t=%0t", name, got, exp, $time);
			fail_count++;
		end else pass_count++;
	endtask

	task check_data(input string name, input logic [WIDTH-1:0] got, input logic [WIDTH-1:0] exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0h exp=%0h t=%0t", name, got, exp, $time);
			fail_count++;
		end else pass_count++;
	endtask

	task reset_dut();
		rst     = 1'b1;
		data_in = '0;
		push    = 1'b0;
		pop     = 1'b0;
		tick(3);
		rst     = 1'b0;
		tick(1);
	endtask

	task test_basic();
		$display("[TEST] fifo_basic");

		check_bit("empty_valid", valid, 1'b0);
		check_bit("empty_accept", accept, 1'b1);

		data_in = 8'hA5;
		push    = 1'b1;
		tick(1);
		push    = 1'b0;

		check_bit("after_push_valid", valid, 1'b1);
		check_data("after_push_data", data_out, 8'hA5);

		pop = 1'b1;
		tick(1);
		pop = 1'b0;

		check_bit("after_pop_valid", valid, 1'b0);
	endtask

	task test_full();
		$display("[TEST] fifo_full");

		data_in = 8'h11; push = 1'b1; tick(1);
		data_in = 8'h22; push = 1'b1; tick(1);
		push = 1'b0;

		check_bit("full_accept", accept, 1'b0);
		check_bit("full_valid", valid, 1'b1);
		check_data("head_data", data_out, 8'h11);

		pop = 1'b1; tick(1); pop = 1'b0;
		check_data("next_data", data_out, 8'h22);
	endtask

	task test_random();
		logic [7:0] model_q[$];
		logic [7:0] val;

		$display("[TEST] fifo_random");

		repeat (100) begin
			push = ($urandom_range(0,1) && (model_q.size() < DEPTH));
			pop  = ($urandom_range(0,1) && (model_q.size() > 0));
			val  = $urandom();

			data_in = val;

			if (push && !pop)
				model_q.push_back(val);
			else if (!push && pop)
				void'(model_q.pop_front());
			else if (push && pop) begin
				if (model_q.size() > 0)
					void'(model_q.pop_front());
				model_q.push_back(val);
			end

			tick(1);

			check_bit("rand_valid", valid, (model_q.size() != 0));
			check_bit("rand_accept", accept, (model_q.size() != DEPTH));
			if (model_q.size() > 0)
				check_data("rand_head", data_out, model_q[0]);
		end

		push = 0;
		pop  = 0;
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;

		reset_dut();
		test_basic();
		reset_dut();
		test_full();
		reset_dut();
		test_random();

		$display("======================================");
		$display("DPORT_AXI_FIFO TB SUMMARY");
		$display("pass_count = %0d", pass_count);
		$display("fail_count = %0d", fail_count);
		$display("======================================");

		$finish;
	end

endmodule