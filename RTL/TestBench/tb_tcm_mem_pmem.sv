`timescale 1ns/1ps

module tb_tcm_mem_pmem;

	localparam int MEM_BYTES = 64*1024;

	logic        clk;
	logic        rst;

	// AXI inputs
	logic        axi_awvalid_i;
	logic [31:0] axi_awaddr_i;
	logic [3:0]  axi_awid_i;
	logic [7:0]  axi_awlen_i;
	logic [1:0]  axi_awburst_i;
	logic        axi_wvalid_i;
	logic [31:0] axi_wdata_i;
	logic [3:0]  axi_wstrb_i;
	logic        axi_wlast_i;
	logic        axi_bready_i;
	logic        axi_arvalid_i;
	logic [31:0] axi_araddr_i;
	logic [3:0]  axi_arid_i;
	logic [7:0]  axi_arlen_i;
	logic [1:0]  axi_arburst_i;
	logic        axi_rready_i;

	logic        ram_accept_i;
	logic        ram_ack_i;
	logic        ram_error_i;
	logic [31:0] ram_read_data_i;

	// AXI outputs
	logic        axi_awready_o;
	logic        axi_wready_o;
	logic        axi_bvalid_o;
	logic [1:0]  axi_bresp_o;
	logic [3:0]  axi_bid_o;
	logic        axi_arready_o;
	logic        axi_rvalid_o;
	logic [31:0] axi_rdata_o;
	logic [1:0]  axi_rresp_o;
	logic [3:0]  axi_rid_o;
	logic        axi_rlast_o;
	logic [3:0]  ram_wr_o;
	logic        ram_rd_o;
	logic [7:0]  ram_len_o;
	logic [31:0] ram_addr_o;
	logic [31:0] ram_write_data_o;

	int pass_count;
	int fail_count;

	byte model_mem [0:MEM_BYTES-1];

	logic        pending_ack;
	logic [31:0] pending_rdata;

	tcm_mem_pmem dut (
		.clk_i            (clk),
		.rst_i            (rst),
		.axi_awvalid_i    (axi_awvalid_i),
		.axi_awaddr_i     (axi_awaddr_i),
		.axi_awid_i       (axi_awid_i),
		.axi_awlen_i      (axi_awlen_i),
		.axi_awburst_i    (axi_awburst_i),
		.axi_wvalid_i     (axi_wvalid_i),
		.axi_wdata_i      (axi_wdata_i),
		.axi_wstrb_i      (axi_wstrb_i),
		.axi_wlast_i      (axi_wlast_i),
		.axi_bready_i     (axi_bready_i),
		.axi_arvalid_i    (axi_arvalid_i),
		.axi_araddr_i     (axi_araddr_i),
		.axi_arid_i       (axi_arid_i),
		.axi_arlen_i      (axi_arlen_i),
		.axi_arburst_i    (axi_arburst_i),
		.axi_rready_i     (axi_rready_i),
		.ram_accept_i     (ram_accept_i),
		.ram_ack_i        (ram_ack_i),
		.ram_error_i      (ram_error_i),
		.ram_read_data_i  (ram_read_data_i),
		.axi_awready_o    (axi_awready_o),
		.axi_wready_o     (axi_wready_o),
		.axi_bvalid_o     (axi_bvalid_o),
		.axi_bresp_o      (axi_bresp_o),
		.axi_bid_o        (axi_bid_o),
		.axi_arready_o    (axi_arready_o),
		.axi_rvalid_o     (axi_rvalid_o),
		.axi_rdata_o      (axi_rdata_o),
		.axi_rresp_o      (axi_rresp_o),
		.axi_rid_o        (axi_rid_o),
		.axi_rlast_o      (axi_rlast_o),
		.ram_wr_o         (ram_wr_o),
		.ram_rd_o         (ram_rd_o),
		.ram_len_o        (ram_len_o),
		.ram_addr_o       (ram_addr_o),
		.ram_write_data_o (ram_write_data_o)
	);

	always #5 clk = ~clk;

	function automatic [31:0] model_read32(input int addr);
		begin
			model_read32 = {model_mem[addr+3], model_mem[addr+2], model_mem[addr+1], model_mem[addr+0]};
		end
	endfunction

	task automatic model_write32(
		input int addr,
		input [31:0] data,
		input [3:0]  be
	);
		begin
			if (be[0]) model_mem[addr+0] = data[7:0];
			if (be[1]) model_mem[addr+1] = data[15:8];
			if (be[2]) model_mem[addr+2] = data[23:16];
			if (be[3]) model_mem[addr+3] = data[31:24];
		end
	endtask

	task automatic check(input bit cond, input string msg);
		begin
			if (!cond) begin
				$display("[FAIL] %s t=%0t", msg, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic idle_bus();
		begin
			axi_awvalid_i = 0;
			axi_awaddr_i  = 0;
			axi_awid_i    = 0;
			axi_awlen_i   = 0;
			axi_awburst_i = 2'b01;

			axi_wvalid_i  = 0;
			axi_wdata_i   = 0;
			axi_wstrb_i   = 0;
			axi_wlast_i   = 0;

			axi_arvalid_i = 0;
			axi_araddr_i  = 0;
			axi_arid_i    = 0;
			axi_arlen_i   = 0;
			axi_arburst_i = 2'b01;
		end
	endtask

	// simple RAM backend
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			ram_ack_i       <= 1'b0;
			ram_read_data_i <= 32'h0;
			pending_ack     <= 1'b0;
			pending_rdata   <= 32'h0;
		end
		else begin
			ram_ack_i       <= pending_ack;
			ram_read_data_i <= pending_rdata;
			pending_ack     <= 1'b0;
			pending_rdata   <= 32'h0;

			if (ram_accept_i && (ram_rd_o || (ram_wr_o != 4'b0))) begin
				pending_ack <= 1'b1;

				if (ram_rd_o)
					pending_rdata <= model_read32(ram_addr_o);

				if (ram_wr_o != 4'b0)
					model_write32(ram_addr_o, ram_write_data_o, ram_wr_o);
			end
		end
	end

	// always accept during this TB
	always @(negedge clk) begin
		ram_accept_i <= 1'b1;
		axi_bready_i <= 1'b1;
		axi_rready_i <= 1'b1;
	end

	covergroup cg_pmem_t @(posedge clk);
		option.per_instance = 1;

		cp_aw : coverpoint (axi_awvalid_i && axi_awready_o);
		cp_w  : coverpoint (axi_wvalid_i  && axi_wready_o);
		cp_b  : coverpoint (axi_bvalid_o  && axi_bready_i);
		cp_ar : coverpoint (axi_arvalid_i && axi_arready_o);
		cp_r  : coverpoint (axi_rvalid_o  && axi_rready_i);

		cp_req : coverpoint ({ram_rd_o, (ram_wr_o != 4'b0)}) {
			bins none = {2'b00};
			bins rd   = {2'b10};
			bins wr   = {2'b01};
		}

		cp_strb : coverpoint axi_wstrb_i {
			bins byte0 = {4'b0001};
			bins byte1 = {4'b0010};
			bins byte2 = {4'b0100};
			bins byte3 = {4'b1000};
			bins half0 = {4'b0011};
			bins half1 = {4'b1100};
			bins word  = {4'b1111};
			bins misc  = default;
		}
	endgroup

	cg_pmem_t cg_pmem = new();

	task automatic axi_write_single(
		input [31:0] addr,
		input [3:0]  id,
		input [31:0] data,
		input [3:0]  strb
	);
		int timeout;
		begin
			@(negedge clk);
			axi_awvalid_i = 1'b1;
			axi_awaddr_i  = addr;
			axi_awid_i    = id;
			axi_awlen_i   = 0;
			axi_awburst_i = 2'b01;

			axi_wvalid_i  = 1'b1;
			axi_wdata_i   = data;
			axi_wstrb_i   = strb;
			axi_wlast_i   = 1'b1;

			timeout = 200;
			while (!(axi_awvalid_i && axi_awready_o) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "Timeout waiting for AW handshake");

			timeout = 200;
			while (!(axi_wvalid_i && axi_wready_o) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "Timeout waiting for W handshake");

			@(negedge clk);
			axi_awvalid_i = 1'b0;
			axi_wvalid_i  = 1'b0;
			axi_wlast_i   = 1'b0;

			timeout = 200;
			while (!(axi_bvalid_o && axi_bready_i) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "Timeout waiting for B response");

			if (timeout > 0) begin
				check(axi_bid_o   == id, "BID mismatch");
				check(axi_bresp_o == 2'b00, "BRESP mismatch");
			end
		end
	endtask

	task automatic axi_read_single(
		input [31:0] addr,
		input [3:0]  id
	);
		int timeout;
		reg [31:0] exp;
		begin
			exp = model_read32(addr);

			@(negedge clk);
			axi_arvalid_i = 1'b1;
			axi_araddr_i  = addr;
			axi_arid_i    = id;
			axi_arlen_i   = 0;
			axi_arburst_i = 2'b01;

			timeout = 200;
			while (!(axi_arvalid_i && axi_arready_o) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "Timeout waiting for AR handshake");

			@(negedge clk);
			axi_arvalid_i = 1'b0;

			timeout = 200;
			while (!(axi_rvalid_o && axi_rready_i) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "Timeout waiting for R response");

			if (timeout > 0) begin
				check(axi_rdata_o == exp, "RDATA mismatch");
				check(axi_rid_o   == id,  "RID mismatch");
				check(axi_rresp_o == 2'b00, "RRESP mismatch");
				check(axi_rlast_o == 1'b1, "RLAST mismatch");
			end
		end
	endtask

	integer i;

	initial begin
		$fsdbDumpfile("tb_tcm_mem_pmem.fsdb");
		$fsdbDumpvars(0, tb_tcm_mem_pmem);

		clk         = 0;
		rst         = 1;
		pass_count  = 0;
		fail_count  = 0;
		ram_error_i = 1'b0;
		idle_bus();

		for (i = 0; i < MEM_BYTES; i++)
			model_mem[i] = 8'h00;

		repeat (4) @(posedge clk);
		rst = 0;

		$display("\n[TEST] single_write_single_read");
		axi_write_single(32'h0000_0100, 4'h3, 32'hA1B2_C3D4, 4'hF);
		axi_read_single (32'h0000_0100, 4'h3);

		$display("[TEST] partial_write");
		axi_write_single(32'h0000_0104, 4'h5, 32'h1122_3344, 4'b0011);
		axi_read_single (32'h0000_0104, 4'h5);

		$display("[TEST] random");
		for (i = 0; i < 100; i++) begin
			logic [31:0] addr;
			logic [31:0] data;
			logic [3:0]  id;
			logic [3:0]  strb;

			addr = $urandom_range(0, MEM_BYTES-4);
			addr = {addr[31:2], 2'b00};
			data = {$urandom, $urandom};
			id   = $urandom_range(0, 15);

			case ($urandom_range(0,6))
				0: strb = 4'b0001;
				1: strb = 4'b0010;
				2: strb = 4'b0100;
				3: strb = 4'b1000;
				4: strb = 4'b0011;
				5: strb = 4'b1100;
				default: strb = 4'b1111;
			endcase

			if ($urandom_range(0,1))
				axi_write_single(addr, id, data, strb);
			else
				axi_read_single(addr, id);
		end

		$display("==================================================");
		$display("TCM_MEM_PMEM TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cg_pmem.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule