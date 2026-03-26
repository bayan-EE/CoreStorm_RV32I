`timescale 1ns/1ps


import coherence_pkg::*;

module tb_snoop_bus;

	localparam int NUM_CORES  = 4;
	localparam int CORE_IDX_W = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES);

	logic                              clk;
	logic                              rst;

	logic                              start_i;
	logic [CORE_IDX_W-1:0]             source_core_i;
	snoop_cmd_t                        cmd_i;
	logic [31:0]                       addr_i;

	logic [NUM_CORES-1:0]              cache_snoop_hit_i;
	logic [NUM_CORES-1:0]              cache_snoop_dirty_i;
	logic [NUM_CORES-1:0]              cache_snoop_ack_i;

	logic [NUM_CORES-1:0]              snoop_valid_o;
	snoop_cmd_t [NUM_CORES-1:0]        snoop_cmd_o;
	logic [NUM_CORES-1:0][31:0]        snoop_addr_o;

	logic                              busy_o;
	logic                              done_o;
	logic                              any_hit_o;
	logic                              any_dirty_o;
	logic [NUM_CORES-1:0]              ack_seen_o;

	int pass_count;
	int fail_count;

	// These are controlled ONLY by tasks/initial
	logic [NUM_CORES-1:0]      plan_hit_q;
	logic [NUM_CORES-1:0]      plan_dirty_q;

	// Written by tasks/initial only
	logic [NUM_CORES-1:0][3:0] plan_delay_init;
	logic [NUM_CORES-1:0]      responder_active_init;

	// Written by always_ff only
	logic [NUM_CORES-1:0][3:0] plan_delay_q;
	logic [NUM_CORES-1:0]      responder_active_q;

	int cov_source;
	int cov_cmd;
	int cov_any_hit;
	int cov_any_dirty;
	int cov_num_targets;

	covergroup cg_snoop_bus;
		option.per_instance = 1;

		cp_source : coverpoint cov_source {
			bins c0 = {0};
			bins c1 = {1};
			bins c2 = {2};
			bins c3 = {3};
		}

		cp_cmd : coverpoint cov_cmd {
			bins busrd   = {0};
			bins busrdx  = {1};
			bins busupgr = {2};
		}

		cp_any_hit : coverpoint cov_any_hit {
			bins no  = {0};
			bins yes = {1};
		}

		cp_any_dirty : coverpoint cov_any_dirty {
			bins no  = {0};
			bins yes = {1};
		}

		cp_num_targets : coverpoint cov_num_targets {
			bins three = {3};
		}

		x_cmd_dirty : cross cp_cmd, cp_any_dirty;
		x_source_hit : cross cp_source, cp_any_hit;
	endgroup

	cg_snoop_bus cov_inst = new();

	snoop_bus #(
		.NUM_CORES(NUM_CORES)
	) dut (
		.clk_i               (clk),
		.rst_i               (rst),
		.start_i             (start_i),
		.source_core_i       (source_core_i),
		.cmd_i               (cmd_i),
		.addr_i              (addr_i),
		.cache_snoop_hit_i   (cache_snoop_hit_i),
		.cache_snoop_dirty_i (cache_snoop_dirty_i),
		.cache_snoop_ack_i   (cache_snoop_ack_i),
		.snoop_valid_o       (snoop_valid_o),
		.snoop_cmd_o         (snoop_cmd_o),
		.snoop_addr_o        (snoop_addr_o),
		.busy_o              (busy_o),
		.done_o              (done_o),
		.any_hit_o           (any_hit_o),
		.any_dirty_o         (any_dirty_o),
		.ack_seen_o          (ack_seen_o)
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

	task automatic drive_plan(
		input logic [CORE_IDX_W-1:0] src,
		input snoop_cmd_t            cmd,
		input logic [31:0]           addr,
		input logic [NUM_CORES-1:0]  hit_mask,
		input logic [NUM_CORES-1:0]  dirty_mask
	);
		int i;
		begin
			for (i = 0; i < NUM_CORES; i++) begin
				plan_hit_q[i]            = hit_mask[i];
				plan_dirty_q[i]          = dirty_mask[i];
				responder_active_init[i] = (i != src);
				plan_delay_init[i]       = (i != src) ? $urandom_range(0, 3) : 4'd0;
			end

			start_i       = 1'b1;
			source_core_i = src;
			cmd_i         = cmd;
			addr_i        = addr;
			tick(1);
			start_i       = 1'b0;
		end
	endtask

	// Here we only drive DUT-facing signals.
	// plan_* and responder_active_q are modified in this block,
	// but nowhere else at the same time except tasks between cycles.
	always_ff @(posedge clk) begin : proc_cache_responders
		int i;
		if (rst) begin
			cache_snoop_hit_i   <= '0;
			cache_snoop_dirty_i <= '0;
			cache_snoop_ack_i   <= '0;

			plan_delay_q        <= '0;
			responder_active_q  <= '0;
		end
		else begin
			cache_snoop_hit_i   <= '0;
			cache_snoop_dirty_i <= '0;
			cache_snoop_ack_i   <= '0;

			if (start_i) begin
				plan_delay_q        <= plan_delay_init;
				responder_active_q  <= responder_active_init;
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
		input logic [NUM_CORES-1:0]   exp_hit_mask,
		input logic [NUM_CORES-1:0]   exp_dirty_mask,
		input logic [CORE_IDX_W-1:0]  src,
		input snoop_cmd_t             exp_cmd
	);
		int timeout;
		logic exp_any_hit;
		logic exp_any_dirty;
		int i;
		begin
			timeout = 0;
			while (!done_o && timeout < 100) begin
				tick(1);
				timeout++;
			end

			if (!done_o) begin
				$display("[FAIL] timeout waiting for snoop done t=%0t", $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			exp_any_hit   = 1'b0;
			exp_any_dirty = 1'b0;
			for (i = 0; i < NUM_CORES; i++) begin
				if (i != src) begin
					exp_any_hit   |= exp_hit_mask[i];
					exp_any_dirty |= exp_dirty_mask[i];
				end
			end

			check_bit("any_hit_o",   any_hit_o,   exp_any_hit);
			check_bit("any_dirty_o", any_dirty_o, exp_any_dirty);

			for (i = 0; i < NUM_CORES; i++) begin
				if (i == src) begin
					check_bit($sformatf("source_excluded_valid_core%0d", i), snoop_valid_o[i], 1'b0);
				end
			end

			cov_source      = src;
			cov_cmd         = exp_cmd;
			cov_any_hit     = exp_any_hit;
			cov_any_dirty   = exp_any_dirty;
			cov_num_targets = NUM_CORES - 1;
			cov_inst.sample();
		end
	endtask

	task automatic reset_dut;
		begin
			rst                = 1'b1;
			start_i            = 1'b0;
			source_core_i      = '0;
			cmd_i              = SNOOP_NONE;
			addr_i             = 32'h0;
			plan_hit_q         = '0;
			plan_dirty_q       = '0;
			plan_delay_init       = '0;
			responder_active_init = '0;
			tick(4);
			rst = 1'b0;
			tick(2);
		end
	endtask

	task automatic test_no_hit;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] no_hit");
			hit_mask   = '0;
			dirty_mask = '0;
			drive_plan(2, SNOOP_BUSRD, 32'h8000_1000, hit_mask, dirty_mask);
			wait_done_and_check(hit_mask, dirty_mask, 2, SNOOP_BUSRD);
		end
	endtask

	task automatic test_clean_shared_hit;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] clean_shared_hit");
			hit_mask   = 4'b0010;
			dirty_mask = 4'b0000;
			drive_plan(0, SNOOP_BUSRD, 32'h8000_2000, hit_mask, dirty_mask);
			wait_done_and_check(hit_mask, dirty_mask, 0, SNOOP_BUSRD);
		end
	endtask

	task automatic test_dirty_owner;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		begin
			$display("[TEST] dirty_owner");
			hit_mask   = 4'b0100;
			dirty_mask = 4'b0100;
			drive_plan(1, SNOOP_BUSRDX, 32'h8000_3000, hit_mask, dirty_mask);
			wait_done_and_check(hit_mask, dirty_mask, 1, SNOOP_BUSRDX);
		end
	endtask

	task automatic test_random;
		int n;
		int src;
		int i;
		logic [NUM_CORES-1:0] hit_mask;
		logic [NUM_CORES-1:0] dirty_mask;
		snoop_cmd_t rand_cmd;
		begin
			$display("[TEST] random");
			for (n = 0; n < 100; n++) begin
				src      = $urandom_range(0, NUM_CORES-1);
				rand_cmd = snoop_cmd_t'($urandom_range(0, 2));
				hit_mask   = '0;
				dirty_mask = '0;

				for (i = 0; i < NUM_CORES; i++) begin
					if (i != src) begin
						hit_mask[i] = $urandom_range(0, 1);
						dirty_mask[i] = hit_mask[i] ? $urandom_range(0, 1) : 1'b0;
					end
				end

				drive_plan(src[CORE_IDX_W-1:0], rand_cmd, 32'h8000_0000 + n*32, hit_mask, dirty_mask);
				wait_done_and_check(hit_mask, dirty_mask, src[CORE_IDX_W-1:0], rand_cmd);
				tick(1);
			end
		end
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;

		$fsdbDumpfile("tb_snoop_bus.fsdb");
		$fsdbDumpvars(0, tb_snoop_bus);

		reset_dut();
		test_no_hit();
		test_clean_shared_hit();
		test_dirty_owner();
		test_random();

		$display("==================================================");
		$display("SNOOP_BUS TB SUMMARY");
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