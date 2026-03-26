`timescale 1ns/1ps


import coherence_pkg::*;

module tb_coherence_controller;

	localparam int NUM_CORES  = 4;
	localparam int CORE_IDX_W = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES);

	logic                              clk;
	logic                              rst;

	logic [NUM_CORES-1:0]              coh_req_valid_i;
	snoop_cmd_t [NUM_CORES-1:0]        coh_req_cmd_i;
	logic [NUM_CORES-1:0][31:0]        coh_req_addr_i;
	logic [NUM_CORES-1:0]              coh_req_ready_o;

	logic [NUM_CORES-1:0]              cache_snoop_hit_i;
	logic [NUM_CORES-1:0]              cache_snoop_dirty_i;
	logic [NUM_CORES-1:0]              cache_snoop_ack_i;

	logic [NUM_CORES-1:0]              snoop_valid_o;
	snoop_cmd_t [NUM_CORES-1:0]        snoop_cmd_o;
	logic [NUM_CORES-1:0][31:0]        snoop_addr_o;

	logic                              trans_done_o;
	logic [CORE_IDX_W-1:0]            trans_core_o;
	snoop_cmd_t                        trans_cmd_o;
	logic [31:0]                       trans_addr_o;
	logic                              trans_shared_o;
	logic                              trans_dirty_o;
	logic                              trans_need_mem_read_o;
	logic                              trans_need_writeback_o;
	logic                              busy_o;

	int pass_count;
	int fail_count;

	logic [NUM_CORES-1:0]              plan_hit_q;
	logic [NUM_CORES-1:0]              plan_dirty_q;

	// Written by tasks only
	logic [NUM_CORES-1:0][3:0]         plan_delay_init;
	logic [NUM_CORES-1:0]              responder_active_init;

	// Written by always_ff only
	logic [NUM_CORES-1:0][3:0]         plan_delay_q;
	logic [NUM_CORES-1:0]              responder_active_q;
	int cov_req_core;
	int cov_req_cmd;
	int cov_shared;
	int cov_dirty;
	int cov_need_mem;
	int cov_need_wb;

	covergroup cg_controller;
		option.per_instance = 1;

		cp_core : coverpoint cov_req_core {
			bins c0 = {0};
			bins c1 = {1};
			bins c2 = {2};
			bins c3 = {3};
		}

		cp_cmd : coverpoint cov_req_cmd {
			bins busrd   = {0};
			bins busrdx  = {1};
			bins busupgr = {2};
		}

		cp_shared : coverpoint cov_shared {
			bins no  = {0};
			bins yes = {1};
		}

		cp_dirty : coverpoint cov_dirty {
			bins no  = {0};
			bins yes = {1};
		}

		cp_need_mem : coverpoint cov_need_mem {
			bins no  = {0};
			bins yes = {1};
		}

		cp_need_wb : coverpoint cov_need_wb {
			bins no  = {0};
			bins yes = {1};
		}

		x_cmd_dirty : cross cp_cmd, cp_dirty;
		x_cmd_mem   : cross cp_cmd, cp_need_mem;
	endgroup

	cg_controller cov_inst = new();

	coherence_controller #(
		.NUM_CORES(NUM_CORES)
	) dut (
		.clk_i                 (clk),
		.rst_i                 (rst),
		.coh_req_valid_i       (coh_req_valid_i),
		.coh_req_cmd_i         (coh_req_cmd_i),
		.coh_req_addr_i        (coh_req_addr_i),
		.coh_req_ready_o       (coh_req_ready_o),
		.cache_snoop_hit_i     (cache_snoop_hit_i),
		.cache_snoop_dirty_i   (cache_snoop_dirty_i),
		.cache_snoop_ack_i     (cache_snoop_ack_i),
		.snoop_valid_o         (snoop_valid_o),
		.snoop_cmd_o           (snoop_cmd_o),
		.snoop_addr_o          (snoop_addr_o),
		.trans_done_o          (trans_done_o),
		.trans_core_o          (trans_core_o),
		.trans_cmd_o           (trans_cmd_o),
		.trans_addr_o          (trans_addr_o),
		.trans_shared_o        (trans_shared_o),
		.trans_dirty_o         (trans_dirty_o),
		.trans_need_mem_read_o (trans_need_mem_read_o),
		.trans_need_writeback_o(trans_need_writeback_o),
		.busy_o                (busy_o)
	);

	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	task automatic tick(input int n = 1);
		repeat (n) @(posedge clk);
	endtask

	task automatic check_bit(input string name, input logic got, input logic exp);
		begin
			if (got !== exp) begin
				$display("[FAIL] %s got=%0b exp=%0b t=%0t", name, got, exp, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic check_u32(input string name, input logic [31:0] got, input logic [31:0] exp);
		begin
			if (got !== exp) begin
				$display("[FAIL] %s got=%08x exp=%08x t=%0t", name, got, exp, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic issue_request(
		input int         req_core,
		input snoop_cmd_t req_cmd,
		input logic [31:0] req_addr,
		input logic [NUM_CORES-1:0] hit_mask,
		input logic [NUM_CORES-1:0] dirty_mask
	);
		int i;
		int timeout;
		begin
			for (i = 0; i < NUM_CORES; i++) begin
				coh_req_valid_i[i] = 1'b0;
				coh_req_cmd_i[i]   = SNOOP_NONE;
				coh_req_addr_i[i]  = 32'h0;
			end

			for (i = 0; i < NUM_CORES; i++) begin
				plan_hit_q[i]             = hit_mask[i];
				plan_dirty_q[i]           = dirty_mask[i];
				responder_active_init[i]  = 1'b0;
				plan_delay_init[i]        = $urandom_range(0, 3);
			end

			coh_req_valid_i[req_core] = 1'b1;
			coh_req_cmd_i[req_core]   = req_cmd;
			coh_req_addr_i[req_core]  = req_addr;

			timeout = 0;
			while (!coh_req_ready_o[req_core] && timeout < 50) begin
				tick(1);
				timeout++;
			end

			if (!coh_req_ready_o[req_core]) begin
				$display("[FAIL] request core%0d not accepted in time t=%0t", req_core, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			coh_req_valid_i[req_core] = 1'b0;

			for (i = 0; i < NUM_CORES; i++) begin
				if (i != req_core) begin
					responder_active_init[i] = 1'b1;
				end
			end
		end
	endtask

	always_ff @(posedge clk) begin : proc_cache_responders
		int i;

		if (rst) begin
			cache_snoop_hit_i    <= '0;
			cache_snoop_dirty_i  <= '0;
			cache_snoop_ack_i    <= '0;

			plan_delay_q         <= '0;
			responder_active_q   <= '0;
		end
		else begin
			cache_snoop_hit_i    <= '0;
			cache_snoop_dirty_i  <= '0;
			cache_snoop_ack_i    <= '0;

			// Load per-transaction init values
			if (|coh_req_ready_o) begin
				plan_delay_q       <= plan_delay_init;
				responder_active_q <= responder_active_init;
			end

			for (i = 0; i < NUM_CORES; i++) begin
				if (responder_active_q[i] && snoop_valid_o[i]) begin
					if (plan_delay_q[i] != 0) begin
						plan_delay_q[i] <= plan_delay_q[i] - 1'b1;
					end
					else begin
						cache_snoop_ack_i[i]   <= 1'b1;
						cache_snoop_hit_i[i]   <= plan_hit_q[i];
						cache_snoop_dirty_i[i] <= plan_dirty_q[i];
						responder_active_q[i]  <= 1'b0;
					end
				end
			end
		end
	end

	task automatic wait_done_and_check(
		input int          exp_core,
		input snoop_cmd_t  exp_cmd,
		input logic [31:0] exp_addr,
		input logic        exp_shared,
		input logic        exp_dirty,
		input logic        exp_need_mem,
		input logic        exp_need_wb
	);
		int timeout;
		begin
			timeout = 0;
			while (!trans_done_o && timeout < 100) begin
				tick(1);
				timeout++;
			end

			if (!trans_done_o) begin
				$display("[FAIL] timeout waiting for controller done t=%0t", $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			check_u32("trans_addr_o", trans_addr_o, exp_addr);
			check_bit("trans_shared_o", trans_shared_o, exp_shared);
			check_bit("trans_dirty_o", trans_dirty_o, exp_dirty);
			check_bit("trans_need_mem_read_o", trans_need_mem_read_o, exp_need_mem);
			check_bit("trans_need_writeback_o", trans_need_writeback_o, exp_need_wb);

			if (trans_core_o !== exp_core[CORE_IDX_W-1:0]) begin
				$display("[FAIL] trans_core_o got=%0d exp=%0d t=%0t", trans_core_o, exp_core, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			if (trans_cmd_o !== exp_cmd) begin
				$display("[FAIL] trans_cmd_o got=%0d exp=%0d t=%0t", trans_cmd_o, exp_cmd, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			cov_req_core = exp_core;
			cov_req_cmd  = exp_cmd;
			cov_shared   = exp_shared;
			cov_dirty    = exp_dirty;
			cov_need_mem = exp_need_mem;
			cov_need_wb  = exp_need_wb;
			cov_inst.sample();
		end
	endtask

	task automatic reset_dut;
		int i;
		begin
			rst = 1'b1;

			for (i = 0; i < NUM_CORES; i++) begin
				coh_req_valid_i[i]      = 1'b0;
				coh_req_cmd_i[i]        = SNOOP_NONE;
				coh_req_addr_i[i]       = 32'h0;

				plan_hit_q[i]           = 1'b0;
				plan_dirty_q[i]         = 1'b0;
				plan_delay_init[i]      = '0;
				responder_active_init[i]= 1'b0;
			end

			tick(4);
			rst = 1'b0;
			tick(2);
		end
	endtask

	task automatic test_lowest_core_priority;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] lowest_core_priority");

			hit_mask   = '0;
			dirty_mask = '0;

			coh_req_valid_i = '0;
			coh_req_cmd_i[0] = SNOOP_BUSRDX;
			coh_req_addr_i[0] = 32'h8000_0100;
			coh_req_valid_i[0] = 1'b1;

			coh_req_cmd_i[2] = SNOOP_BUSRD;
			coh_req_addr_i[2] = 32'h8000_0200;
			coh_req_valid_i[2] = 1'b1;

			tick(1);

			check_bit("core0_ready_first", coh_req_ready_o[0], 1'b1);
			check_bit("core2_ready_not_first", coh_req_ready_o[2], 1'b0);

			coh_req_valid_i = '0;

			plan_hit_q         = hit_mask;
			plan_dirty_q       = dirty_mask;
			responder_active_init = 4'b1110;

			wait_done_and_check(0, SNOOP_BUSRDX, 32'h8000_0100, 1'b0, 1'b0, 1'b1, 1'b0);
		end
	endtask

	task automatic test_busrd_clean_shared;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] busrd_clean_shared");

			hit_mask   = 4'b0100;
			dirty_mask = 4'b0000;

			issue_request(1, SNOOP_BUSRD, 32'h8000_1000, hit_mask, dirty_mask);
			wait_done_and_check(1, SNOOP_BUSRD, 32'h8000_1000, 1'b1, 1'b0, 1'b1, 1'b0);
		end
	endtask

	task automatic test_busrdx_dirty_owner;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] busrdx_dirty_owner");

			hit_mask   = 4'b1000;
			dirty_mask = 4'b1000;

			issue_request(0, SNOOP_BUSRDX, 32'h8000_2000, hit_mask, dirty_mask);
			wait_done_and_check(0, SNOOP_BUSRDX, 32'h8000_2000, 1'b1, 1'b1, 1'b0, 1'b1);
		end
	endtask

	task automatic test_busupgr_no_mem_read;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] busupgr_no_mem_read");

			hit_mask   = 4'b0101;
			dirty_mask = 4'b0000;

			issue_request(1, SNOOP_BUSUPGR, 32'h8000_3000, hit_mask, dirty_mask);
			wait_done_and_check(1, SNOOP_BUSUPGR, 32'h8000_3000, 1'b1, 1'b0, 1'b0, 1'b0);
		end
	endtask

	task automatic test_random;
		int n;
		int req_core;
		int i;
		snoop_cmd_t rand_cmd;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		logic exp_shared;
		logic exp_dirty;
		logic exp_need_mem;
		logic exp_need_wb;
		begin
			$display("[TEST] random");

			for (n = 0; n < 120; n++) begin
				req_core  = $urandom_range(0, NUM_CORES-1);
				rand_cmd  = snoop_cmd_t'($urandom_range(0, 2));
				hit_mask   = '0;
				dirty_mask = '0;

				for (i = 0; i < NUM_CORES; i++) begin
					if (i != req_core) begin
						hit_mask[i] = $urandom_range(0, 1);
						if (hit_mask[i]) begin
							dirty_mask[i] = $urandom_range(0, 1);
						end
					end
				end

				exp_shared = |hit_mask | |dirty_mask;
				exp_dirty  = |dirty_mask;
				exp_need_wb = exp_dirty;

				if (rand_cmd == SNOOP_BUSUPGR)
					exp_need_mem = 1'b0;
				else
					exp_need_mem = ~exp_dirty;

				issue_request(req_core, rand_cmd, 32'h9000_0000 + n*32, hit_mask, dirty_mask);
				wait_done_and_check(req_core, rand_cmd, 32'h9000_0000 + n*32,
									exp_shared, exp_dirty, exp_need_mem, exp_need_wb);
				tick(1);
			end
		end
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;

		$fsdbDumpfile("tb_coherence_controller.fsdb");
		$fsdbDumpvars(0, tb_coherence_controller);

		reset_dut();
		test_lowest_core_priority();
		test_busrd_clean_shared();
		test_busrdx_dirty_owner();
		test_busupgr_no_mem_read();
		test_random();

		$display("==================================================");
		$display("COHERENCE_CONTROLLER TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cov_inst.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end

endmodule