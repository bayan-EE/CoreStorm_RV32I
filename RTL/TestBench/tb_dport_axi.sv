`timescale 1ns/1ps

module tb_dport_axi;

	// ------------------------------------------------------------
	// DUT interface
	// ------------------------------------------------------------
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
	logic         axi_awready_i;
	logic         axi_wready_i;
	logic         axi_bvalid_i;
	logic [1:0]   axi_bresp_i;
	logic         axi_arready_i;
	logic         axi_rvalid_i;
	logic [31:0]  axi_rdata_i;
	logic [1:0]   axi_rresp_i;

	logic [31:0]  mem_data_rd_o;
	logic         mem_accept_o;
	logic         mem_ack_o;
	logic         mem_error_o;
	logic [10:0]  mem_resp_tag_o;
	logic         axi_awvalid_o;
	logic [31:0]  axi_awaddr_o;
	logic         axi_wvalid_o;
	logic [31:0]  axi_wdata_o;
	logic [3:0]   axi_wstrb_o;
	logic         axi_bready_o;
	logic         axi_arvalid_o;
	logic [31:0]  axi_araddr_o;
	logic         axi_rready_o;

	int pass_count;
	int fail_count;
	int random_iters;

	// ------------------------------------------------------------
	// Coverage sampling variables
	// ------------------------------------------------------------
	typedef enum logic [0:0] {OP_READ=1'b0, OP_WRITE=1'b1} op_e;
	typedef enum logic [1:0] {SPLIT_NONE=2'd0, SPLIT_AW_FIRST=2'd1, SPLIT_W_FIRST=2'd2} split_e;

	op_e          cov_op;
	logic         cov_err;
	logic [3:0]   cov_wstrb;
	split_e       cov_split;
	logic         cov_cacheable;
	logic         cov_inv;
	logic         cov_wb;
	logic         cov_flush;

	dport_axi dut (
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
		.axi_awready_i(axi_awready_i),
		.axi_wready_i(axi_wready_i),
		.axi_bvalid_i(axi_bvalid_i),
		.axi_bresp_i(axi_bresp_i),
		.axi_arready_i(axi_arready_i),
		.axi_rvalid_i(axi_rvalid_i),
		.axi_rdata_i(axi_rdata_i),
		.axi_rresp_i(axi_rresp_i),

		.mem_data_rd_o(mem_data_rd_o),
		.mem_accept_o(mem_accept_o),
		.mem_ack_o(mem_ack_o),
		.mem_error_o(mem_error_o),
		.mem_resp_tag_o(mem_resp_tag_o),
		.axi_awvalid_o(axi_awvalid_o),
		.axi_awaddr_o(axi_awaddr_o),
		.axi_wvalid_o(axi_wvalid_o),
		.axi_wdata_o(axi_wdata_o),
		.axi_wstrb_o(axi_wstrb_o),
		.axi_bready_o(axi_bready_o),
		.axi_arvalid_o(axi_arvalid_o),
		.axi_araddr_o(axi_araddr_o),
		.axi_rready_o(axi_rready_o)
	);

	// ------------------------------------------------------------
	// Clock
	// ------------------------------------------------------------
	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	// ------------------------------------------------------------
	// Functional coverage
	// ------------------------------------------------------------
	covergroup cg_axi;
		option.per_instance = 1;

		cp_op : coverpoint cov_op {
			bins read  = {OP_READ};
			bins write = {OP_WRITE};
		}

		cp_err : coverpoint cov_err {
			bins ok  = {1'b0};
			bins err = {1'b1};
		}

		cp_wstrb : coverpoint cov_wstrb iff (cov_op == OP_WRITE) {
			bins byte0   = {4'b0001};
			bins byte1   = {4'b0010};
			bins byte2   = {4'b0100};
			bins byte3   = {4'b1000};
			bins half_lo = {4'b0011};
			bins half_hi = {4'b1100};
			bins word    = {4'b1111};
		}

		cp_split : coverpoint cov_split iff (cov_op == OP_WRITE) {
			bins none     = {SPLIT_NONE};
			bins aw_first = {SPLIT_AW_FIRST};
			bins w_first  = {SPLIT_W_FIRST};
		}

		cp_cacheable : coverpoint cov_cacheable {
			bins no  = {1'b0};
			bins yes = {1'b1};
		}

		cp_inv : coverpoint cov_inv {
			bins no  = {1'b0};
			bins yes = {1'b1};
		}

		cp_wb : coverpoint cov_wb {
			bins no  = {1'b0};
			bins yes = {1'b1};
		}

		cp_flush : coverpoint cov_flush {
			bins no  = {1'b0};
			bins yes = {1'b1};
		}

		cross cp_op, cp_err;
	endgroup

	cg_axi cov = new();

	// ------------------------------------------------------------
	// FSDB
	// ------------------------------------------------------------
	initial begin
		$fsdbDumpfile("novas.fsdb");
		$fsdbDumpvars(0, tb_dport_axi);
	end

	// ------------------------------------------------------------
	// Helpers
	// ------------------------------------------------------------
	task automatic tick(input int n = 1);
		repeat (n) @(posedge clk);
	endtask

	task automatic check_bit(input string name, input logic got, input logic exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0b exp=%0b t=%0t", name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic check32(input string name, input logic [31:0] got, input logic [31:0] exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%08x exp=%08x t=%0t", name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic check11(input string name, input logic [10:0] got, input logic [10:0] exp);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0d exp=%0d t=%0t", name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic drive_idle();
		mem_addr_i       = 32'b0;
		mem_data_wr_i    = 32'b0;
		mem_rd_i         = 1'b0;
		mem_wr_i         = 4'b0000;
		mem_cacheable_i  = 1'b0;
		mem_req_tag_i    = 11'b0;
		mem_invalidate_i = 1'b0;
		mem_writeback_i  = 1'b0;
		mem_flush_i      = 1'b0;

		axi_awready_i    = 1'b1;
		axi_wready_i     = 1'b1;
		axi_bvalid_i     = 1'b0;
		axi_bresp_i      = 2'b00;
		axi_arready_i    = 1'b1;
		axi_rvalid_i     = 1'b0;
		axi_rdata_i      = 32'b0;
		axi_rresp_i      = 2'b00;
	endtask

	task automatic reset_dut();
		rst = 1'b1;
		drive_idle();
		tick(4);
		rst = 1'b0;
		tick(2);
	endtask

	// ------------------------------------------------------------
	// Transaction tasks
	// ------------------------------------------------------------

	task automatic do_read_txn(
		input logic [31:0] addr,
		input logic [10:0] tag,
		input logic [31:0] rdata,
		input logic        err,
		input logic        cacheable = 1'b0,
		input logic        inval     = 1'b0,
		input logic        wb        = 1'b0,
		input logic        flush     = 1'b0
	);
		// Coverage bookkeeping
		cov_op        = OP_READ;
		cov_err       = err;
		cov_wstrb     = 4'b0000;
		cov_split     = SPLIT_NONE;
		cov_cacheable = cacheable;
		cov_inv       = inval;
		cov_wb        = wb;
		cov_flush     = flush;

		// Issue request
		mem_addr_i       = addr;
		mem_data_wr_i    = 32'b0;
		mem_req_tag_i    = tag;
		mem_rd_i         = 1'b1;
		mem_wr_i         = 4'b0000;
		mem_cacheable_i  = cacheable;
		mem_invalidate_i = inval;
		mem_writeback_i  = wb;
		mem_flush_i      = flush;

		// Push request into FIFO
		tick(1);
		#1;
		check_bit("read_accept", mem_accept_o, 1'b1);
		check_bit("arvalid_seen", axi_arvalid_o, 1'b1);
		check32("araddr_seen", axi_araddr_o, addr & 32'hFFFF_FFFC);

		// Remove request
		mem_rd_i         = 1'b0;
		mem_invalidate_i = 1'b0;
		mem_writeback_i  = 1'b0;
		mem_flush_i      = 1'b0;

		// One cycle for request_pending to go active
		tick(1);

		// Return response
		axi_rvalid_i = 1'b1;
		axi_rdata_i  = rdata;
		axi_rresp_i  = err ? 2'b10 : 2'b00;

		// Outputs are registered in DUT
		tick(1);
		#1;
		check_bit("read_ack",   mem_ack_o, 1'b1);
		check11 ("read_tag",    mem_resp_tag_o, tag);
		check32 ("read_data",   mem_data_rd_o, rdata);
		check_bit("read_error", mem_error_o, err);

		cov.sample();

		// Clear response
		axi_rvalid_i = 1'b0;
		axi_rresp_i  = 2'b00;
		tick(1);
	endtask


	task automatic do_write_txn(
		input logic [31:0] addr,
		input logic [31:0] wdata,
		input logic [3:0]  wstrb,
		input logic [10:0] tag,
		input logic        err,
		input split_e      split_mode = SPLIT_NONE,
		input logic        cacheable  = 1'b0,
		input logic        inval      = 1'b0,
		input logic        wb         = 1'b0,
		input logic        flush      = 1'b0
	);
		// Coverage bookkeeping
		cov_op        = OP_WRITE;
		cov_err       = err;
		cov_wstrb     = wstrb;
		cov_split     = split_mode;
		cov_cacheable = cacheable;
		cov_inv       = inval;
		cov_wb        = wb;
		cov_flush     = flush;

		// Default handshake mode
		axi_awready_i = 1'b1;
		axi_wready_i  = 1'b1;

		if (split_mode == SPLIT_AW_FIRST) begin
			axi_awready_i = 1'b1;
			axi_wready_i  = 1'b0;
		end
		else if (split_mode == SPLIT_W_FIRST) begin
			axi_awready_i = 1'b0;
			axi_wready_i  = 1'b1;
		end

		// Issue request
		mem_addr_i       = addr;
		mem_data_wr_i    = wdata;
		mem_req_tag_i    = tag;
		mem_rd_i         = 1'b0;
		mem_wr_i         = wstrb;
		mem_cacheable_i  = cacheable;
		mem_invalidate_i = inval;
		mem_writeback_i  = wb;
		mem_flush_i      = flush;

		// Push request into FIFO
		tick(1);
		#1;
		check_bit("write_accept", mem_accept_o, 1'b1);
		check_bit("awvalid_seen", axi_awvalid_o, 1'b1);
		check_bit("wvalid_seen",  axi_wvalid_o, 1'b1);
		check32("awaddr_seen", axi_awaddr_o, addr & 32'hFFFF_FFFC);
		check32("wdata_seen",  axi_wdata_o, wdata);
		check32("wstrb_seen",  {28'b0, axi_wstrb_o}, {28'b0, wstrb});

		// Remove request
		mem_wr_i         = 4'b0000;
		mem_invalidate_i = 1'b0;
		mem_writeback_i  = 1'b0;
		mem_flush_i      = 1'b0;

		// Handle split modes
		if (split_mode == SPLIT_AW_FIRST) begin
			tick(1);
			#1;
			check_bit("awvalid_split_aw_first", axi_awvalid_o, 1'b0);
			check_bit("wvalid_split_aw_first",  axi_wvalid_o, 1'b1);
			axi_wready_i = 1'b1;
			tick(1);
		end
		else if (split_mode == SPLIT_W_FIRST) begin
			tick(1);
			#1;
			check_bit("awvalid_split_w_first", axi_awvalid_o, 1'b1);
			check_bit("wvalid_split_w_first",  axi_wvalid_o, 1'b0);
			axi_awready_i = 1'b1;
			tick(1);
		end
		else begin
			tick(1);
		end

		// Return B response
		axi_bvalid_i = 1'b1;
		axi_bresp_i  = err ? 2'b10 : 2'b00;

		tick(1);
		#1;
		check_bit("write_ack",   mem_ack_o, 1'b1);
		check11 ("write_tag",    mem_resp_tag_o, tag);
		check_bit("write_error", mem_error_o, err);

		cov.sample();

		// Clear response
		axi_bvalid_i = 1'b0;
		axi_bresp_i  = 2'b00;
		axi_awready_i = 1'b1;
		axi_wready_i  = 1'b1;
		tick(1);
	endtask

	// ------------------------------------------------------------
	// Directed tests
	// ------------------------------------------------------------
	task automatic test_read_basic();
		$display("[TEST] read_basic");
		do_read_txn(32'h1234_5678, 11'h012, 32'hA5A5_5A5A, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
	endtask

	task automatic test_read_error();
		$display("[TEST] read_error");
		do_read_txn(32'h1000_0044, 11'h123, 32'hFACE_CAFE, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
	endtask

	task automatic test_write_basic();
		$display("[TEST] write_basic");
		do_write_txn(32'h2000_0004, 32'hDEAD_BEEF, 4'b1111, 11'h055, 1'b0, SPLIT_NONE, 1'b0, 1'b0, 1'b0, 1'b0);
	endtask

	task automatic test_write_error();
		$display("[TEST] write_error");
		do_write_txn(32'h2000_0010, 32'hCAFE_BABE, 4'b0011, 11'h066, 1'b1, SPLIT_NONE, 1'b1, 1'b1, 1'b1, 1'b1);
	endtask

	task automatic test_write_split_handshake_aw_first();
		$display("[TEST] write_split_handshake_aw_first");
		do_write_txn(32'h3000_0000, 32'h1111_2222, 4'b1111, 11'h033, 1'b1, SPLIT_AW_FIRST, 1'b0, 1'b0, 1'b0, 1'b0);
	endtask

	task automatic test_write_split_handshake_w_first();
		$display("[TEST] write_split_handshake_w_first");
		do_write_txn(32'h3000_0010, 32'h3333_4444, 4'b1100, 11'h044, 1'b0, SPLIT_W_FIRST, 1'b1, 1'b0, 1'b1, 1'b0);
	endtask

	task automatic test_all_write_strobes();
		$display("[TEST] all_write_strobes");

		do_write_txn(32'h4000_0000, 32'hAAAA_0001, 4'b0001, 11'h101, 1'b0, SPLIT_NONE);
		do_write_txn(32'h4000_0004, 32'hAAAA_0002, 4'b0010, 11'h102, 1'b0, SPLIT_NONE);
		do_write_txn(32'h4000_0008, 32'hAAAA_0003, 4'b0100, 11'h103, 1'b0, SPLIT_NONE);
		do_write_txn(32'h4000_000C, 32'hAAAA_0004, 4'b1000, 11'h104, 1'b0, SPLIT_NONE);
		do_write_txn(32'h4000_0010, 32'hAAAA_0005, 4'b0011, 11'h105, 1'b0, SPLIT_NONE);
		do_write_txn(32'h4000_0014, 32'hAAAA_0006, 4'b1100, 11'h106, 1'b0, SPLIT_NONE);
		do_write_txn(32'h4000_0018, 32'hAAAA_0007, 4'b1111, 11'h107, 1'b0, SPLIT_NONE);
	endtask

	// ------------------------------------------------------------
	// Random test
	// ------------------------------------------------------------
	task automatic test_random();
		logic        do_read;
		logic [10:0] tag;
		logic [31:0] addr;
		logic [31:0] data;
		logic [3:0]  strb;
		logic        err;
		split_e      split_mode;
		logic        cacheable;
		logic        inval;
		logic        wb;
		logic        flush;

		$display("[TEST] random");

		random_iters = 120;

		repeat (random_iters) begin
			do_read   = $urandom_range(0,1);
			tag       = $urandom_range(0, 2047);
			addr      = $urandom() & 32'hFFFF_FFFC;
			data      = $urandom();
			cacheable = $urandom_range(0,1);
			inval     = $urandom_range(0,1);
			wb        = $urandom_range(0,1);
			flush     = $urandom_range(0,1);
			err       = ($urandom_range(0,4) == 0);

			case ($urandom_range(0,6))
				0: strb = 4'b0001;
				1: strb = 4'b0010;
				2: strb = 4'b0100;
				3: strb = 4'b1000;
				4: strb = 4'b0011;
				5: strb = 4'b1100;
				default: strb = 4'b1111;
			endcase

			if (do_read) begin
				do_read_txn(addr, tag, data, err, cacheable, inval, wb, flush);
			end
			else begin
				case ($urandom_range(0,2))
					0: split_mode = SPLIT_NONE;
					1: split_mode = SPLIT_AW_FIRST;
					default: split_mode = SPLIT_W_FIRST;
				endcase

				do_write_txn(addr, data, strb, tag, err, split_mode, cacheable, inval, wb, flush);
			end
		end
	endtask

	// ------------------------------------------------------------
	// Main
	// ------------------------------------------------------------
	initial begin
		pass_count = 0;
		fail_count = 0;

		reset_dut();
		test_read_basic();

		reset_dut();
		test_read_error();

		reset_dut();
		test_write_basic();

		reset_dut();
		test_write_error();

		reset_dut();
		test_write_split_handshake_aw_first();

		reset_dut();
		test_write_split_handshake_w_first();

		reset_dut();
		test_all_write_strobes();

		reset_dut();
		test_random();

		$display("======================================");
		$display("DPORT_AXI TB SUMMARY");
		$display("pass_count = %0d", pass_count);
		$display("fail_count = %0d", fail_count);
		$display("coverage   = %0.2f %%", cov.get_inst_coverage());
		$display("======================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule