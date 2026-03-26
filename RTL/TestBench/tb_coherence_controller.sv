`timescale 1ns/1ps

import coherence_pkg::*;

module tb_coherence_controller;

  localparam int NUM_CORES  = 4;
  localparam int CORE_IDX_W = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES);

  // ------------------------------------------------------------
  // DUT signals
  // ------------------------------------------------------------
  logic                              clk_i;
  logic                              rst_i;

  logic [NUM_CORES-1:0]              coh_req_valid_i;
  snoop_cmd_t [NUM_CORES-1:0]        coh_req_cmd_i;
  logic [NUM_CORES-1:0][31:0]        coh_req_addr_i;
  wire  [NUM_CORES-1:0]              coh_req_ready_o;

  logic [NUM_CORES-1:0]              cache_snoop_hit_i;
  logic [NUM_CORES-1:0]              cache_snoop_dirty_i;
  logic [NUM_CORES-1:0]              cache_snoop_ack_i;

  wire  [NUM_CORES-1:0]              snoop_valid_o;
  wire  snoop_cmd_t [NUM_CORES-1:0]  snoop_cmd_o;
  wire  [NUM_CORES-1:0][31:0]        snoop_addr_o;

  wire                               trans_done_o;
  wire  [CORE_IDX_W-1:0]             trans_core_o;
  wire  snoop_cmd_t                  trans_cmd_o;
  wire  [31:0]                       trans_addr_o;
  wire                               trans_shared_o;
  wire                               trans_dirty_o;
  wire                               trans_need_mem_read_o;
  wire                               trans_need_writeback_o;
  wire                               busy_o;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  coherence_controller #(
	.NUM_CORES(NUM_CORES)
  ) dut (
	.clk_i(clk_i),
	.rst_i(rst_i),

	.coh_req_valid_i(coh_req_valid_i),
	.coh_req_cmd_i(coh_req_cmd_i),
	.coh_req_addr_i(coh_req_addr_i),
	.coh_req_ready_o(coh_req_ready_o),

	.cache_snoop_hit_i(cache_snoop_hit_i),
	.cache_snoop_dirty_i(cache_snoop_dirty_i),
	.cache_snoop_ack_i(cache_snoop_ack_i),

	.snoop_valid_o(snoop_valid_o),
	.snoop_cmd_o(snoop_cmd_o),
	.snoop_addr_o(snoop_addr_o),

	.trans_done_o(trans_done_o),
	.trans_core_o(trans_core_o),
	.trans_cmd_o(trans_cmd_o),
	.trans_addr_o(trans_addr_o),
	.trans_shared_o(trans_shared_o),
	.trans_dirty_o(trans_dirty_o),
	.trans_need_mem_read_o(trans_need_mem_read_o),
	.trans_need_writeback_o(trans_need_writeback_o),
	.busy_o(busy_o)
  );

  // ------------------------------------------------------------
  // Scoreboard / counters
  // ------------------------------------------------------------
  integer pass_count;
  integer fail_count;
  integer test_count;

  task automatic pass(input string msg);
	begin
	  pass_count = pass_count + 1;
	  $display("[PASS] %s t=%0t", msg, $time);
	end
  endtask

  task automatic fail(input string msg);
	begin
	  fail_count = fail_count + 1;
	  $display("[FAIL] %s t=%0t", msg, $time);
	end
  endtask

  task automatic check_eq1(input string name, input logic got, input logic exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%0b exp=%0b", name, got, exp));
	  else
		pass($sformatf("%s = %0b", name, got));
	end
  endtask

  task automatic check_eq32(input string name, input logic [31:0] got, input logic [31:0] exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%08x exp=%08x", name, got, exp));
	  else
		pass($sformatf("%s = %08x", name, got));
	end
  endtask

  task automatic check_eq_core(input string name, input logic [CORE_IDX_W-1:0] got, input logic [CORE_IDX_W-1:0] exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%0d exp=%0d", name, got, exp));
	  else
		pass($sformatf("%s = %0d", name, got));
	end
  endtask

  task automatic check_eq_cmd(input string name, input snoop_cmd_t got, input snoop_cmd_t exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%0d exp=%0d", name, got, exp));
	  else
		pass($sformatf("%s = %0d", name, got));
	end
  endtask

  task automatic check_true(input string name, input logic cond);
	begin
	  if (!cond)
		fail(name);
	  else
		pass(name);
	end
  endtask

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  initial begin
	clk_i = 1'b0;
	forever #5 clk_i = ~clk_i;
  end

  // ------------------------------------------------------------
  // Coverage
  // ------------------------------------------------------------
  logic [1:0] cov_cmd;
  logic       cov_any_hit;
  logic       cov_any_dirty;
  logic       cov_need_mem_read;
  logic       cov_need_wb;

  covergroup cg_ctrl @(posedge clk_i);
	cp_cmd: coverpoint cov_cmd {
	  bins busrd   = {SNOOP_BUSRD};
	  bins busrdx  = {SNOOP_BUSRDX};
	  bins busupgr = {SNOOP_BUSUPGR};
	}

	cp_hit: coverpoint cov_any_hit   { bins nohit = {0}; bins hit = {1}; }
	cp_dirty: coverpoint cov_any_dirty { bins clean = {0}; bins dirty = {1}; }
	cp_mem_read: coverpoint cov_need_mem_read { bins no = {0}; bins yes = {1}; }
	cp_wb: coverpoint cov_need_wb { bins no = {0}; bins yes = {1}; }

	x_cmd_resp: cross cp_cmd, cp_hit, cp_dirty {
	  ignore_bins miss_dirty =
		binsof(cp_hit) intersect {0} &&
		binsof(cp_dirty) intersect {1};

	  ignore_bins busupgr_dirty =
		binsof(cp_cmd) intersect {SNOOP_BUSUPGR} &&
		binsof(cp_dirty) intersect {1};
	}
  endgroup

  cg_ctrl cov = new();

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  task automatic clear_inputs;
	integer i;
	begin
	  coh_req_valid_i    = '0;
	  cache_snoop_hit_i  = '0;
	  cache_snoop_dirty_i= '0;
	  cache_snoop_ack_i  = '0;
	  for (i = 0; i < NUM_CORES; i++) begin
		coh_req_cmd_i[i]  = SNOOP_NONE;
		coh_req_addr_i[i] = 32'h0;
	  end
	end
  endtask

  task automatic wait_idle;
	integer timeout;
	begin
	  timeout = 200;
	  while (busy_o && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail("timeout waiting for busy_o deassert");
	end
  endtask

  task automatic wait_done;
	integer timeout;
	begin
	  timeout = 200;
	  while (!trans_done_o && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail("timeout waiting for trans_done_o");
	end
  endtask

  task automatic issue_request(
	input int src,
	input snoop_cmd_t cmd,
	input logic [31:0] addr
  );
	begin
	  @(posedge clk_i);
	  coh_req_valid_i[src] <= 1'b1;
	  coh_req_cmd_i[src]   <= cmd;
	  coh_req_addr_i[src]  <= addr;

	  @(posedge clk_i);
	  if (!coh_req_ready_o[src])
		fail($sformatf("request from core%0d was not accepted in IDLE", src));
	  else
		pass($sformatf("request from core%0d accepted", src));

	  coh_req_valid_i[src] <= 1'b0;
	  coh_req_cmd_i[src]   <= SNOOP_NONE;
	  coh_req_addr_i[src]  <= 32'h0;
	end
  endtask

  task automatic check_broadcast(
	input int src,
	input snoop_cmd_t cmd,
	input logic [31:0] addr
  );
	integer i;
	begin
	  for (i = 0; i < NUM_CORES; i++) begin
		if (i == src) begin
		  check_eq1($sformatf("core%0d snoop_valid masked for source", i), snoop_valid_o[i], 1'b0);
		end
		else begin
		  check_eq1($sformatf("core%0d snoop_valid asserted", i), snoop_valid_o[i], 1'b1);
		  check_eq_cmd($sformatf("core%0d snoop_cmd", i), snoop_cmd_o[i], cmd);
		  check_eq32($sformatf("core%0d snoop_addr", i), snoop_addr_o[i], addr);
		end
	  end
	end
  endtask

  task automatic ack_core(
	input int core,
	input logic hit,
	input logic dirty
  );
	begin
	  @(posedge clk_i);
	  cache_snoop_hit_i[core]   <= hit;
	  cache_snoop_dirty_i[core] <= dirty;
	  cache_snoop_ack_i[core]   <= 1'b1;

	  @(posedge clk_i);
	  cache_snoop_hit_i[core]   <= 1'b0;
	  cache_snoop_dirty_i[core] <= 1'b0;
	  cache_snoop_ack_i[core]   <= 1'b0;
	end
  endtask

  task automatic check_result(
	input int src,
	input snoop_cmd_t cmd,
	input logic [31:0] addr,
	input logic shared,
	input logic dirty,
	input logic need_mem_read,
	input logic need_wb
  );
	begin
	  wait_done();
	  #1;

	  cov_cmd           = cmd;
	  cov_any_hit       = shared;
	  cov_any_dirty     = dirty;
	  cov_need_mem_read = need_mem_read;
	  cov_need_wb       = need_wb;

	  check_eq_core("trans_core_o", trans_core_o, src[CORE_IDX_W-1:0]);
	  check_eq_cmd("trans_cmd_o", trans_cmd_o, cmd);
	  check_eq32("trans_addr_o", trans_addr_o, addr);
	  check_eq1("trans_shared_o", trans_shared_o, shared);
	  check_eq1("trans_dirty_o", trans_dirty_o, dirty);
	  check_eq1("trans_need_mem_read_o", trans_need_mem_read_o, need_mem_read);
	  check_eq1("trans_need_writeback_o", trans_need_writeback_o, need_wb);

	  @(posedge clk_i);
	  check_eq1("trans_done_o pulse clears", trans_done_o, 1'b0);
	  wait_idle();
	end
  endtask

  // ------------------------------------------------------------
  // Tests
  // ------------------------------------------------------------
  task automatic test_reset_idle;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] reset_idle");

	  check_eq1("busy_o after reset", busy_o, 1'b0);
	  check_eq1("trans_done_o after reset", trans_done_o, 1'b0);
	  check_eq1("all coh_req_ready_o after reset", (coh_req_ready_o == '0), 1'b1);
	  check_eq1("all snoop_valid_o after reset", (snoop_valid_o == '0), 1'b1);
	end
  endtask

  task automatic test_busrd_nohit;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrd_nohit");
	  addr = 32'h8000_1000;

	  issue_request(0, SNOOP_BUSRD, addr);
	  @(posedge clk_i);
	  check_eq1("busy_o asserted", busy_o, 1'b1);
	  check_broadcast(0, SNOOP_BUSRD, addr);

	  ack_core(1, 1'b0, 1'b0);
	  ack_core(2, 1'b0, 1'b0);
	  ack_core(3, 1'b0, 1'b0);

	  check_result(0, SNOOP_BUSRD, addr, 1'b0, 1'b0, 1'b1, 1'b0);
	end
  endtask

  task automatic test_busrd_shared_clean;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrd_shared_clean");
	  addr = 32'h8000_2000;

	  issue_request(1, SNOOP_BUSRD, addr);
	  @(posedge clk_i);
	  check_broadcast(1, SNOOP_BUSRD, addr);

	  ack_core(0, 1'b1, 1'b0);
	  ack_core(2, 1'b0, 1'b0);
	  ack_core(3, 1'b0, 1'b0);

	  check_result(1, SNOOP_BUSRD, addr, 1'b1, 1'b0, 1'b1, 1'b0);
	end
  endtask

  task automatic test_busrd_dirty_supplier;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrd_dirty_supplier");
	  addr = 32'h8000_3000;

	  issue_request(2, SNOOP_BUSRD, addr);
	  @(posedge clk_i);
	  check_broadcast(2, SNOOP_BUSRD, addr);

	  ack_core(0, 1'b0, 1'b0);
	  ack_core(1, 1'b1, 1'b1);
	  ack_core(3, 1'b0, 1'b0);

	  check_result(2, SNOOP_BUSRD, addr, 1'b1, 1'b1, 1'b0, 1'b1);
	end
  endtask

  task automatic test_busrdx_clean_hit;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrdx_clean_hit");
	  addr = 32'h8000_4000;

	  issue_request(3, SNOOP_BUSRDX, addr);
	  @(posedge clk_i);
	  check_broadcast(3, SNOOP_BUSRDX, addr);

	  ack_core(0, 1'b1, 1'b0);
	  ack_core(1, 1'b0, 1'b0);
	  ack_core(2, 1'b0, 1'b0);

	  check_result(3, SNOOP_BUSRDX, addr, 1'b1, 1'b0, 1'b1, 1'b0);
	end
  endtask

  task automatic test_busrdx_dirty_hit;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrdx_dirty_hit");
	  addr = 32'h8000_5000;

	  issue_request(0, SNOOP_BUSRDX, addr);
	  @(posedge clk_i);
	  check_broadcast(0, SNOOP_BUSRDX, addr);

	  ack_core(1, 1'b0, 1'b0);
	  ack_core(2, 1'b1, 1'b1);
	  ack_core(3, 1'b0, 1'b0);

	  check_result(0, SNOOP_BUSRDX, addr, 1'b1, 1'b1, 1'b0, 1'b1);
	end
  endtask

  task automatic test_busupgr_shared;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busupgr_shared");
	  addr = 32'h8000_6000;

	  issue_request(1, SNOOP_BUSUPGR, addr);
	  @(posedge clk_i);
	  check_broadcast(1, SNOOP_BUSUPGR, addr);

	  ack_core(0, 1'b1, 1'b0);
	  ack_core(2, 1'b0, 1'b0);
	  ack_core(3, 1'b0, 1'b0);

	  check_result(1, SNOOP_BUSUPGR, addr, 1'b1, 1'b0, 1'b0, 1'b0);
	end
  endtask

  task automatic test_priority_lowest_index;
	logic [31:0] addr0;
	logic [31:0] addr2;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] priority_lowest_index");
	  addr0 = 32'h8000_7000;
	  addr2 = 32'h8000_7004;

	  @(posedge clk_i);
	  coh_req_valid_i[2] <= 1'b1;
	  coh_req_cmd_i[2]   <= SNOOP_BUSRD;
	  coh_req_addr_i[2]  <= addr2;
	  coh_req_valid_i[0] <= 1'b1;
	  coh_req_cmd_i[0]   <= SNOOP_BUSRDX;
	  coh_req_addr_i[0]  <= addr0;

	  @(posedge clk_i);
	  check_eq1("core0 ready first", coh_req_ready_o[0], 1'b1);
	  check_eq1("core2 not ready while core0 wins", coh_req_ready_o[2], 1'b0);

	  coh_req_valid_i[0] <= 1'b0;
	  coh_req_cmd_i[0]   <= SNOOP_NONE;
	  coh_req_addr_i[0]  <= 32'h0;
	  coh_req_valid_i[2] <= 1'b0;
	  coh_req_cmd_i[2]   <= SNOOP_NONE;
	  coh_req_addr_i[2]  <= 32'h0;

	  @(posedge clk_i);
	  check_broadcast(0, SNOOP_BUSRDX, addr0);

	  ack_core(1, 1'b0, 1'b0);
	  ack_core(2, 1'b0, 1'b0);
	  ack_core(3, 1'b0, 1'b0);

	  check_result(0, SNOOP_BUSRDX, addr0, 1'b0, 1'b0, 1'b1, 1'b0);
	end
  endtask

  task automatic test_done_waits_for_all_acks;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] done_waits_for_all_acks");
	  addr = 32'h8000_8000;

	  issue_request(2, SNOOP_BUSRD, addr);
	  @(posedge clk_i);
	  check_broadcast(2, SNOOP_BUSRD, addr);

	  ack_core(0, 1'b0, 1'b0);
	  @(posedge clk_i);
	  check_eq1("trans_done_o not early after first ack", trans_done_o, 1'b0);

	  ack_core(1, 1'b1, 1'b0);
	  @(posedge clk_i);
	  check_eq1("trans_done_o not early after second ack", trans_done_o, 1'b0);

	  ack_core(3, 1'b0, 1'b0);

	  check_result(2, SNOOP_BUSRD, addr, 1'b1, 1'b0, 1'b1, 1'b0);
	end
  endtask

  task automatic test_random;
	int iter;
	int src;
	int hit_core;
	int dirty_core;
	int i;
	snoop_cmd_t cmd;
	logic [31:0] addr;
	logic exp_shared;
	logic exp_dirty;
	logic exp_need_mem_read;
	logic exp_need_wb;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] random");

	  for (iter = 0; iter < 120; iter++) begin
		src       = $urandom_range(0, NUM_CORES-1);
		hit_core  = $urandom_range(0, NUM_CORES);
		dirty_core= $urandom_range(0, NUM_CORES);
		addr      = {16'h8000, $urandom_range(0, 16'h7fff)};
		addr[1:0] = 2'b00;

		case ($urandom_range(0,2))
		  0: cmd = SNOOP_BUSRD;
		  1: cmd = SNOOP_BUSRDX;
		  default: cmd = SNOOP_BUSUPGR;
		endcase

		issue_request(src, cmd, addr);
		@(posedge clk_i);
		check_broadcast(src, cmd, addr);

		exp_shared = 1'b0;
		exp_dirty  = 1'b0;

		for (i = 0; i < NUM_CORES; i++) begin
		  if (i != src) begin
			logic hit_v;
			logic dirty_v;

			hit_v   = (i == hit_core);
			dirty_v = (i == dirty_core) && (cmd != SNOOP_BUSUPGR) && hit_v;

			if (hit_v)   exp_shared = 1'b1;
			if (dirty_v) exp_dirty  = 1'b1;

			ack_core(i, hit_v, dirty_v);
		  end
		end

		if (cmd == SNOOP_BUSUPGR)
		  exp_need_mem_read = 1'b0;
		else
		  exp_need_mem_read = ~exp_dirty;

		exp_need_wb = exp_dirty;

		check_result(src, cmd, addr, exp_shared, exp_dirty, exp_need_mem_read, exp_need_wb);
	  end

	  pass("random completed");
	end
  endtask

  // ------------------------------------------------------------
  // Main
  // ------------------------------------------------------------
  initial begin
	pass_count = 0;
	fail_count = 0;
	test_count = 0;

	clear_inputs();

	rst_i = 1'b1;

	`ifdef FSDB
	  $fsdbDumpfile("tb_coherence_controller.fsdb");
	  $fsdbDumpvars(0, tb_coherence_controller);
	`else
	  $dumpfile("tb_coherence_controller.vcd");
	  $dumpvars(0, tb_coherence_controller);
	`endif

	repeat (6) @(posedge clk_i);
	rst_i = 1'b0;

	@(posedge clk_i);

	test_reset_idle();
	test_busrd_nohit();
	test_busrd_shared_clean();
	test_busrd_dirty_supplier();
	test_busrdx_clean_hit();
	test_busrdx_dirty_hit();
	test_busupgr_shared();
	test_priority_lowest_index();
	test_done_waits_for_all_acks();
	test_random();

	$display("==================================================");
	$display("COHERENCE_CONTROLLER TB SUMMARY");
	$display("  test_count = %0d", test_count);
	$display("  pass_count = %0d", pass_count);
	$display("  fail_count = %0d", fail_count);
	$display("  coverage   = %0.2f %%", cov.get_inst_coverage());
	$display("==================================================");

	if (fail_count == 0)
	  $display("TB PASSED");
	else
	  $display("TB FAILED");

	#50;
	$finish;
  end

endmodule