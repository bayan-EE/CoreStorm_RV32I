`timescale 1ns/1ps

module tb_shared_l2_cache_single;

	localparam int ADDR_W    = 32;
	localparam int LINE_W    = 256;
	localparam int SETS      = 64;
	localparam int OFFSET_W  = 5;
	localparam int IDX_W     = (SETS <= 1) ? 1 : $clog2(SETS);
	localparam int TAG_W     = ADDR_W - OFFSET_W - IDX_W;
	localparam int BE_W      = LINE_W / 8;

	logic                 clk_i;
	logic                 rst_i;

	logic                 req_valid_i;
	logic                 req_ready_o;
	logic                 req_we_i;
	logic [ADDR_W-1:0]    req_addr_i;
	logic [LINE_W-1:0]    req_wdata_i;
	logic [BE_W-1:0]      req_wmask_i;

	logic                 resp_valid_o;
	logic                 resp_hit_o;
	logic [LINE_W-1:0]    resp_rdata_o;

	shared_l2_cache_single #(
		.ADDR_W   (ADDR_W),
		.LINE_W   (LINE_W),
		.SETS     (SETS),
		.OFFSET_W (OFFSET_W)
	) dut (
		.clk_i       (clk_i),
		.rst_i       (rst_i),
		.req_valid_i (req_valid_i),
		.req_ready_o (req_ready_o),
		.req_we_i    (req_we_i),
		.req_addr_i  (req_addr_i),
		.req_wdata_i (req_wdata_i),
		.req_wmask_i (req_wmask_i),
		.resp_valid_o(resp_valid_o),
		.resp_hit_o  (resp_hit_o),
		.resp_rdata_o(resp_rdata_o)
	);

	typedef struct packed {
		logic [TAG_W-1:0]  tag;
		logic              valid;
		logic              dirty;
		logic [LINE_W-1:0] line;
	} line_entry_t;

	line_entry_t model_mem [0:SETS-1];

	int pass_count;
	int fail_count;
	int test_count;

	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	function automatic [LINE_W-1:0] apply_wmask(
		input [LINE_W-1:0] old_line,
		input [LINE_W-1:0] new_line,
		input [BE_W-1:0]   wmask
	);
		automatic logic [LINE_W-1:0] tmp;
		int i;
		begin
			tmp = old_line;
			for (i = 0; i < BE_W; i++) begin
				if (wmask[i]) begin
					tmp[8*i +: 8] = new_line[8*i +: 8];
				end
			end
			return tmp;
		end
	endfunction

	function automatic [IDX_W-1:0] get_idx(input [ADDR_W-1:0] addr);
		begin
			return addr[OFFSET_W + IDX_W - 1 : OFFSET_W];
		end
	endfunction

	function automatic [TAG_W-1:0] get_tag(input [ADDR_W-1:0] addr);
		begin
			return addr[ADDR_W-1 : OFFSET_W + IDX_W];
		end
	endfunction

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

	task automatic check_line(
		input string             name,
		input [LINE_W-1:0]       got,
		input [LINE_W-1:0]       exp
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
			req_valid_i = 1'b0;
			req_we_i    = 1'b0;
			req_addr_i  = '0;
			req_wdata_i = '0;
			req_wmask_i = '0;
		end
	endtask

	task automatic reset_dut();
		int i;
		begin
			rst_i = 1'b1;
			drive_idle();

			repeat (3) @(posedge clk_i);
			#1;

			for (i = 0; i < SETS; i++) begin
				model_mem[i] = '0;
			end

			rst_i = 1'b0;
			@(posedge clk_i);
			#1;

			check_bit("reset_req_ready", req_ready_o, 1'b1);
			check_bit("reset_resp_valid", resp_valid_o, 1'b0);
		end
	endtask

	task automatic send_req_and_check(
		input logic              we,
		input logic [ADDR_W-1:0] addr,
		input logic [LINE_W-1:0] wdata,
		input logic [BE_W-1:0]   wmask
	);
		automatic logic [IDX_W-1:0] idx;
		automatic logic [TAG_W-1:0] tag;
		automatic logic             exp_hit;
		automatic logic [LINE_W-1:0] exp_rdata;
		begin
			idx = get_idx(addr);
			tag = get_tag(addr);

			exp_hit   = model_mem[idx].valid && (model_mem[idx].tag == tag);
			exp_rdata = exp_hit ? model_mem[idx].line : '0;

			@(negedge clk_i);
			req_valid_i = 1'b1;
			req_we_i    = we;
			req_addr_i  = addr;
			req_wdata_i = wdata;
			req_wmask_i = wmask;

			#1;
			check_bit("req_ready_before_accept", req_ready_o, 1'b1);

			@(posedge clk_i);
			#1;

			@(negedge clk_i);
			req_valid_i = 1'b0;
			req_we_i    = 1'b0;
			req_addr_i  = '0;
			req_wdata_i = '0;
			req_wmask_i = '0;

			@(posedge clk_i);
			#1;

			check_bit("resp_valid", resp_valid_o, 1'b1);
			check_bit("resp_hit",   resp_hit_o,   exp_hit);
			check_line("resp_rdata", resp_rdata_o, exp_rdata);

			if (we) begin
				if (exp_hit) begin
					model_mem[idx].line  = apply_wmask(model_mem[idx].line, wdata, wmask);
					model_mem[idx].dirty = 1'b1;
				end
				else begin
					model_mem[idx].line  = apply_wmask('0, wdata, wmask);
					model_mem[idx].tag   = tag;
					model_mem[idx].valid = 1'b1;
					model_mem[idx].dirty = 1'b1;
				end
			end
		end
	endtask

	task automatic test_read_miss();
		logic [ADDR_W-1:0] a;
		begin
			$display("[TEST] read_miss");
			a = 32'h0000_0040;
			send_req_and_check(1'b0, a, '0, '0);
		end
	endtask

	task automatic test_write_miss_allocate_then_read_hit();
		logic [ADDR_W-1:0] a;
		logic [LINE_W-1:0] d;
		begin
			$display("[TEST] write_miss_allocate_then_read_hit");
			a = 32'h0000_0080;
			d = 256'h01234567_89abcdef_deadbeef_cafebabe_00112233_44556677_8899aabb_ccddeeff;

			send_req_and_check(1'b1, a, d, {BE_W{1'b1}});
			send_req_and_check(1'b0, a, '0, '0);

			check_line("alloc_then_read_model", model_mem[get_idx(a)].line, d);
		end
	endtask

	task automatic test_write_hit_partial();
		logic [ADDR_W-1:0] a;
		logic [LINE_W-1:0] base_d;
		logic [LINE_W-1:0] patch_d;
		logic [LINE_W-1:0] exp_d;
		logic [BE_W-1:0]   m;
		begin
			$display("[TEST] write_hit_partial");
			a      = 32'h0000_0100;
			base_d = 256'hffffeeee_ddddcccc_bbbbaaaa_99998888_77776666_55554444_33332222_11110000;
			patch_d= 256'h00010203_04050607_08090a0b_0c0d0e0f_10111213_14151617_18191a1b_1c1d1e1f;
			m      = 32'h00ff00ff;

			send_req_and_check(1'b1, a, base_d, {BE_W{1'b1}});
			send_req_and_check(1'b1, a, patch_d, m);
			send_req_and_check(1'b0, a, '0, '0);

			exp_d = apply_wmask(base_d, patch_d, m);
			check_line("write_hit_partial_model", model_mem[get_idx(a)].line, exp_d);
		end
	endtask

	task automatic test_conflict_miss_same_index();
		logic [ADDR_W-1:0] a0;
		logic [ADDR_W-1:0] a1;
		logic [LINE_W-1:0] d0;
		logic [LINE_W-1:0] d1;
		begin
			$display("[TEST] conflict_miss_same_index");

			a0 = 32'h0000_0200;
			a1 = a0 ^ (32'h1 << (OFFSET_W + IDX_W)); // same index, different tag

			d0 = 256'haaaa0000_bbbb1111_cccc2222_dddd3333_eeee4444_ffff5555_12345678_87654321;
			d1 = 256'h11112222_33334444_55556666_77778888_9999aaaa_bbbbcccc_ddddeeee_ffff0000;

			send_req_and_check(1'b1, a0, d0, {BE_W{1'b1}});
			send_req_and_check(1'b0, a0, '0, '0);

			send_req_and_check(1'b1, a1, d1, {BE_W{1'b1}});
			send_req_and_check(1'b0, a1, '0, '0);

			send_req_and_check(1'b0, a0, '0, '0); // should miss now
		end
	endtask

	task automatic test_back_to_back_with_ready();
		logic [ADDR_W-1:0] a;
		logic [LINE_W-1:0] d;
		begin
			$display("[TEST] back_to_back_with_ready");
			a = 32'h0000_0300;
			d = 256'hcafecafe_deadbeef_01010101_02020202_03030303_04040404_05050505_06060606;

			send_req_and_check(1'b1, a, d, {BE_W{1'b1}});
			send_req_and_check(1'b0, a, '0, '0);
			send_req_and_check(1'b0, a, '0, '0);
		end
	endtask

	task automatic test_cov_directed();
		logic [ADDR_W-1:0] a [0:3];
		logic [LINE_W-1:0] d;
		logic [BE_W-1:0] m_one;
		logic [BE_W-1:0] m_half;
		logic [BE_W-1:0] m_full;
		int i;
		begin
			$display("[TEST] cov_directed");

			a[0] = 32'h0000_0000;
			a[1] = 32'h0000_0200;
			a[2] = 32'h0000_0400;
			a[3] = 32'h0000_0600;

			d = 256'h13579bdf_2468ace0_a5a5a5a5_5a5a5a5a_deadbeef_cafebabe_11223344_55667788;

			m_one = '0;
			m_one[0] = 1'b1;

			m_half = '0;
			for (i = 0; i < BE_W/2; i++) begin
				m_half[i] = 1'b1;
			end

			m_full = {BE_W{1'b1}};

			for (i = 0; i < 4; i++) begin
				send_req_and_check(1'b0, a[i], '0, '0);      // read miss
				send_req_and_check(1'b1, a[i], d ^ i, m_one);
				send_req_and_check(1'b1, a[i], d ^ (32'h100+i), m_half);
				send_req_and_check(1'b1, a[i], d ^ (32'h200+i), m_full);
				send_req_and_check(1'b0, a[i], '0, '0);      // read hit
			end
		end
	endtask

	task automatic test_random(int iterations);
		logic              we;
		logic [ADDR_W-1:0] addr;
		logic [LINE_W-1:0] wdata;
		logic [BE_W-1:0]   wmask;
		int i, j;
		begin
			$display("[TEST] random");
			for (i = 0; i < iterations; i++) begin
				we   = $urandom_range(0, 1);
				addr = {$urandom(), $urandom()};
				addr[OFFSET_W-1:0] = '0;

				for (j = 0; j < LINE_W/32; j++) begin
					wdata[32*j +: 32] = $urandom();
				end

				if (!we) begin
					wmask = '0;
				end
				else begin
					case ($urandom_range(0, 2))
						0: begin
							wmask = '0;
							wmask[$urandom_range(0, BE_W-1)] = 1'b1;
						end
						1: begin
							wmask = '0;
							for (j = 0; j < BE_W/2; j++) begin
								wmask[j] = 1'b1;
							end
						end
						default: begin
							wmask = {BE_W{1'b1}};
						end
					endcase
				end

				send_req_and_check(we, addr, wdata, wmask);
			end
		end
	endtask

	// -------------------------------------------------------------------------
	// Coverage
	// -------------------------------------------------------------------------
	logic                 cov_req_we_q;
	logic                 cov_resp_hit_q;
	logic                 cov_resp_valid_q;
	logic [ADDR_W-1:0]    cov_req_addr_q;
	logic [BE_W-1:0]      cov_req_wmask_q;

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			cov_req_we_q     <= 1'b0;
			cov_resp_hit_q   <= 1'b0;
			cov_resp_valid_q <= 1'b0;
			cov_req_addr_q   <= '0;
			cov_req_wmask_q  <= '0;
		end
		else begin
			cov_req_we_q     <= req_we_i;
			cov_resp_hit_q   <= resp_hit_o;
			cov_resp_valid_q <= resp_valid_o;
			cov_req_addr_q   <= req_addr_i;
			cov_req_wmask_q  <= req_wmask_i;
		end
	end

	covergroup cg_shared_l2_cache_single @(posedge clk_i);
		option.per_instance = 1;

		cp_req_type: coverpoint cov_req_we_q {
			bins read  = {0};
			bins write = {1};
		}

		cp_resp_hit: coverpoint cov_resp_hit_q iff (cov_resp_valid_q) {
			bins miss = {0};
			bins hit  = {1};
		}

		cp_addr_region: coverpoint get_idx(cov_req_addr_q) {
			bins low  = {[0:(SETS/4)-1]};
			bins mid1 = {[(SETS/4):(SETS/2)-1]};
			bins mid2 = {[(SETS/2):(3*SETS/4)-1]};
			bins high = {[(3*SETS/4):(SETS-1)]};
		}

		cp_mask_kind: coverpoint $countones(cov_req_wmask_q) iff (cov_req_we_q) {
			bins one   = {1};
			bins half  = {BE_W/2};
			bins full  = {BE_W};
		}

		x_type_hit: cross cp_req_type, cp_resp_hit;
		x_addr_hit: cross cp_addr_region, cp_resp_hit;
		x_mask_hit: cross cp_mask_kind, cp_resp_hit;
	endgroup

	cg_shared_l2_cache_single cg_inst;

	initial begin
		pass_count = 0;
		fail_count = 0;
		test_count = 0;
		cg_inst = new();

		$display("[TEST] shared_l2_cache_single_reset");
		reset_dut();

		test_read_miss();
		test_write_miss_allocate_then_read_hit();
		test_write_hit_partial();
		test_conflict_miss_same_index();
		test_back_to_back_with_ready();
		test_cov_directed();
		test_random(800);

		$display("==================================================");
		$display("SHARED_L2_CACHE_SINGLE TB SUMMARY");
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
		$dumpfile("tb_shared_l2_cache_single.vcd");
		$dumpvars(0, tb_shared_l2_cache_single);
	end

endmodule