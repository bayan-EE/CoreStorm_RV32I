`timescale 1ns/1ps

module tb_dcache_axi;

	logic         clk_i;
	logic         rst_i;
	logic         outport_awready_i;
	logic         outport_wready_i;
	logic         outport_bvalid_i;
	logic [1:0]   outport_bresp_i;
	logic [3:0]   outport_bid_i;
	logic         outport_arready_i;
	logic         outport_rvalid_i;
	logic [31:0]  outport_rdata_i;
	logic [1:0]   outport_rresp_i;
	logic [3:0]   outport_rid_i;
	logic         outport_rlast_i;
	logic [3:0]   inport_wr_i;
	logic         inport_rd_i;
	logic [7:0]   inport_len_i;
	logic [31:0]  inport_addr_i;
	logic [31:0]  inport_write_data_i;

	logic         outport_awvalid_o;
	logic [31:0]  outport_awaddr_o;
	logic [3:0]   outport_awid_o;
	logic [7:0]   outport_awlen_o;
	logic [1:0]   outport_awburst_o;
	logic         outport_wvalid_o;
	logic [31:0]  outport_wdata_o;
	logic [3:0]   outport_wstrb_o;
	logic         outport_wlast_o;
	logic         outport_bready_o;
	logic         outport_arvalid_o;
	logic [31:0]  outport_araddr_o;
	logic [3:0]   outport_arid_o;
	logic [7:0]   outport_arlen_o;
	logic [1:0]   outport_arburst_o;
	logic         outport_rready_o;
	logic         inport_accept_o;
	logic         inport_ack_o;
	logic         inport_error_o;
	logic [31:0]  inport_read_data_o;

	dcache_axi #(
		.AXI_ID(4)
	) dut (
		.clk_i(clk_i),
		.rst_i(rst_i),
		.outport_awready_i(outport_awready_i),
		.outport_wready_i(outport_wready_i),
		.outport_bvalid_i(outport_bvalid_i),
		.outport_bresp_i(outport_bresp_i),
		.outport_bid_i(outport_bid_i),
		.outport_arready_i(outport_arready_i),
		.outport_rvalid_i(outport_rvalid_i),
		.outport_rdata_i(outport_rdata_i),
		.outport_rresp_i(outport_rresp_i),
		.outport_rid_i(outport_rid_i),
		.outport_rlast_i(outport_rlast_i),
		.inport_wr_i(inport_wr_i),
		.inport_rd_i(inport_rd_i),
		.inport_len_i(inport_len_i),
		.inport_addr_i(inport_addr_i),
		.inport_write_data_i(inport_write_data_i),
		.outport_awvalid_o(outport_awvalid_o),
		.outport_awaddr_o(outport_awaddr_o),
		.outport_awid_o(outport_awid_o),
		.outport_awlen_o(outport_awlen_o),
		.outport_awburst_o(outport_awburst_o),
		.outport_wvalid_o(outport_wvalid_o),
		.outport_wdata_o(outport_wdata_o),
		.outport_wstrb_o(outport_wstrb_o),
		.outport_wlast_o(outport_wlast_o),
		.outport_bready_o(outport_bready_o),
		.outport_arvalid_o(outport_arvalid_o),
		.outport_araddr_o(outport_araddr_o),
		.outport_arid_o(outport_arid_o),
		.outport_arlen_o(outport_arlen_o),
		.outport_arburst_o(outport_arburst_o),
		.outport_rready_o(outport_rready_o),
		.inport_accept_o(inport_accept_o),
		.inport_ack_o(inport_ack_o),
		.inport_error_o(inport_error_o),
		.inport_read_data_o(inport_read_data_o)
	);

	// ------------------------------------------------------------
	// Clock
	// ------------------------------------------------------------
	initial clk_i = 1'b0;
	always #5 clk_i = ~clk_i;

	int pass_count;
	int fail_count;

	// ------------------------------------------------------------
	// Coverage
	// ------------------------------------------------------------
	covergroup cg_top @(posedge clk_i);
		cp_rd      : coverpoint inport_rd_i;
		cp_wr      : coverpoint (inport_wr_i != 4'b0);
		cp_len     : coverpoint inport_len_i {
			bins single = {0};
			bins short  = {[1:3]};
			bins long   = {[4:8]};
		}
		cp_accept  : coverpoint inport_accept_o;
		cp_ack     : coverpoint inport_ack_o;
		cp_error   : coverpoint inport_error_o;
		cp_cross   : cross cp_rd, cp_wr, cp_len;
	endgroup

	cg_top cov_top = new();

	task automatic tick();
		@(posedge clk_i);
		#1;
	endtask

	task automatic reset_dut();
		rst_i              = 1'b1;
		outport_awready_i  = 1'b0;
		outport_wready_i   = 1'b0;
		outport_bvalid_i   = 1'b0;
		outport_bresp_i    = 2'b00;
		outport_bid_i      = '0;
		outport_arready_i  = 1'b0;
		outport_rvalid_i   = 1'b0;
		outport_rdata_i    = '0;
		outport_rresp_i    = 2'b00;
		outport_rid_i      = '0;
		outport_rlast_i    = 1'b0;
		inport_wr_i        = 4'b0000;
		inport_rd_i        = 1'b0;
		inport_len_i       = '0;
		inport_addr_i      = '0;
		inport_write_data_i= '0;
		repeat (3) tick();
		rst_i = 1'b0;
		tick();
	endtask

	task automatic check(input bit cond, input string msg);
		if (!cond) begin
			$display("[FAIL] %s", msg);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	// ------------------------------------------------------------
	// Simple AXI response model helpers
	// ------------------------------------------------------------
	task automatic drive_write_response(input logic [3:0] bid, input logic [1:0] bresp);
		begin
			outport_bvalid_i = 1'b1;
			outport_bid_i    = bid;
			outport_bresp_i  = bresp;

			#1;
			check(inport_ack_o,   "write response should produce ack");
			check(inport_error_o == (bresp != 2'b00), "write response error mismatch");

			tick();

			outport_bvalid_i = 1'b0;
		end
	endtask

	task automatic drive_read_response(
			input logic [3:0] rid,
			input integer     beats,
			input logic [1:0] rresp
		);
			integer i;
			begin
				for (i = 0; i < beats; i = i + 1) begin
					outport_rvalid_i = 1'b1;
					outport_rid_i    = rid;
					outport_rresp_i  = rresp;
					outport_rdata_i  = 32'h1000_0000 + i;
					outport_rlast_i  = (i == beats-1);

					#1;
					check(inport_ack_o, "read response should produce ack");
					check(inport_error_o == (rresp != 2'b00), "read response error mismatch");

					tick();
				end

				outport_rvalid_i = 1'b0;
				outport_rlast_i  = 1'b0;
			end
		endtask

		task automatic service_read_request();
			integer k;
			reg issued;
			begin
				issued = 0;

				for (k = 0; k < 40; k = k + 1) begin
					outport_arready_i = 1'b1;

					#1;
					if (outport_arvalid_o && outport_arready_i) begin
						issued = 1;
						tick();
						k = 40;
					end
					else begin
						tick();
					end
				end

				check(issued, "read request did not issue to AXI");

				outport_arready_i = 1'b0;
			end
		endtask
		
		
		task automatic issue_read(input logic [31:0] addr, input logic [7:0] len);
			begin
				inport_rd_i         = 1'b1;
				inport_wr_i         = 4'b0000;
				inport_len_i        = len;
				inport_addr_i       = addr;
				inport_write_data_i = '0;

				#1;
				check(inport_accept_o, $sformatf("read addr=%h not accepted", addr));

				tick();

				inport_rd_i = 1'b0;
				inport_wr_i = 4'b0000;
			end
		endtask


		task automatic service_write_request();
			integer k;
			reg aw_seen;
			reg w_seen;
			begin
				aw_seen = 0;
				w_seen  = 0;

				for (k = 0; k < 60; k = k + 1) begin
					outport_awready_i = 1'b1;
					outport_wready_i  = 1'b1;

					#1;
					if (outport_awvalid_o && outport_awready_i)
						aw_seen = 1;

					if (outport_wvalid_o && outport_wready_i && outport_wlast_o)
						w_seen = 1;

					if (aw_seen && w_seen) begin
						tick();
						k = 60;
					end
					else begin
						tick();
					end
				end

				check(aw_seen, "write request AW channel did not issue");
				check(w_seen,  "write request W channel did not complete");

				outport_awready_i = 1'b0;
				outport_wready_i  = 1'b0;
			end
		endtask
		
		task automatic issue_write(input logic [31:0] addr, input logic [31:0] data, input logic [7:0] len);
			begin
				inport_rd_i         = 1'b0;
				inport_wr_i         = 4'hF;
				inport_len_i        = len;
				inport_addr_i       = addr;
				inport_write_data_i = data;

				#1;
				check(inport_accept_o, $sformatf("write addr=%h not accepted", addr));

				tick();

				inport_wr_i = 4'b0000;
				inport_rd_i = 1'b0;
			end
		endtask

	// ------------------------------------------------------------
	// Directed tests
	// ------------------------------------------------------------
		task automatic test_single_read();
			$display("[TEST] top_single_read");

			issue_read(32'h4000_0000, 8'd0);
			service_read_request();
			drive_read_response(4, 1, 2'b00);

			check(inport_read_data_o == 32'h1000_0000, "single read data mismatch");
		endtask

		task automatic test_single_write();
			$display("[TEST] top_single_write");

			issue_write(32'h4000_0100, 32'hCAFE_BABE, 8'd0);
			service_write_request();
			drive_write_response(4, 2'b00);
		endtask

		task automatic test_error_paths();
			$display("[TEST] top_error_paths");

			issue_write(32'h4000_0200, 32'h1111_2222, 8'd0);
			service_write_request();
			drive_write_response(4, 2'b10);

			issue_read(32'h4000_0300, 8'd0);
			service_read_request();
			drive_read_response(4, 1, 2'b10);
		endtask

		task automatic test_fifo_full_accept();
			$display("[TEST] fifo_full_accept");

			// Fill the 2-entry request FIFO
			issue_read(32'h5000_0000, 8'd0);
			issue_read(32'h5000_0004, 8'd0);

			// Third request should be rejected because FIFO is full
			inport_rd_i         = 1'b1;
			inport_wr_i         = 4'b0000;
			inport_len_i        = 8'd0;
			inport_addr_i       = 32'h5000_0008;
			inport_write_data_i = '0;

			#1;
			check(!inport_accept_o, "accept should drop when FIFO full");

			tick();

			inport_rd_i = 1'b0;
		endtask
		
		task automatic test_cross_cases();
			$display("[TEST] cross_cases");

			// write error
			issue_write(32'h7000_0000, 32'h12345678, 0);
			service_write_request();
			drive_write_response(4, 2'b10);

			// read error
			issue_read(32'h7000_1000, 0);
			service_read_request();
			drive_read_response(4, 1, 2'b10);
		endtask
		
	task automatic test_random(int ntests = 200);
		bit is_write;
		logic [31:0] addr, data;
		logic [7:0]  len;
		logic [1:0]  resp;

		$display("[TEST] top_random");

		for (int t = 0; t < ntests; t++) begin
			is_write = $urandom_range(0,1);
			addr     = $urandom & 32'hFFFF_FFFC;
			data     = $urandom;

			// Top-level dcache_axi TB:
			// - writes are constrained to single-beat
			// - reads may be burst
			if (is_write)
				len = 8'd0;
			else
				len = $urandom_range(0,4);

			resp = ($urandom_range(0,4) == 0) ? 2'b10 : 2'b00;

			if (is_write) begin
				issue_write(addr, data, len);
				service_write_request();
				drive_write_response(4, resp);
			end
			else begin
				issue_read(addr, len);
				service_read_request();
				drive_read_response(4, len + 1, resp);
			end
		end
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;

		reset_dut();

		test_single_read();
		test_single_write();
		test_error_paths();
		test_fifo_full_accept();
		reset_dut();
		test_cross_cases();
		test_random(1000);

		$display("==================================================");
		$display("DCACHE_AXI TB SUMMARY");
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