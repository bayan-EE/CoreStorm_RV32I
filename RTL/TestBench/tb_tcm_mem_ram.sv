`timescale 1ns/1ps

module tb_tcm_mem_ram;

	localparam int DEPTH_WORDS = 8192;
	localparam int MEM_BYTES   = DEPTH_WORDS * 8;

	logic        clk;
	logic        rst;

	logic [12:0] addr0_i;
	logic [63:0] data0_i;
	logic [7:0]  wr0_i;

	logic [12:0] addr1_i;
	logic [63:0] data1_i;
	logic [7:0]  wr1_i;

	logic [63:0] data0_o;
	logic [63:0] data1_o;

	int pass_count;
	int fail_count;

	byte model_mem [0:MEM_BYTES-1];

	tcm_mem_ram dut (
		.clk0_i  (clk),
		.rst0_i  (rst),
		.addr0_i (addr0_i),
		.data0_i (data0_i),
		.wr0_i   (wr0_i),
		.clk1_i  (clk),
		.rst1_i  (rst),
		.addr1_i (addr1_i),
		.data1_i (data1_i),
		.wr1_i   (wr1_i),
		.data0_o (data0_o),
		.data1_o (data1_o)
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

	task automatic model_write64(
		input int word_addr,
		input [63:0] data,
		input [7:0]  be
	);
		int base;
		begin
			base = word_addr * 8;

			if (be[0]) model_mem[base+0] = data[7:0];
			if (be[1]) model_mem[base+1] = data[15:8];
			if (be[2]) model_mem[base+2] = data[23:16];
			if (be[3]) model_mem[base+3] = data[31:24];
			if (be[4]) model_mem[base+4] = data[39:32];
			if (be[5]) model_mem[base+5] = data[47:40];
			if (be[6]) model_mem[base+6] = data[55:48];
			if (be[7]) model_mem[base+7] = data[63:56];
		end
	endtask

	task automatic check_equal64(input [63:0] got, input [63:0] exp, input string msg);
		begin
			if (got !== exp) begin
				$display("[FAIL] %s got=%016h exp=%016h t=%0t", msg, got, exp, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic drive_cycle(
		input [12:0] a0,
		input [63:0] d0,
		input [7:0]  w0,
		input [12:0] a1,
		input [63:0] d1,
		input [7:0]  w1,
		input string name
	);
		reg [63:0] exp0, exp1;
		begin
			@(negedge clk);
			addr0_i = a0;
			data0_i = d0;
			wr0_i   = w0;
			addr1_i = a1;
			data1_i = d1;
			wr1_i   = w1;

			exp0 = model_read64(a0);
			exp1 = model_read64(a1);

			@(posedge clk);
			#1;
			check_equal64(data0_o, exp0, {name, " port0"});
			check_equal64(data1_o, exp1, {name, " port1"});

			// Update golden model after checking (read-first behavior)
			model_write64(a0, d0, w0);
			model_write64(a1, d1, w1);

			cg_ram.sample();
		end
	endtask

	covergroup cg_ram_t;
		option.per_instance = 1;

		cp_wr0   : coverpoint (wr0_i != 8'h00) { bins rd = {0}; bins wr = {1}; }
		cp_wr1   : coverpoint (wr1_i != 8'h00) { bins rd = {0}; bins wr = {1}; }
		cp_same  : coverpoint (addr0_i == addr1_i) { bins no = {0}; bins yes = {1}; }

		cp_be0   : coverpoint wr0_i {
			bins zero_mask   = {8'h00};
			bins full_mask   = {8'hFF};
			bins single_lane[] = {8'h01,8'h02,8'h04,8'h08,8'h10,8'h20,8'h40,8'h80};
			bins alt_55      = {8'h55};
			bins alt_AA      = {8'hAA};
			bins misc_masks[] = {[1:254]};
		}

		cp_be1   : coverpoint wr1_i {
			bins zero_mask   = {8'h00};
			bins full_mask   = {8'hFF};
			bins single_lane[] = {8'h01,8'h02,8'h04,8'h08,8'h10,8'h20,8'h40,8'h80};
			bins alt_55      = {8'h55};
			bins alt_AA      = {8'hAA};
			bins misc_masks[] = {[1:254]};
		}

		cp_addr0 : coverpoint addr0_i {
			bins low  = {[0:1023]};
			bins mid1 = {[1024:3071]};
			bins mid2 = {[3072:5119]};
			bins high = {[5120:8191]};
		}

		cp_addr1 : coverpoint addr1_i {
			bins low  = {[0:1023]};
			bins mid1 = {[1024:3071]};
			bins mid2 = {[3072:5119]};
			bins high = {[5120:8191]};
		}

		x_rw : cross cp_wr0, cp_wr1, cp_same;
	endgroup

	cg_ram_t cg_ram = new();

	integer i;

	initial begin
		$fsdbDumpfile("tb_tcm_mem_ram.fsdb");
		$fsdbDumpvars(0, tb_tcm_mem_ram);

		clk        = 0;
		rst        = 1;
		addr0_i    = '0;
		data0_i    = '0;
		wr0_i      = '0;
		addr1_i    = '0;
		data1_i    = '0;
		wr1_i      = '0;
		pass_count = 0;
		fail_count = 0;

		for (i = 0; i < MEM_BYTES; i++) begin
			model_mem[i] = 8'h00;
		end

		// Initialize DUT memory so simulation does not start with X data
		for (i = 0; i < DEPTH_WORDS; i++) begin
			dut.ram[i] = 64'h0000_0000_0000_0000;
		end
		dut.ram_read0_q = 64'h0;
		dut.ram_read1_q = 64'h0;

		repeat (3) @(posedge clk);
		rst = 0;

		$display("\n[TEST] basic_port0_write_read");
		drive_cycle(13'd4, 64'h1122_3344_5566_7788, 8'hFF, 13'd0, 64'h0, 8'h00, "p0 write/read-first");
		drive_cycle(13'd4, 64'h0, 8'h00, 13'd0, 64'h0, 8'h00, "p0 read back");

		$display("[TEST] basic_port1_write_read");
		drive_cycle(13'd0, 64'h0, 8'h00, 13'd10, 64'hDEAD_BEEF_CAFE_1234, 8'hFF, "p1 write/read-first");
		drive_cycle(13'd0, 64'h0, 8'h00, 13'd10, 64'h0, 8'h00, "p1 read back");

		$display("[TEST] simultaneous_different_addresses");
		drive_cycle(13'd20, 64'hAAAA_BBBB_CCCC_DDDD, 8'hFF,
					13'd21, 64'h1111_2222_3333_4444, 8'hFF,
					"simul write diff addr");
		drive_cycle(13'd20, 64'h0, 8'h00, 13'd21, 64'h0, 8'h00, "simul read diff addr");

		$display("[TEST] partial_write_masks");
		drive_cycle(13'd30, 64'h1234_5678_9ABC_DEF0, 8'b0000_1111,
					13'd31, 64'h0F0E_0D0C_0B0A_0908, 8'b1111_0000,
					"partial writes");
		drive_cycle(13'd30, 64'h0, 8'h00, 13'd31, 64'h0, 8'h00, "partial readback");

		$display("[TEST] same_address_combinations");
		drive_cycle(13'd100, 64'h0, 8'h00,
					13'd100, 64'h0, 8'h00,
					"same_addr_rr");

		drive_cycle(13'd101, 64'h1111_2222_3333_4444, 8'hFF,
					13'd101, 64'h0, 8'h00,
					"same_addr_wr");

		drive_cycle(13'd102, 64'h0, 8'h00,
					13'd102, 64'hAAAA_BBBB_CCCC_DDDD, 8'hFF,
					"same_addr_rw");

		drive_cycle(13'd103, 64'h0123_4567_89AB_CDEF, 8'hFF,
					13'd103, 64'hFEDC_BA98_7654_3210, 8'hFF,
					"same_addr_ww");

		$display("[TEST] byte_enable_extremes");
		drive_cycle(13'd200, 64'h1122_3344_5566_7788, 8'h01,
					13'd201, 64'h0, 8'h00,
					"be_p0_01");

		drive_cycle(13'd202, 64'h1122_3344_5566_7788, 8'h80,
					13'd203, 64'h0, 8'h00,
					"be_p0_80");

		drive_cycle(13'd204, 64'h1122_3344_5566_7788, 8'h55,
					13'd205, 64'h0, 8'h00,
					"be_p0_55");

		drive_cycle(13'd206, 64'h1122_3344_5566_7788, 8'hAA,
					13'd207, 64'h0, 8'h00,
					"be_p0_AA");

		drive_cycle(13'd208, 64'h0, 8'h00,
					13'd209, 64'h99AA_BBCC_DDEE_FF00, 8'h01,
					"be_p1_01");

		drive_cycle(13'd210, 64'h0, 8'h00,
					13'd211, 64'h99AA_BBCC_DDEE_FF00, 8'h80,
					"be_p1_80");

		drive_cycle(13'd212, 64'h0, 8'h00,
					13'd213, 64'h99AA_BBCC_DDEE_FF00, 8'h55,
					"be_p1_55");

		drive_cycle(13'd214, 64'h0, 8'h00,
					13'd215, 64'h99AA_BBCC_DDEE_FF00, 8'hAA,
					"be_p1_AA");

		$display("[TEST] address_region_sweep");
		drive_cycle(13'd0,    64'h0000_0000_0000_0001, 8'hFF,
					13'd1024, 64'h0000_0000_0000_1001, 8'hFF,
					"region0");

		drive_cycle(13'd2048, 64'h0000_0000_0000_0002, 8'hFF,
					13'd3072, 64'h0000_0000_0000_1002, 8'hFF,
					"region1");

		drive_cycle(13'd4095, 64'h0000_0000_0000_0003, 8'hFF,
					13'd5119, 64'h0000_0000_0000_1003, 8'hFF,
					"region2");

		drive_cycle(13'd6143, 64'h0000_0000_0000_0004, 8'hFF,
					13'd7167, 64'h0000_0000_0000_1004, 8'hFF,
					"region3");

		drive_cycle(13'd8191, 64'h0000_0000_0000_0005, 8'hFF,
					13'd4096, 64'h0000_0000_0000_1005, 8'hFF,
					"region4");

		$display("[TEST] random");
		for (i = 0; i < 500; i++) begin
			logic [12:0] ra0, ra1;
			logic [63:0] rd0, rd1;
			logic [7:0]  rw0, rw1;

			ra0 = $urandom_range(0, DEPTH_WORDS-1);
			ra1 = $urandom_range(0, DEPTH_WORDS-1);

			// allow same-address cases sometimes for coverage
			if ((ra0 == ra1) && ($urandom_range(0,99) < 70))
				ra1 = (ra1 + 1) % DEPTH_WORDS;

			rd0 = {$urandom, $urandom};
			rd1 = {$urandom, $urandom};
			rw0 = $urandom_range(0, 255);
			rw1 = $urandom_range(0, 255);

			drive_cycle(ra0, rd0, rw0, ra1, rd1, rw1, $sformatf("random_%0d", i));
		end

		$display("==================================================");
		$display("TCM_MEM_RAM TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cg_ram.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule