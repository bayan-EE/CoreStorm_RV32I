`timescale 1ns/1ps

module tb_dcache_axi_axi;

	logic         clk_i;
	logic         rst_i;
	logic         inport_valid_i;
	logic         inport_write_i;
	logic [31:0]  inport_addr_i;
	logic [3:0]   inport_id_i;
	logic [7:0]   inport_len_i;
	logic [1:0]   inport_burst_i;
	logic [31:0]  inport_wdata_i;
	logic [3:0]   inport_wstrb_i;
	logic         inport_bready_i;
	logic         inport_rready_i;
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

	logic         inport_accept_o;
	logic         inport_bvalid_o;
	logic [1:0]   inport_bresp_o;
	logic [3:0]   inport_bid_o;
	logic         inport_rvalid_o;
	logic [31:0]  inport_rdata_o;
	logic [1:0]   inport_rresp_o;
	logic [3:0]   inport_rid_o;
	logic         inport_rlast_o;
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

	dcache_axi_axi dut (
		.clk_i(clk_i),
		.rst_i(rst_i),
		.inport_valid_i(inport_valid_i),
		.inport_write_i(inport_write_i),
		.inport_addr_i(inport_addr_i),
		.inport_id_i(inport_id_i),
		.inport_len_i(inport_len_i),
		.inport_burst_i(inport_burst_i),
		.inport_wdata_i(inport_wdata_i),
		.inport_wstrb_i(inport_wstrb_i),
		.inport_bready_i(inport_bready_i),
		.inport_rready_i(inport_rready_i),
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

		.inport_accept_o(inport_accept_o),
		.inport_bvalid_o(inport_bvalid_o),
		.inport_bresp_o(inport_bresp_o),
		.inport_bid_o(inport_bid_o),
		.inport_rvalid_o(inport_rvalid_o),
		.inport_rdata_o(inport_rdata_o),
		.inport_rresp_o(inport_rresp_o),
		.inport_rid_o(inport_rid_o),
		.inport_rlast_o(inport_rlast_o),
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
		.outport_rready_o(outport_rready_o)
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
	covergroup cg_axi @(posedge clk_i);
		cp_write  : coverpoint inport_write_i;
		cp_len    : coverpoint inport_len_i {
			bins single = {0};
			bins short  = {[1:3]};
			bins long   = {[4:8]};
		}
		cp_aw_hs  : coverpoint (outport_awvalid_o && outport_awready_i);
		cp_w_hs   : coverpoint (outport_wvalid_o  && outport_wready_i);
		cp_ar_hs  : coverpoint (outport_arvalid_o && outport_arready_i);
		cp_bvalid : coverpoint inport_bvalid_o;
		cp_rvalid : coverpoint inport_rvalid_o;
		cp_cross  : cross cp_write, cp_len;
	endgroup

	cg_axi cov_axi = new();

	task automatic tick();
		@(posedge clk_i);
		#1;
	endtask

	task automatic reset_dut();
		rst_i            = 1'b1;
		inport_valid_i   = 1'b0;
		inport_write_i   = 1'b0;
		inport_addr_i    = '0;
		inport_id_i      = '0;
		inport_len_i     = '0;
		inport_burst_i   = 2'b01;
		inport_wdata_i   = '0;
		inport_wstrb_i   = 4'hF;
		inport_bready_i  = 1'b1;
		inport_rready_i  = 1'b1;
		outport_awready_i= 1'b0;
		outport_wready_i = 1'b0;
		outport_bvalid_i = 1'b0;
		outport_bresp_i  = 2'b00;
		outport_bid_i    = '0;
		outport_arready_i= 1'b0;
		outport_rvalid_i = 1'b0;
		outport_rdata_i  = '0;
		outport_rresp_i  = 2'b00;
		outport_rid_i    = '0;
		outport_rlast_i  = 1'b0;
		repeat (3) tick();
		rst_i = 1'b0;
		tick();
	endtask

	task automatic check;
		input logic cond;
		input [8*128-1:0] msg;
		begin
			if (!cond) begin
				$display("[FAIL] %s", msg);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	// ------------------------------------------------------------
	// Directed tests
	// ------------------------------------------------------------
	task automatic test_single_read();
		$display("[TEST] axi_single_read");

		inport_valid_i    = 1'b1;
		inport_write_i    = 1'b0;
		inport_addr_i     = 32'h1000_0040;
		inport_id_i       = 4'h3;
		inport_len_i      = 8'd0;
		inport_burst_i    = 2'b01;
		outport_arready_i = 1'b1;

		tick();

		check(outport_arvalid_o, "ARVALID should assert for read");
		check(inport_accept_o,   "inport_accept_o should assert on read handshake");
		check(outport_araddr_o == 32'h1000_0040, "ARADDR mismatch");
		check(outport_arid_o   == 4'h3,          "ARID mismatch");

		inport_valid_i    = 1'b0;
		outport_arready_i = 1'b0;

		outport_rvalid_i = 1'b1;
		outport_rdata_i  = 32'hA5A5_5A5A;
		outport_rresp_i  = 2'b00;
		outport_rid_i    = 4'h3;
		outport_rlast_i  = 1'b1;
		tick();

		check(inport_rvalid_o,               "RVALID should pass through");
		check(inport_rdata_o == 32'hA5A5_5A5A, "RDATA mismatch");
		check(inport_rlast_o,                "RLAST mismatch");

		outport_rvalid_i = 1'b0;
		outport_rlast_i  = 1'b0;
	endtask

	task automatic test_single_write();
		$display("[TEST] axi_single_write");

		inport_valid_i    = 1'b1;
		inport_write_i    = 1'b1;
		inport_addr_i     = 32'h2000_0000;
		inport_id_i       = 4'h7;
		inport_len_i      = 8'd0;
		inport_burst_i    = 2'b01;
		inport_wdata_i    = 32'hDEAD_BEEF;
		inport_wstrb_i    = 4'hF;
		outport_awready_i = 1'b1;
		outport_wready_i  = 1'b1;

		tick();

		check(outport_awvalid_o, "AWVALID should assert");
		check(outport_wvalid_o,  "WVALID should assert");
		check(outport_wlast_o,   "WLAST should assert for single beat");
		check(inport_accept_o,   "accept should assert for single write");

		inport_valid_i    = 1'b0;
		outport_awready_i = 1'b0;
		outport_wready_i  = 1'b0;

		outport_bvalid_i  = 1'b1;
		outport_bresp_i   = 2'b00;
		outport_bid_i     = 4'h7;
		tick();

		check(inport_bvalid_o, "BVALID should pass through");
		check(inport_bid_o == 4'h7, "BID mismatch");

		outport_bvalid_i = 1'b0;
	endtask

	task automatic test_write_aw_before_w();
		$display("[TEST] axi_write_aw_before_w");

		inport_valid_i    = 1'b1;
		inport_write_i    = 1'b1;
		inport_addr_i     = 32'h3000_0010;
		inport_id_i       = 4'h2;
		inport_len_i      = 8'd0;
		inport_wdata_i    = 32'h1122_3344;
		inport_wstrb_i    = 4'hF;

		outport_awready_i = 1'b1;
		outport_wready_i  = 1'b0;

		#1;
		check(outport_awvalid_o, "AWVALID should be high");
		check(outport_wvalid_o,  "WVALID should be high");

		tick();

		outport_awready_i = 1'b0;
		outport_wready_i  = 1'b1;

		#1;
		check(outport_wvalid_o || dut.buf_valid_q, "W should remain pending after AW-only accept");

		tick();

		inport_valid_i    = 1'b0;
		outport_wready_i  = 1'b0;
	endtask

	task automatic test_random(input integer ntests);
		integer t;
		integer k;
		reg is_write;
		reg [7:0]  len;
		reg [31:0] addr;
		reg [31:0] data;
		reg [3:0]  id;
		reg accepted;
		integer beat;

		begin
			$display("[TEST] axi_random");

			for (t = 0; t < ntests; t = t + 1) begin
				is_write = $urandom_range(0,1);
				len      = $urandom_range(0,4);
				addr     = $urandom & 32'hFFFF_FFFC;
				data     = $urandom;
				id       = $urandom_range(0,15);

				inport_valid_i = 1'b1;
				inport_write_i = is_write;
				inport_addr_i  = addr;
				inport_id_i    = id;
				inport_len_i   = len;
				inport_burst_i = 2'b01;
				inport_wdata_i = data;
				inport_wstrb_i = 4'hF;

				accepted = 0;
				for (k = 0; k < 20; k = k + 1) begin
					outport_awready_i = $urandom_range(0,1);
					outport_wready_i  = $urandom_range(0,1);
					outport_arready_i = $urandom_range(0,1);

					#1;
					if (inport_accept_o) begin
						accepted = 1;
						tick();
						k = 20;
					end
					else begin
						tick();
					end
				end

				check(accepted, $sformatf("random request %0d not accepted in time", t));

				inport_valid_i    = 1'b0;
				outport_awready_i = 1'b0;
				outport_wready_i  = 1'b0;
				outport_arready_i = 1'b0;

				if (is_write) begin
					outport_bvalid_i = 1'b1;
					outport_bresp_i  = ($urandom_range(0,1) ? 2'b00 : 2'b10);
					outport_bid_i    = id;
					tick();
					check(inport_bvalid_o, $sformatf("random write response %0d missing", t));
					outport_bvalid_i = 1'b0;
				end
				else begin
					for (beat = 0; beat <= len; beat = beat + 1) begin
						outport_rvalid_i = 1'b1;
						outport_rdata_i  = $urandom;
						outport_rresp_i  = 2'b00;
						outport_rid_i    = id;
						outport_rlast_i  = (beat == len);
						tick();
						check(inport_rvalid_o, $sformatf("random read beat %0d/%0d missing", beat, len));
					end
					outport_rvalid_i = 1'b0;
					outport_rlast_i  = 1'b0;
				end
			end
		end
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;

		reset_dut();

		test_single_read();
		test_single_write();
		test_write_aw_before_w();
		test_random(250);

		$display("==================================================");
		$display("DCACHE_AXI_AXI TB SUMMARY");
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