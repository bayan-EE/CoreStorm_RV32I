`timescale 1ns/1ps

module tb_l2_tag_ram;

	localparam int TAG_W  = 20;
	localparam int DEPTH  = 128;
	localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

	logic              clk_i;
	logic              rst_i;
	logic              en_i;
	logic              wr_i;
	logic [ADDR_W-1:0] addr_i;
	logic [TAG_W-1:0]  tag_i;
	logic              valid_i;
	logic              dirty_i;
	logic [TAG_W-1:0]  tag_o;
	logic              valid_o;
	logic              dirty_o;

	l2_tag_ram #(
		.TAG_W (TAG_W),
		.DEPTH (DEPTH)
	) dut (
		.clk_i   (clk_i),
		.rst_i   (rst_i),
		.en_i    (en_i),
		.wr_i    (wr_i),
		.addr_i  (addr_i),
		.tag_i   (tag_i),
		.valid_i (valid_i),
		.dirty_i (dirty_i),
		.tag_o   (tag_o),
		.valid_o (valid_o),
		.dirty_o (dirty_o)
	);

	typedef struct packed {
		logic [TAG_W-1:0] tag;
		logic             valid;
		logic             dirty;
	} tag_entry_t;

	tag_entry_t model_mem [0:DEPTH-1];
	tag_entry_t expected_entry_q;

	int pass_count;
	int fail_count;
	int test_count;

	initial begin
		clk_i = 1'b0;
		forever #5 clk_i = ~clk_i;
	end

	task automatic check_equal_tag(
		input string          name,
		input [TAG_W-1:0]     got,
		input [TAG_W-1:0]     exp
	);
		begin
			test_count++;
			if (got !== exp) begin
				fail_count++;
				$display("[FAIL] %s got=%h exp=%h t=%0t", name, got, exp, $time);
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic check_equal_bit(
		input string          name,
		input logic           got,
		input logic           exp
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

	task automatic drive_idle();
		begin
			en_i    = 1'b0;
			wr_i    = 1'b0;
			addr_i  = '0;
			tag_i   = '0;
			valid_i = 1'b0;
			dirty_i = 1'b0;
		end
	endtask

	task automatic tag_access(
		input logic [ADDR_W-1:0] addr,
		input logic              en,
		input logic              wr,
		input logic [TAG_W-1:0]  tag,
		input logic              valid,
		input logic              dirty
	);
		automatic tag_entry_t old_entry;
		begin
			old_entry = model_mem[addr];

			@(negedge clk_i);
			addr_i  = addr;
			en_i    = en;
			wr_i    = wr;
			tag_i   = tag;
			valid_i = valid;
			dirty_i = dirty;

			@(posedge clk_i);
			#1;

			if (en) begin
				expected_entry_q = old_entry;

				check_equal_tag("tag_o_check",   tag_o,   expected_entry_q.tag);
				check_equal_bit("valid_o_check", valid_o, expected_entry_q.valid);
				check_equal_bit("dirty_o_check", dirty_o, expected_entry_q.dirty);

				if (wr) begin
					model_mem[addr].tag   = tag;
					model_mem[addr].valid = valid;
					model_mem[addr].dirty = dirty;
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

			check_equal_tag("reset_tag_zero", tag_o, '0);
			check_equal_bit("reset_valid_zero", valid_o, 1'b0);
			check_equal_bit("reset_dirty_zero", dirty_o, 1'b0);
		end
	endtask

	task automatic test_basic_write_read();
		begin
			$display("[TEST] basic_write_read");

			tag_access(5, 1'b1, 1'b1, 20'habcde, 1'b1, 1'b0);
			tag_access(5, 1'b1, 1'b0, '0,       1'b0, 1'b0);

			check_equal_tag("basic_model_tag", model_mem[5].tag, 20'habcde);
			check_equal_bit("basic_model_valid", model_mem[5].valid, 1'b1);
			check_equal_bit("basic_model_dirty", model_mem[5].dirty, 1'b0);
		end
	endtask

	task automatic test_dirty_transition();
		begin
			$display("[TEST] dirty_transition");

			tag_access(9,  1'b1, 1'b1, 20'h12345, 1'b1, 1'b0);
			tag_access(9,  1'b1, 1'b1, 20'h12345, 1'b1, 1'b1);
			tag_access(9,  1'b1, 1'b0, '0,       1'b0, 1'b0);

			check_equal_tag("dirty_model_tag", model_mem[9].tag, 20'h12345);
			check_equal_bit("dirty_model_valid", model_mem[9].valid, 1'b1);
			check_equal_bit("dirty_model_dirty", model_mem[9].dirty, 1'b1);
		end
	endtask

	task automatic test_invalidate_entry();
		begin
			begin
				$display("[TEST] invalidate_entry");

				tag_access(13, 1'b1, 1'b1, 20'h55aaa, 1'b1, 1'b1);
				tag_access(13, 1'b1, 1'b1, 20'h55aaa, 1'b0, 1'b0);
				tag_access(13, 1'b1, 1'b0, '0,       1'b0, 1'b0);

				check_equal_bit("invalidate_model_valid", model_mem[13].valid, 1'b0);
				check_equal_bit("invalidate_model_dirty", model_mem[13].dirty, 1'b0);
			end
		end
	endtask

	task automatic test_read_first_same_cycle();
		begin
			$display("[TEST] read_first_same_cycle");

			tag_access(17, 1'b1, 1'b1, 20'h11111, 1'b1, 1'b0);
			tag_access(17, 1'b1, 1'b1, 20'h22222, 1'b1, 1'b1);

			check_equal_tag("read_first_model_after_write", model_mem[17].tag, 20'h22222);
			check_equal_bit("read_first_model_valid_after_write", model_mem[17].valid, 1'b1);
			check_equal_bit("read_first_model_dirty_after_write", model_mem[17].dirty, 1'b1);

			tag_access(17, 1'b1, 1'b0, '0, 1'b0, 1'b0);
			check_equal_tag("read_first_followup_tag", tag_o, 20'h22222);
			check_equal_bit("read_first_followup_valid", valid_o, 1'b1);
			check_equal_bit("read_first_followup_dirty", dirty_o, 1'b1);
		end
	endtask

	task automatic test_idle_hold();
		logic [TAG_W-1:0] prev_tag;
		logic             prev_valid;
		logic             prev_dirty;
		begin
			$display("[TEST] idle_hold");

			tag_access(23, 1'b1, 1'b1, 20'h0f0f0, 1'b1, 1'b1);
			tag_access(23, 1'b1, 1'b0, '0,       1'b0, 1'b0);

			prev_tag   = tag_o;
			prev_valid = valid_o;
			prev_dirty = dirty_o;

			@(negedge clk_i);
			en_i    = 1'b0;
			wr_i    = 1'b0;
			addr_i  = 23;
			tag_i   = '0;
			valid_i = 1'b0;
			dirty_i = 1'b0;

			@(posedge clk_i);
			#1;

			check_equal_tag("idle_hold_tag", tag_o, prev_tag);
			check_equal_bit("idle_hold_valid", valid_o, prev_valid);
			check_equal_bit("idle_hold_dirty", dirty_o, prev_dirty);
		end
	endtask

	task automatic test_cov_directed();
		logic [ADDR_W-1:0] addr_list [0:3];
		int i;
		begin
			$display("[TEST] cov_directed");

			addr_list[0] = 0;
			addr_list[1] = DEPTH/4;
			addr_list[2] = DEPTH/2;
			addr_list[3] = DEPTH-1;

			for (i = 0; i < 4; i++) begin
				tag_access(addr_list[i], 1'b1, 1'b1, 20'h01000 + i, 1'b0, 1'b0);
				tag_access(addr_list[i], 1'b1, 1'b1, 20'h02000 + i, 1'b1, 1'b0);
				tag_access(addr_list[i], 1'b1, 1'b1, 20'h03000 + i, 1'b1, 1'b1);
				tag_access(addr_list[i], 1'b1, 1'b1, 20'h04000 + i, 1'b0, 1'b1);
				tag_access(addr_list[i], 1'b1, 1'b0, '0,            1'b0, 1'b0);
			end
		end
	endtask

	task automatic test_random(int iterations);
		logic [ADDR_W-1:0] rand_addr;
		logic              rand_en;
		logic              rand_wr;
		logic [TAG_W-1:0]  rand_tag;
		logic              rand_valid;
		logic              rand_dirty;
		int                i;
		begin
			$display("[TEST] random");

			for (i = 0; i < iterations; i++) begin
				rand_addr  = $urandom_range(0, DEPTH-1);
				rand_en    = $urandom_range(0, 1);
				rand_wr    = $urandom_range(0, 1);
				rand_tag   = $urandom() & ((1 << TAG_W) - 1);
				rand_valid = $urandom_range(0, 1);
				rand_dirty = $urandom_range(0, 1);

				if (!rand_en) begin
					rand_wr = 1'b0;
				end

				tag_access(rand_addr, rand_en, rand_wr, rand_tag, rand_valid, rand_dirty);
			end
		end
	endtask

	// -------------------------------------------------------------------------
	// Coverage
	// -------------------------------------------------------------------------
	logic [ADDR_W-1:0] cov_addr_q;
	logic              cov_en_q;
	logic              cov_wr_q;
	logic              cov_valid_i_q;
	logic              cov_dirty_i_q;

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			cov_addr_q    <= '0;
			cov_en_q      <= 1'b0;
			cov_wr_q      <= 1'b0;
			cov_valid_i_q <= 1'b0;
			cov_dirty_i_q <= 1'b0;
		end
		else begin
			cov_addr_q    <= addr_i;
			cov_en_q      <= en_i;
			cov_wr_q      <= wr_i;
			cov_valid_i_q <= valid_i;
			cov_dirty_i_q <= dirty_i;
		end
	end

	covergroup cg_l2_tag_ram @(posedge clk_i);
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

		cp_valid_dirty: coverpoint {cov_valid_i_q, cov_dirty_i_q} iff (cov_en_q && cov_wr_q) {
			bins vv0dd0 = {2'b00};
			bins vv1dd0 = {2'b10};
			bins vv1dd1 = {2'b11};
			bins vv0dd1 = {2'b01};
		}

		x_rw_addr: cross cp_wr, cp_addr;
		x_addr_vd: cross cp_addr, cp_valid_dirty;
	endgroup

	cg_l2_tag_ram cg_inst;

	initial begin
		pass_count = 0;
		fail_count = 0;
		test_count = 0;
		cg_inst = new();

		$display("[TEST] l2_tag_ram_reset");
		reset_dut();

		test_basic_write_read();
		test_dirty_transition();
		test_invalidate_entry();
		test_read_first_same_cycle();
		test_idle_hold();
		test_cov_directed();
		test_random(1000);

		$display("==================================================");
		$display("L2_TAG_RAM TB SUMMARY");
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
		$dumpfile("tb_l2_tag_ram.vcd");
		$dumpvars(0, tb_l2_tag_ram);
	end

endmodule