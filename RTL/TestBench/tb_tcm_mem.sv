`timescale 1ns/1ps

module tb_tcm_mem;

	localparam int MEM_BYTES = 64*1024;
	localparam int MEM_WORDS = MEM_BYTES / 8;

	logic        clk;
	logic        rst;

	// CPU instruction side
	logic        mem_i_rd_i;
	logic        mem_i_flush_i;
	logic        mem_i_invalidate_i;
	logic [31:0] mem_i_pc_i;

	logic        mem_i_accept_o;
	logic        mem_i_valid_o;
	logic        mem_i_error_o;
	logic [63:0] mem_i_inst_o;

	// CPU data side
	logic [31:0] mem_d_addr_i;
	logic [31:0] mem_d_data_wr_i;
	logic        mem_d_rd_i;
	logic [3:0]  mem_d_wr_i;
	logic        mem_d_cacheable_i;
	logic [10:0] mem_d_req_tag_i;
	logic        mem_d_invalidate_i;
	logic        mem_d_writeback_i;
	logic        mem_d_flush_i;

	logic [31:0] mem_d_data_rd_o;
	logic        mem_d_accept_o;
	logic        mem_d_ack_o;
	logic        mem_d_error_o;
	logic [10:0] mem_d_resp_tag_o;

	// External AXI side
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

	int pass_count;
	int fail_count;

	byte model_mem [0:MEM_BYTES-1];

	tcm_mem dut (
		.clk_i              (clk),
		.rst_i              (rst),
		.mem_i_rd_i         (mem_i_rd_i),
		.mem_i_flush_i      (mem_i_flush_i),
		.mem_i_invalidate_i (mem_i_invalidate_i),
		.mem_i_pc_i         (mem_i_pc_i),
		.mem_d_addr_i       (mem_d_addr_i),
		.mem_d_data_wr_i    (mem_d_data_wr_i),
		.mem_d_rd_i         (mem_d_rd_i),
		.mem_d_wr_i         (mem_d_wr_i),
		.mem_d_cacheable_i  (mem_d_cacheable_i),
		.mem_d_req_tag_i    (mem_d_req_tag_i),
		.mem_d_invalidate_i (mem_d_invalidate_i),
		.mem_d_writeback_i  (mem_d_writeback_i),
		.mem_d_flush_i      (mem_d_flush_i),
		.axi_awvalid_i      (axi_awvalid_i),
		.axi_awaddr_i       (axi_awaddr_i),
		.axi_awid_i         (axi_awid_i),
		.axi_awlen_i        (axi_awlen_i),
		.axi_awburst_i      (axi_awburst_i),
		.axi_wvalid_i       (axi_wvalid_i),
		.axi_wdata_i        (axi_wdata_i),
		.axi_wstrb_i        (axi_wstrb_i),
		.axi_wlast_i        (axi_wlast_i),
		.axi_bready_i       (axi_bready_i),
		.axi_arvalid_i      (axi_arvalid_i),
		.axi_araddr_i       (axi_araddr_i),
		.axi_arid_i         (axi_arid_i),
		.axi_arlen_i        (axi_arlen_i),
		.axi_arburst_i      (axi_arburst_i),
		.axi_rready_i       (axi_rready_i),
		.mem_i_accept_o     (mem_i_accept_o),
		.mem_i_valid_o      (mem_i_valid_o),
		.mem_i_error_o      (mem_i_error_o),
		.mem_i_inst_o       (mem_i_inst_o),
		.mem_d_data_rd_o    (mem_d_data_rd_o),
		.mem_d_accept_o     (mem_d_accept_o),
		.mem_d_ack_o        (mem_d_ack_o),
		.mem_d_error_o      (mem_d_error_o),
		.mem_d_resp_tag_o   (mem_d_resp_tag_o),
		.axi_awready_o      (axi_awready_o),
		.axi_wready_o       (axi_wready_o),
		.axi_bvalid_o       (axi_bvalid_o),
		.axi_bresp_o        (axi_bresp_o),
		.axi_bid_o          (axi_bid_o),
		.axi_arready_o      (axi_arready_o),
		.axi_rvalid_o       (axi_rvalid_o),
		.axi_rdata_o        (axi_rdata_o),
		.axi_rresp_o        (axi_rresp_o),
		.axi_rid_o          (axi_rid_o),
		.axi_rlast_o        (axi_rlast_o)
	);

	always #5 clk = ~clk;

	function automatic [63:0] model_read64(input int word_addr);
		int base;
		begin
			base = word_addr * 8;
			model_read64 = {
				model_mem[base+7], model_mem[base+6], model_mem[base+5], model_mem[base+4],
				model_mem[base+3], model_mem[base+2], model_mem[base+1], model_mem[base+0]
			};
		end
	endfunction

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

	task automatic model_write64(
		input int word_addr,
		input [63:0] data
	);
		int base;
		begin
			base = word_addr * 8;
			model_mem[base+0] = data[7:0];
			model_mem[base+1] = data[15:8];
			model_mem[base+2] = data[23:16];
			model_mem[base+3] = data[31:24];
			model_mem[base+4] = data[39:32];
			model_mem[base+5] = data[47:40];
			model_mem[base+6] = data[55:48];
			model_mem[base+7] = data[63:56];
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

	task automatic idle_inputs();
		begin
			mem_i_rd_i         = 0;
			mem_i_flush_i      = 0;
			mem_i_invalidate_i = 0;
			mem_i_pc_i         = 0;

			mem_d_addr_i       = 0;
			mem_d_data_wr_i    = 0;
			mem_d_rd_i         = 0;
			mem_d_wr_i         = 0;
			mem_d_cacheable_i  = 0;
			mem_d_req_tag_i    = 0;
			mem_d_invalidate_i = 0;
			mem_d_writeback_i  = 0;
			mem_d_flush_i      = 0;

			axi_awvalid_i      = 0;
			axi_awaddr_i       = 0;
			axi_awid_i         = 0;
			axi_awlen_i        = 0;
			axi_awburst_i      = 2'b01;
			axi_wvalid_i       = 0;
			axi_wdata_i        = 0;
			axi_wstrb_i        = 0;
			axi_wlast_i        = 0;
			axi_bready_i       = 1;
			axi_arvalid_i      = 0;
			axi_araddr_i       = 0;
			axi_arid_i         = 0;
			axi_arlen_i        = 0;
			axi_arburst_i      = 2'b01;
			axi_rready_i       = 1;
		end
	endtask

	task automatic cpu_ifetch(input [31:0] pc);
		reg [63:0] exp_inst;
		begin
			exp_inst = model_read64(pc[15:3]);

			@(negedge clk);
			mem_i_pc_i = pc;
			mem_i_rd_i = 1'b1;

			@(posedge clk);
			#1;
			check(mem_i_accept_o == 1'b1, "mem_i_accept_o should be 1");
			check(mem_i_valid_o  == 1'b1, "mem_i_valid_o should pulse");
			check(mem_i_error_o  == 1'b0, "mem_i_error_o should be 0");
			check(mem_i_inst_o   == exp_inst, "mem_i_inst_o mismatch");

			@(negedge clk);
			mem_i_rd_i = 1'b0;
		end
	endtask

	task automatic cpu_d_read(input [31:0] addr, input [10:0] tag);
		reg [31:0] exp;
		int timeout;
		begin
			exp = model_read32(addr);

			timeout = 200;
			while (!mem_d_accept_o && timeout > 0) begin
				@(posedge clk);
				timeout--;
			end
			check(timeout > 0, "cpu_d_read accept timeout");

			@(negedge clk);
			mem_d_addr_i    = addr;
			mem_d_rd_i      = 1'b1;
			mem_d_wr_i      = 4'b0000;
			mem_d_req_tag_i = tag;

			@(posedge clk);
			#1;
			check(mem_d_ack_o      == 1'b1, "cpu read ack");
			check(mem_d_resp_tag_o == tag,  "cpu read tag");
			check(mem_d_error_o    == 1'b0, "cpu read error");
			check(mem_d_data_rd_o  == exp,  "cpu read data");

			@(negedge clk);
			mem_d_rd_i = 1'b0;
		end
	endtask

	task automatic cpu_d_write(
		input [31:0] addr,
		input [31:0] data,
		input [3:0]  be,
		input [10:0] tag
	);
		reg [31:0] exp_old;
		int timeout;
		begin
			exp_old = model_read32(addr);

			timeout = 200;
			while (!mem_d_accept_o && timeout > 0) begin
				@(posedge clk);
				timeout--;
			end
			check(timeout > 0, "cpu_d_write accept timeout");

			@(negedge clk);
			mem_d_addr_i    = addr;
			mem_d_data_wr_i = data;
			mem_d_wr_i      = be;
			mem_d_rd_i      = 1'b0;
			mem_d_req_tag_i = tag;

			@(posedge clk);
			#1;
			check(mem_d_ack_o      == 1'b1, "cpu write ack");
			check(mem_d_resp_tag_o == tag,  "cpu write tag");
			check(mem_d_error_o    == 1'b0, "cpu write error");
			check(mem_d_data_rd_o  == exp_old, "cpu write read-first old data");

			model_write32(addr, data, be);

			@(negedge clk);
			mem_d_wr_i = 4'b0000;
		end
	endtask

	task automatic cpu_d_maint(
		input bit inval,
		input bit wb,
		input bit flush,
		input [10:0] tag
	);
		int timeout;
		begin
			timeout = 200;
			while (!mem_d_accept_o && timeout > 0) begin
				@(posedge clk);
				timeout--;
			end
			check(timeout > 0, "cpu_d_maint accept timeout");

			@(negedge clk);
			mem_d_req_tag_i    = tag;
			mem_d_invalidate_i = inval;
			mem_d_writeback_i  = wb;
			mem_d_flush_i      = flush;

			@(posedge clk);
			#1;
			check(mem_d_ack_o      == 1'b1, "cpu maint ack");
			check(mem_d_resp_tag_o == tag,  "cpu maint tag");
			check(mem_d_error_o    == 1'b0, "cpu maint error");

			@(negedge clk);
			mem_d_invalidate_i = 1'b0;
			mem_d_writeback_i  = 1'b0;
			mem_d_flush_i      = 1'b0;
		end
	endtask

	task automatic axi_write_single(
		input [31:0] addr,
		input [31:0] data,
		input [3:0]  be,
		input [3:0]  id
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
			axi_wstrb_i   = be;
			axi_wlast_i   = 1'b1;

			timeout = 200;
			while (!((axi_awvalid_i && axi_awready_o) && (axi_wvalid_i && axi_wready_o)) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "axi write handshake timeout");

			model_write32(addr, data, be);

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
			check(timeout > 0, "axi write bresp timeout");

			if (timeout > 0) begin
				check(axi_bid_o   == id,   "axi single write BID");
				check(axi_bresp_o == 2'b00,"axi single write BRESP");
			end
		end
	endtask

	task automatic axi_read_single(
		input [31:0] addr,
		input [3:0]  id
	);
		reg [31:0] exp;
		int timeout;
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
			check(timeout > 0, "axi read ar timeout");

			@(negedge clk);
			axi_arvalid_i = 1'b0;

			timeout = 200;
			while (!(axi_rvalid_o && axi_rready_i) && timeout > 0) begin
				@(posedge clk);
				#1;
				timeout--;
			end
			check(timeout > 0, "axi read r timeout");

			if (timeout > 0) begin
				check(axi_rdata_o == exp,  "axi single read data");
				check(axi_rid_o   == id,   "axi single read RID");
				check(axi_rresp_o == 2'b00,"axi single read RRESP");
				check(axi_rlast_o == 1'b1, "axi single read RLAST");
			end
		end
	endtask
	task automatic cpu_d_combo(
			input bit rd_en,
			input [3:0] wr_en,
			input bit inval,
			input bit wb,
			input bit flush,
			input [31:0] addr,
			input [31:0] data,
			input [10:0] tag
		);
			int timeout;
			begin
				timeout = 200;
				while (!mem_d_accept_o && timeout > 0) begin
					@(posedge clk);
					timeout--;
				end
				check(timeout > 0, "cpu_d_combo accept timeout");

				@(negedge clk);
				mem_d_addr_i       = addr;
				mem_d_data_wr_i    = data;
				mem_d_rd_i         = rd_en;
				mem_d_wr_i         = wr_en;
				mem_d_req_tag_i    = tag;
				mem_d_invalidate_i = inval;
				mem_d_writeback_i  = wb;
				mem_d_flush_i      = flush;

				@(posedge clk);
				#1;
				check(mem_d_ack_o      == 1'b1, "cpu_d_combo ack");
				check(mem_d_resp_tag_o == tag,  "cpu_d_combo tag");
				check(mem_d_error_o    == 1'b0, "cpu_d_combo error");

				@(negedge clk);
				mem_d_rd_i         = 1'b0;
				mem_d_wr_i         = 4'b0000;
				mem_d_invalidate_i = 1'b0;
				mem_d_writeback_i  = 1'b0;
				mem_d_flush_i      = 1'b0;
			end
		endtask

	covergroup cg_tcm_t @(posedge clk);
		option.per_instance = 1;

		cp_ifetch   : coverpoint mem_i_rd_i;
		cp_dread    : coverpoint mem_d_rd_i;
		cp_dwrite   : coverpoint (mem_d_wr_i != 4'b0);
		cp_dinv     : coverpoint mem_d_invalidate_i;
		cp_dwb      : coverpoint mem_d_writeback_i;
		cp_dflush   : coverpoint mem_d_flush_i;

		cp_tag      : coverpoint mem_d_req_tag_i[3:0];

		cp_be : coverpoint mem_d_wr_i {
			bins byte_lane  = {4'b0001,4'b0010,4'b0100,4'b1000};
			bins half_word  = {4'b0011,4'b1100};
			bins full_word  = {4'b1111};
			bins other_mask = default;
		}

		cp_iaddr : coverpoint mem_i_pc_i[15:3] {
			bins low  = {[0:1023]};
			bins mid1 = {[1024:3071]};
			bins mid2 = {[3072:5119]};
			bins high = {[5120:8191]};
		}

		cp_daddr : coverpoint mem_d_addr_i[15:2] {
			bins low  = {[0:2047]};
			bins mid1 = {[2048:8191]};
			bins mid2 = {[8192:12287]};
			bins high = {[12288:16383]};
		}

		x_cpu_ops   : cross cp_dread, cp_dwrite;
		x_maint_ops : cross cp_dinv, cp_dwb, cp_dflush;
	endgroup

	cg_tcm_t cg_tcm = new();

	integer i;

	initial begin
		$fsdbDumpfile("tb_tcm_mem.fsdb");
		$fsdbDumpvars(0, tb_tcm_mem);

		clk        = 0;
		rst        = 1;
		pass_count = 0;
		fail_count = 0;
		idle_inputs();

		for (i = 0; i < MEM_BYTES; i++) begin
			model_mem[i] = 8'h00;
		end

		for (i = 0; i < MEM_WORDS; i++) begin
			dut.u_ram.ram[i] = 64'h0;
		end
		dut.u_ram.ram_read0_q = 64'h0;
		dut.u_ram.ram_read1_q = 64'h0;

		repeat (4) @(posedge clk);
		rst = 0;

		model_write64(13'h004, 64'h0000_0013_0000_0013);
		model_write64(13'h008, 64'hDEAD_BEEF_CAFE_BABE);
		dut.u_ram.ram[13'h004] = 64'h0000_0013_0000_0013;
		dut.u_ram.ram[13'h008] = 64'hDEAD_BEEF_CAFE_BABE;

		$display("\n[TEST] instruction_fetch");
		cpu_ifetch(32'h0000_0020);
		cpu_ifetch(32'h0000_0040);

		$display("[TEST] cpu_data_write_read");
		cpu_d_write(32'h0000_0100, 32'h1122_3344, 4'hF, 11'h12);
		cpu_d_read (32'h0000_0100, 11'h13);

		$display("[TEST] cpu_partial_write");
		cpu_d_write(32'h0000_0104, 32'hAABB_CCDD, 4'b0011, 11'h21);
		cpu_d_read (32'h0000_0104, 11'h22);

		$display("[TEST] cpu_maintenance_ops");
		cpu_d_maint(1'b1, 1'b0, 1'b0, 11'h31);
		cpu_d_maint(1'b0, 1'b1, 1'b0, 11'h32);
		cpu_d_maint(1'b0, 1'b0, 1'b1, 11'h33);
		
		$display("[TEST] cross_cpu_ops_and_maint_combos");

		// missing x_cpu_ops bin: read + write together
		cpu_d_combo(1'b1, 4'b1111, 1'b0, 1'b0, 1'b0,
					32'h0000_0280, 32'hDEAD_BEEF, 11'h34);

		// extra x_maint_ops combinations
		cpu_d_combo(1'b0, 4'b0000, 1'b1, 1'b1, 1'b0,
					32'h0000_0284, 32'h0000_0000, 11'h35);

		cpu_d_combo(1'b0, 4'b0000, 1'b1, 1'b0, 1'b1,
					32'h0000_0288, 32'h0000_0000, 11'h36);

		cpu_d_combo(1'b0, 4'b0000, 1'b0, 1'b1, 1'b1,
					32'h0000_028C, 32'h0000_0000, 11'h37);

		cpu_d_combo(1'b0, 4'b0000, 1'b1, 1'b1, 1'b1,
					32'h0000_0290, 32'h0000_0000, 11'h38);

		$display("[TEST] cpu_same_address_reuse");
		cpu_d_write(32'h0000_0200, 32'h1234_5678, 4'hF, 11'h41);
		cpu_d_read (32'h0000_0200, 11'h42);
		cpu_d_write(32'h0000_0200, 32'hCAFE_BABE, 4'b0011, 11'h43);
		cpu_d_read (32'h0000_0200, 11'h44);


		$display("[TEST] instruction_address_regions");
		begin
			logic [63:0] instr64;
			instr64 = 64'h1111_1111_2222_2222;
			model_write64(13'd0, instr64);
			dut.u_ram.ram[13'd0] = instr64;
			cpu_ifetch(32'h0000_0000);

			instr64 = 64'h3333_3333_4444_4444;
			model_write64(13'd1500, instr64);
			dut.u_ram.ram[13'd1500] = instr64;
			cpu_ifetch({13'd1500, 3'b000});

			instr64 = 64'h5555_5555_6666_6666;
			model_write64(13'd4096, instr64);
			dut.u_ram.ram[13'd4096] = instr64;
			cpu_ifetch({13'd4096, 3'b000});

			instr64 = 64'h7777_7777_8888_8888;
			model_write64(13'd8191, instr64);
			dut.u_ram.ram[13'd8191] = instr64;
			cpu_ifetch({13'd8191, 3'b000});
		end

		$display("[TEST] cpu_write_mask_patterns");
		cpu_d_write(32'h0000_0300, 32'hAAAA_BBBB, 4'b0001, 11'h51);
		cpu_d_read (32'h0000_0300, 11'h52);

		cpu_d_write(32'h0000_0304, 32'hCCCC_DDDD, 4'b0010, 11'h53);
		cpu_d_read (32'h0000_0304, 11'h54);

		cpu_d_write(32'h0000_0308, 32'h1111_2222, 4'b0100, 11'h55);
		cpu_d_read (32'h0000_0308, 11'h56);

		cpu_d_write(32'h0000_030C, 32'h3333_4444, 4'b1000, 11'h57);
		cpu_d_read (32'h0000_030C, 11'h58);

		cpu_d_write(32'h0000_0310, 32'h5555_6666, 4'b1100, 11'h59);
		cpu_d_read (32'h0000_0310, 11'h5A);

		$display("[TEST] cpu_data_address_regions");
		cpu_d_write({18'h0, 14'd0,     2'b00}, 32'h0000_0001, 4'hF, 11'h61);
		cpu_d_read ({18'h0, 14'd0,     2'b00}, 11'h62);

		cpu_d_write({18'h0, 14'd3000,  2'b00}, 32'h0000_0002, 4'hF, 11'h63);
		cpu_d_read ({18'h0, 14'd3000,  2'b00}, 11'h64);

		cpu_d_write({18'h0, 14'd10000, 2'b00}, 32'h0000_0003, 4'hF, 11'h65);
		cpu_d_read ({18'h0, 14'd10000, 2'b00}, 11'h66);

		cpu_d_write({18'h0, 14'd16383, 2'b00}, 32'h0000_0004, 4'hF, 11'h67);
		cpu_d_read ({18'h0, 14'd16383, 2'b00}, 11'h68);

		$display("[TEST] maintenance_combinations");
		cpu_d_maint(1'b1, 1'b0, 1'b0, 11'h71);
		cpu_d_maint(1'b0, 1'b1, 1'b0, 11'h72);
		cpu_d_maint(1'b0, 1'b0, 1'b1, 11'h73);
		
		
		$display("[TEST] random");
		for (i = 0; i < 250; i++) begin
			int sel;
			logic [31:0] addr;
			logic [31:0] data;
			logic [3:0]  be;

			sel = $urandom_range(0, 7);
			addr = $urandom_range(0, MEM_BYTES-8);
			addr = {addr[31:2], 2'b00};
			data = {$urandom, $urandom};

			case ($urandom_range(0,10))
				0: be = 4'b0001;
				1: be = 4'b0010;
				2: be = 4'b0100;
				3: be = 4'b1000;
				4: be = 4'b0011;
				5: be = 4'b1100;
				6: be = 4'b1111;
				7: be = 4'b0101;
				8: be = 4'b1010;
				9: be = 4'b0110;
				default: be = 4'b1001;
			endcase

			case (sel)
				0,1: begin
					logic [63:0] instr64;
					instr64 = {$urandom, $urandom};
					model_write64(addr[15:3], instr64);
					dut.u_ram.ram[addr[15:3]] = instr64;
					cpu_ifetch(addr & 32'h0000_FFF8);
				end

				2: cpu_d_read(addr, $urandom_range(0, 2047));
				3: cpu_d_write(addr, data, be, $urandom_range(0, 2047));
				4: cpu_d_maint(1'b1, 1'b0, 1'b0, $urandom_range(0, 2047));
				5: cpu_d_maint(1'b0, 1'b1, 1'b0, $urandom_range(0, 2047));
				6: cpu_d_maint(1'b0, 1'b0, 1'b1, $urandom_range(0, 2047));
				7: begin
					cpu_d_write(addr, data, be, $urandom_range(0, 2047));
					cpu_d_read(addr, $urandom_range(0, 2047));
				end
			endcase
		end
		
		$display("==================================================");
		$display("TCM_MEM TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cg_tcm.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule