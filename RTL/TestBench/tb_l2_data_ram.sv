`timescale 1ns/1ps

module tb_l2_data_ram;

	localparam int DATA_W = 256;
	localparam int DEPTH  = 128;
	localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
	localparam int BE_W   = DATA_W / 8;

	logic              clk_i;
	logic              rst_i;
	logic              en_i;
	logic              wr_i;
	logic [ADDR_W-1:0] addr_i;
	logic [DATA_W-1:0] wdata_i;
	logic [BE_W-1:0]   wstrb_i;
	logic [DATA_W-1:0] rdata_o;

	l2_data_ram #(
		.DATA_W(DATA_W),
		.DEPTH (DEPTH)
	) dut (
		.clk_i   (clk_i),
		.rst_i   (rst_i),
		.en_i    (en_i),
		.wr_i    (wr_i),
		.addr_i  (addr_i),
		.wdata_i (wdata_i),
		.wstrb_i (wstrb_i),
		.rdata_o (rdata_o)
	);

	logic [DATA_W-1:0] model_mem [0:DEPTH-1];
	logic [DATA_W-1:0] expected_rdata_q;

	int pass_count;
	int fail_count;
	int test_count;

	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	function automatic [DATA_W-1:0] apply_wstrb(
		input [DATA_W-1:0] old_data,
		input [DATA_W-1:0] new_data,
		input [BE_W-1:0]   strb
	);
		automatic logic [DATA_W-1:0] tmp;
		int k;
		begin
			tmp = old_data;
			for (k = 0; k < BE_W; k++) begin
				if (strb[k]) begin
					tmp[8*k +: 8] = new_data[8*k +: 8];
				end
			end
			return tmp;
		end
	endfunction

	task automatic check_equal(
		input string           name,
		input [DATA_W-1:0]     got,
		input [DATA_W-1:0]     exp
	);
		begin
			test_count++;
			if (got !== exp) begin
				fail_count++;
				$display("[FAIL] %s got=%064h exp=%064h t=%0t", name, got, exp, $time);
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic drive_idle();
		begin
			en_i    = 1'b0;
			wr_i    = 1'b0;
			addr_i  = '0;
			wdata_i = '0;
			wstrb_i = '0;
		end
	endtask

	task automatic ram_access(
		input logic [ADDR_W-1:0] addr,
		input logic              en,
		input logic              wr,
		input logic [DATA_W-1:0] wdata,
		input logic [BE_W-1:0]   wstrb
	);
		automatic logic [DATA_W-1:0] old_val;
		begin
			old_val = model_mem[addr];

			@(negedge clk_i);
			addr_i  = addr;
			en_i    = en;
			wr_i    = wr;
			wdata_i = wdata;
			wstrb_i = wstrb;

			@(posedge clk_i);
			#1;

			if (en) begin
				expected_rdata_q = old_val;
				check_equal("rdata_check", rdata_o, expected_rdata_q);

				if (wr) begin
					model_mem[addr] = apply_wstrb(model_mem[addr], wdata, wstrb);
				end
			end
		end
	endtask

	task automatic reset_dut();
		int i;
		begin
			rst_i = 1'b1;
			drive_idle();

			repeat (3) @(posedge clk_i);
			#1;

			for (i = 0; i < DEPTH; i++) begin
				model_mem[i] = '0;
			end

			rst_i = 1'b0;
			@(posedge clk_i);
			#1;

			check_equal("reset_rdata_zero", rdata_o, '0);
		end
	endtask

	task automatic test_basic_write_read();
		logic [DATA_W-1:0] data0;
		begin
			$display("[TEST] basic_write_read");
			data0 = 256'h01234567_89abcdef_deadbeef_cafebabe_00112233_44556677_8899aabb_ccddeeff;

			ram_access(7, 1'b1, 1'b1, data0, {BE_W{1'b1}});
			ram_access(7, 1'b1, 1'b0, '0,   '0);

			check_equal("basic_write_read_mem_model", model_mem[7], data0);
		end
	endtask

	task automatic test_partial_write();
		logic [DATA_W-1:0] base_data;
		logic [DATA_W-1:0] patch_data;
		logic [DATA_W-1:0] exp_data;
		logic [BE_W-1:0]   mask;
		begin
			$display("[TEST] partial_write");
			base_data  = 256'hffffeeee_ddddcccc_bbbbaaaa_99998888_77776666_55554444_33332222_11110000;
			patch_data = 256'h00010203_04050607_08090a0b_0c0d0e0f_10111213_14151617_18191a1b_1c1d1e1f;
			mask       = 32'h00ff00ff;

			ram_access(11, 1'b1, 1'b1, base_data,  {BE_W{1'b1}});
			ram_access(11, 1'b1, 1'b1, patch_data, mask);
			ram_access(11, 1'b1, 1'b0, '0,         '0);

			exp_data = apply_wstrb(base_data, patch_data, mask);
			check_equal("partial_write_mem_model", model_mem[11], exp_data);
		end
	endtask

	task automatic test_read_first_same_cycle();
		logic [DATA_W-1:0] old_data;
		logic [DATA_W-1:0] new_data;
		begin
			$display("[TEST] read_first_same_cycle");
			old_data = 256'h11111111_22222222_33333333_44444444_55555555_66666666_77777777_88888888;
			new_data = 256'haaaaaaaa_bbbbbbbb_cccccccc_dddddddd_eeeeeeee_ffffffff_12345678_87654321;

			ram_access(19, 1'b1, 1'b1, old_data, {BE_W{1'b1}});
			ram_access(19, 1'b1, 1'b1, new_data, {BE_W{1'b1}});

			// During second access rdata must return old_data because of read-first
			check_equal("read_first_behavior_model", model_mem[19], new_data);

			ram_access(19, 1'b1, 1'b0, '0, '0);
			check_equal("read_first_followup_read", rdata_o, new_data);
		end
	endtask

	task automatic test_idle_hold();
		logic [DATA_W-1:0] prev_rdata;
		begin
			$display("[TEST] idle_hold");
			ram_access(23, 1'b1, 1'b1, 256'h55aa55aa55aa55aa55aa55aa55aa55aa_aa55aa55aa55aa55aa55aa55aa55aa55, {BE_W{1'b1}});
			ram_access(23, 1'b1, 1'b0, '0, '0);

			prev_rdata = rdata_o;

			@(negedge clk_i);
			en_i    = 1'b0;
			wr_i    = 1'b0;
			addr_i  = 23;
			wdata_i = '0;
			wstrb_i = '0;

			@(posedge clk_i);
			#1;
			check_equal("idle_hold_rdata", rdata_o, prev_rdata);
		end
	endtask

	task automatic test_random(int iterations);
		logic [ADDR_W-1:0] rand_addr;
		logic              rand_en;
		logic              rand_wr;
		logic [DATA_W-1:0] rand_wdata;
		logic [BE_W-1:0]   rand_wstrb;
		int                i;
		int                b;
		begin
			$display("[TEST] random");
			for (i = 0; i < iterations; i++) begin
				rand_addr  = $urandom_range(0, DEPTH-1);
				rand_en    = $urandom_range(0, 1);
				rand_wr    = $urandom_range(0, 1);

				for (b = 0; b < DATA_W/32; b++) begin
					rand_wdata[32*b +: 32] = $urandom();
				end

				case ($urandom_range(0, 4))
					0: begin
						rand_wstrb = '0;
						rand_wstrb[$urandom_range(0, BE_W-1)] = 1'b1;
					end
					1: begin
						rand_wstrb = '0;
						for (b = 0; b < 4; b++) begin
							rand_wstrb[$urandom_range(0, BE_W-1)] = 1'b1;
						end
					end
					2: begin
						rand_wstrb = '0;
						for (b = 0; b < (BE_W/2); b++) begin
							rand_wstrb[b] = 1'b1;
						end
					end
					3: begin
						rand_wstrb = '0;
						for (b = 0; b < (BE_W-8); b++) begin
							rand_wstrb[b] = 1'b1;
						end
					end
					default: begin
						rand_wstrb = {BE_W{1'b1}};
					end
				endcase

				if (!rand_en) begin
					rand_wr    = 1'b0;
					rand_wstrb = '0;
				end

				if (rand_wr && (rand_wstrb == '0)) begin
					rand_wstrb[$urandom_range(0, BE_W-1)] = 1'b1;
				end

				ram_access(rand_addr, rand_en, rand_wr, rand_wdata, rand_wstrb);
			end
		end
	endtask

	task automatic test_mask_coverage();
		logic [DATA_W-1:0] data_pat;
		logic [BE_W-1:0]   mask_one;
		logic [BE_W-1:0]   mask_few;
		logic [BE_W-1:0]   mask_half;
		logic [BE_W-1:0]   mask_most;
		logic [BE_W-1:0]   mask_full;

		logic [ADDR_W-1:0] addr_list [0:3];
		int i;
		begin
			$display("[TEST] mask_coverage");

			data_pat = 256'hfedcba98_76543210_0f1e2d3c_4b5a6978_89abcdef_01234567_deadbeef_cafebabe;

			// One byte enabled
			mask_one = '0;
			mask_one[0] = 1'b1;

			// Few bytes enabled: 4 bytes
			mask_few = '0;
			mask_few[0] = 1'b1;
			mask_few[3] = 1'b1;
			mask_few[7] = 1'b1;
			mask_few[12] = 1'b1;

			// Half line enabled: 16 bytes
			mask_half = '0;
			for (i = 0; i < (BE_W/2); i++) begin
				mask_half[i] = 1'b1;
			end

			// Most line enabled: 24 bytes
			mask_most = '0;
			for (i = 0; i < (BE_W-8); i++) begin
				mask_most[i] = 1'b1;
			end

			// Full line enabled
			mask_full = {BE_W{1'b1}};

			// Address spread for low / mid1 / mid2 / high
			addr_list[0] = 0;
			addr_list[1] = DEPTH/4;
			addr_list[2] = DEPTH/2;
			addr_list[3] = DEPTH-1;

			for (i = 0; i < 4; i++) begin
				ram_access(addr_list[i], 1'b1, 1'b1, data_pat ^ i, mask_one);
				ram_access(addr_list[i], 1'b1, 1'b1, data_pat ^ (32'h100 + i), mask_few);
				ram_access(addr_list[i], 1'b1, 1'b1, data_pat ^ (32'h200 + i), mask_half);
				ram_access(addr_list[i], 1'b1, 1'b1, data_pat ^ (32'h300 + i), mask_most);
				ram_access(addr_list[i], 1'b1, 1'b1, data_pat ^ (32'h400 + i), mask_full);
			end
		end
	endtask

	// -------------------------------------------------------------------------
	// Coverage
	// -------------------------------------------------------------------------
	logic [ADDR_W-1:0] cov_addr_q;
	logic              cov_en_q;
	logic              cov_wr_q;
	logic [BE_W-1:0]   cov_wstrb_q;

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			cov_addr_q  <= '0;
			cov_en_q    <= 1'b0;
			cov_wr_q    <= 1'b0;
			cov_wstrb_q <= '0;
		end
		else begin
			cov_addr_q  <= addr_i;
			cov_en_q    <= en_i;
			cov_wr_q    <= wr_i;
			cov_wstrb_q <= wstrb_i;
		end
	end

	covergroup cg_l2_data_ram @(posedge clk_i);
		option.per_instance = 1;

		cp_en: coverpoint cov_en_q {
			bins off = {0};
			bins on  = {1};
		}

		cp_wr: coverpoint cov_wr_q iff (cov_en_q) {
			bins rd = {0};
			bins wr = {1};
		}

		cp_addr: coverpoint cov_addr_q iff (cov_en_q) {
			bins low  = {[0:(DEPTH/4)-1]};
			bins mid1 = {[(DEPTH/4):(DEPTH/2)-1]};
			bins mid2 = {[(DEPTH/2):(3*DEPTH/4)-1]};
			bins high = {[(3*DEPTH/4):(DEPTH-1)]};
		}

		cp_mask_kind: coverpoint $countones(cov_wstrb_q) iff (cov_en_q && cov_wr_q) {
			bins one_byte   = {1};
			bins few_bytes  = {[2:7]};
			bins half_line  = {[8:16]};
			bins most_line  = {[17:31]};
			bins full_line  = {BE_W};
		}

		cp_full_mask: coverpoint (cov_wstrb_q == {BE_W{1'b1}}) iff (cov_en_q && cov_wr_q) {
			bins partial = {0};
			bins full    = {1};
		}

		x_rw_addr: cross cp_wr, cp_addr;
		x_wr_mask: cross cp_addr, cp_mask_kind;
	endgroup

	cg_l2_data_ram cg_inst;

	initial begin
		pass_count = 0;
		fail_count = 0;
		test_count = 0;
		cg_inst = new();

		$display("[TEST] l2_data_ram_reset");
		reset_dut();

		test_basic_write_read();
		test_partial_write();
		test_read_first_same_cycle();
		test_idle_hold();
		test_mask_coverage();
		test_random(1500);

		$display("==================================================");
		$display("L2_DATA_RAM TB SUMMARY");
		$display("  test_count = %0d", test_count);
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cg_inst.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0) begin
			$display("TB PASSED");
		end
		else begin
			$display("TB FAILED");
		end

		$finish;
	end

	initial begin
		$dumpfile("tb_l2_data_ram.vcd");
		$dumpvars(0, tb_l2_data_ram);
	end

endmodule