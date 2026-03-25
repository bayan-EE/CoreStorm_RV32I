`timescale 1ns/1ps

module tb_dport_mux;

	localparam logic [31:0] TCM_MEM_BASE = 32'h0000_0000;

	logic         clk;
	logic         rst;
	logic [31:0]  mem_addr_i;
	logic [31:0]  mem_data_wr_i;
	logic         mem_rd_i;
	logic [3:0]   mem_wr_i;
	logic         mem_cacheable_i;
	logic [10:0]  mem_req_tag_i;
	logic         mem_invalidate_i;
	logic         mem_writeback_i;
	logic         mem_flush_i;
	logic [31:0]  mem_tcm_data_rd_i;
	logic         mem_tcm_accept_i;
	logic         mem_tcm_ack_i;
	logic         mem_tcm_error_i;
	logic [10:0]  mem_tcm_resp_tag_i;
	logic [31:0]  mem_ext_data_rd_i;
	logic         mem_ext_accept_i;
	logic         mem_ext_ack_i;
	logic         mem_ext_error_i;
	logic [10:0]  mem_ext_resp_tag_i;

	logic [31:0]  mem_data_rd_o;
	logic         mem_accept_o;
	logic         mem_ack_o;
	logic         mem_error_o;
	logic [10:0]  mem_resp_tag_o;
	logic [31:0]  mem_tcm_addr_o;
	logic [31:0]  mem_tcm_data_wr_o;
	logic         mem_tcm_rd_o;
	logic [3:0]   mem_tcm_wr_o;
	logic         mem_tcm_cacheable_o;
	logic [10:0]  mem_tcm_req_tag_o;
	logic         mem_tcm_invalidate_o;
	logic         mem_tcm_writeback_o;
	logic         mem_tcm_flush_o;
	logic [31:0]  mem_ext_addr_o;
	logic [31:0]  mem_ext_data_wr_o;
	logic         mem_ext_rd_o;
	logic [3:0]   mem_ext_wr_o;
	logic         mem_ext_cacheable_o;
	logic [10:0]  mem_ext_req_tag_o;
	logic         mem_ext_invalidate_o;
	logic         mem_ext_writeback_o;
	logic         mem_ext_flush_o;

	int pass_count;
	int fail_count;

	dport_mux #(
		.TCM_MEM_BASE(TCM_MEM_BASE)
	) dut (
		.clk_i(clk),
		.rst_i(rst),
		.mem_addr_i(mem_addr_i),
		.mem_data_wr_i(mem_data_wr_i),
		.mem_rd_i(mem_rd_i),
		.mem_wr_i(mem_wr_i),
		.mem_cacheable_i(mem_cacheable_i),
		.mem_req_tag_i(mem_req_tag_i),
		.mem_invalidate_i(mem_invalidate_i),
		.mem_writeback_i(mem_writeback_i),
		.mem_flush_i(mem_flush_i),
		.mem_tcm_data_rd_i(mem_tcm_data_rd_i),
		.mem_tcm_accept_i(mem_tcm_accept_i),
		.mem_tcm_ack_i(mem_tcm_ack_i),
		.mem_tcm_error_i(mem_tcm_error_i),
		.mem_tcm_resp_tag_i(mem_tcm_resp_tag_i),
		.mem_ext_data_rd_i(mem_ext_data_rd_i),
		.mem_ext_accept_i(mem_ext_accept_i),
		.mem_ext_ack_i(mem_ext_ack_i),
		.mem_ext_error_i(mem_ext_error_i),
		.mem_ext_resp_tag_i(mem_ext_resp_tag_i),
		.mem_data_rd_o(mem_data_rd_o),
		.mem_accept_o(mem_accept_o),
		.mem_ack_o(mem_ack_o),
		.mem_error_o(mem_error_o),
		.mem_resp_tag_o(mem_resp_tag_o),
		.mem_tcm_addr_o(mem_tcm_addr_o),
		.mem_tcm_data_wr_o(mem_tcm_data_wr_o),
		.mem_tcm_rd_o(mem_tcm_rd_o),
		.mem_tcm_wr_o(mem_tcm_wr_o),
		.mem_tcm_cacheable_o(mem_tcm_cacheable_o),
		.mem_tcm_req_tag_o(mem_tcm_req_tag_o),
		.mem_tcm_invalidate_o(mem_tcm_invalidate_o),
		.mem_tcm_writeback_o(mem_tcm_writeback_o),
		.mem_tcm_flush_o(mem_tcm_flush_o),
		.mem_ext_addr_o(mem_ext_addr_o),
		.mem_ext_data_wr_o(mem_ext_data_wr_o),
		.mem_ext_rd_o(mem_ext_rd_o),
		.mem_ext_wr_o(mem_ext_wr_o),
		.mem_ext_cacheable_o(mem_ext_cacheable_o),
		.mem_ext_req_tag_o(mem_ext_req_tag_o),
		.mem_ext_invalidate_o(mem_ext_invalidate_o),
		.mem_ext_writeback_o(mem_ext_writeback_o),
		.mem_ext_flush_o(mem_ext_flush_o)
	);

	initial begin
		clk = 0;
		forever #5 clk = ~clk;
	end

	covergroup cg_mux @(posedge clk);
		cp_tcm_req : coverpoint ((mem_addr_i >= TCM_MEM_BASE) && (mem_addr_i < TCM_MEM_BASE + 32'd65536));
		cp_rd      : coverpoint mem_rd_i;
		cp_wr      : coverpoint (mem_wr_i != 0);
		cp_ack     : coverpoint mem_ack_o;
		cp_err     : coverpoint mem_error_o;
		cp_inv     : coverpoint mem_invalidate_i;
		cp_wb      : coverpoint mem_writeback_i;
		cp_flush   : coverpoint mem_flush_i;
		cross cp_tcm_req, cp_rd, cp_wr;
	endgroup
	cg_mux cov = new();

	task tick(input int n = 1);
		repeat (n) @(posedge clk);
	endtask

	task check_bit(input string name, input logic got, input logic exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0b exp=%0b t=%0t", name, got, exp, $time);
			fail_count++;
		end else pass_count++;
	endtask

	task check32(input string name, input logic [31:0] got, input logic [31:0] exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%08x exp=%08x t=%0t", name, got, exp, $time);
			fail_count++;
		end else pass_count++;
	endtask

	task check11(input string name, input logic [10:0] got, input logic [10:0] exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0d exp=%0d t=%0t", name, got, exp, $time);
			fail_count++;
		end else pass_count++;
	endtask

	task reset_dut();
		rst                 = 1'b1;
		mem_addr_i          = '0;
		mem_data_wr_i       = '0;
		mem_rd_i            = 1'b0;
		mem_wr_i            = 4'b0000;
		mem_cacheable_i     = 1'b0;
		mem_req_tag_i       = '0;
		mem_invalidate_i    = 1'b0;
		mem_writeback_i     = 1'b0;
		mem_flush_i         = 1'b0;
		mem_tcm_data_rd_i   = 32'h1111_1111;
		mem_tcm_accept_i    = 1'b1;
		mem_tcm_ack_i       = 1'b0;
		mem_tcm_error_i     = 1'b0;
		mem_tcm_resp_tag_i  = 11'h01;
		mem_ext_data_rd_i   = 32'h2222_2222;
		mem_ext_accept_i    = 1'b1;
		mem_ext_ack_i       = 1'b0;
		mem_ext_error_i     = 1'b0;
		mem_ext_resp_tag_i  = 11'h02;
		tick(3);
		rst = 1'b0;
		tick(1);
	endtask

	task test_tcm_route();
		$display("[TEST] tcm_route");

		mem_addr_i       = 32'h0000_0010;
		mem_data_wr_i    = 32'hABCD_EF01;
		mem_wr_i         = 4'b1111;
		mem_req_tag_i    = 11'h12;
		mem_invalidate_i = 1'b1;
		mem_writeback_i  = 1'b1;
		mem_flush_i      = 1'b1;
		#1;

		check_bit("tcm_wr_enable", mem_tcm_wr_o != 0, 1'b1);
		check_bit("ext_wr_disable", mem_ext_wr_o != 0, 1'b0);
		check32("tcm_addr", mem_tcm_addr_o, 32'h0000_0010);
		check32("tcm_wdata", mem_tcm_data_wr_o, 32'hABCD_EF01);
		check11("tcm_tag", mem_tcm_req_tag_o, 11'h12);
	endtask

	task test_ext_route();
		$display("[TEST] ext_route");

		mem_addr_i       = 32'h0001_1000;
		mem_rd_i         = 1'b1;
		mem_req_tag_i    = 11'h55;
		#1;

		check_bit("ext_rd_enable", mem_ext_rd_o, 1'b1);
		check_bit("tcm_rd_disable", mem_tcm_rd_o, 1'b0);
		check32("ext_addr", mem_ext_addr_o, 32'h0001_1000);
		check11("ext_tag", mem_ext_req_tag_o, 11'h55);

		mem_rd_i = 1'b0;
	endtask

	task test_response_select();
		$display("[TEST] response_select");

		// Issue TCM request
		mem_addr_i = 32'h0000_0020;
		mem_rd_i   = 1'b1;
		tick(1);
		mem_rd_i   = 1'b0;

		mem_tcm_ack_i      = 1'b1;
		mem_tcm_data_rd_i  = 32'hAAAA_5555;
		mem_tcm_resp_tag_i = 11'h21;
		#1;
		check_bit("tcm_ack_seen", mem_ack_o, 1'b1);
		check32("tcm_data_seen", mem_data_rd_o, 32'hAAAA_5555);
		check11("tcm_tag_seen", mem_resp_tag_o, 11'h21);

		tick(1);
		mem_tcm_ack_i = 1'b0;

		// Issue EXT request
		mem_addr_i = 32'h0002_0000;
		mem_rd_i   = 1'b1;
		tick(1);
		mem_rd_i   = 1'b0;

		mem_ext_ack_i      = 1'b1;
		mem_ext_data_rd_i  = 32'h1234_5678;
		mem_ext_resp_tag_i = 11'h45;
		#1;
		check_bit("ext_ack_seen", mem_ack_o, 1'b1);
		check32("ext_data_seen", mem_data_rd_o, 32'h1234_5678);
		check11("ext_tag_seen", mem_resp_tag_o, 11'h45);

		tick(1);
		mem_ext_ack_i = 1'b0;
	endtask

	task test_hold_behavior();
		$display("[TEST] hold_behavior");

		// --------------------------------------------------
		// Step 1: issue one TCM request and let it be accepted
		// --------------------------------------------------
		mem_addr_i = 32'h0000_0010;   // TCM region
		mem_rd_i   = 1'b1;

		tick(1);   // request accepted here

		// Remove first request
		mem_rd_i   = 1'b0;

		// IMPORTANT:
		// Give one extra cycle so pending_q / tcm_access_q are fully visible
		tick(1);

		// --------------------------------------------------
		// Step 2: now try an EXT request while TCM request pending
		// This should be blocked by hold_w
		// --------------------------------------------------
		mem_addr_i = 32'h0002_0000;   // EXT region
		mem_rd_i   = 1'b1;

		#1;
		check_bit("hold_accept_low", mem_accept_o, 1'b0);
		check_bit("hold_ext_rd_low", mem_ext_rd_o, 1'b0);

		// --------------------------------------------------
		// Step 3: complete the original TCM request
		// --------------------------------------------------
		mem_tcm_ack_i = 1'b1;
		tick(1);
		mem_tcm_ack_i = 1'b0;

		// One more cycle for pending_q to drop
		tick(1);

		// --------------------------------------------------
		// Step 4: now the EXT request should be allowed
		// --------------------------------------------------
		#1;
		check_bit("after_release_accept", mem_accept_o, 1'b1);
		check_bit("after_release_ext_rd", mem_ext_rd_o, 1'b1);

		mem_rd_i = 1'b0;
	endtask

	task test_random();
		logic use_tcm;
		logic do_read;
		logic do_write;
		logic [31:0] addr;

		$display("[TEST] random");

		repeat (200) begin
			use_tcm  = $urandom_range(0,1);
			do_read  = $urandom_range(0,1);
			do_write = !do_read;
			addr     = use_tcm ? (TCM_MEM_BASE + $urandom_range(0, 16'hFFFC)) :
								 (32'h0002_0000 + $urandom_range(0, 16'hFFFC));

			mem_addr_i       = {addr[31:2], 2'b00};
			mem_data_wr_i    = $urandom();
			mem_rd_i         = do_read;
			mem_wr_i         = do_write ? (4'b0001 << $urandom_range(0,3)) : 4'b0000;
			mem_req_tag_i    = $urandom_range(0, 2047);
			mem_invalidate_i = $urandom_range(0,1);
			mem_writeback_i  = $urandom_range(0,1);
			mem_flush_i      = $urandom_range(0,1);

			if (use_tcm) begin
				mem_tcm_accept_i   = 1'b1;
				mem_ext_accept_i   = 1'b1;
				mem_tcm_ack_i      = $urandom_range(0,1);
				mem_tcm_data_rd_i  = $urandom();
				mem_tcm_resp_tag_i = mem_req_tag_i;
				mem_tcm_error_i    = $urandom_range(0,1);
				mem_ext_ack_i      = 1'b0;
			end
			else begin
				mem_tcm_accept_i   = 1'b1;
				mem_ext_accept_i   = 1'b1;
				mem_ext_ack_i      = $urandom_range(0,1);
				mem_ext_data_rd_i  = $urandom();
				mem_ext_resp_tag_i = mem_req_tag_i;
				mem_ext_error_i    = $urandom_range(0,1);
				mem_tcm_ack_i      = 1'b0;
			end

			tick(1);
		end

		mem_rd_i = 0;
		mem_wr_i = 0;
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;

		reset_dut();
		test_tcm_route();
		reset_dut();
		test_ext_route();
		reset_dut();
		test_response_select();
		reset_dut();
		test_hold_behavior();
		reset_dut();
		test_random();

		$display("======================================");
		$display("DPORT_MUX TB SUMMARY");
		$display("pass_count = %0d", pass_count);
		$display("fail_count = %0d", fail_count);
		$display("======================================");

		$finish;
	end

endmodule