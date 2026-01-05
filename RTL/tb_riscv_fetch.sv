`timescale 1ns/1ps

//==============================================================
// Self-checking TB for riscv_fetch (two-way superscalar)
// - Directed tests + randomized stress
// - Verifies: reset, PC increment, ID stall, cache accept/valid delays, redirects
//
// IMPORTANT compile note:
// Save as .sv and compile with SystemVerilog enabled (-sv).
//==============================================================
module tb_riscv_fetch;

  // -----------------------------
  // Clock / Reset
  // -----------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk; // 100MHz

  task automatic wait_cycles(input int n);
	int i;
	begin
	  for (i = 0; i < n; i++) @(posedge clk);
	end
  endtask

  task automatic tb_fatal(input string msg);
	begin
	  $display("[%0t] TB_FATAL: %s", $time, msg);
	  $fatal(1);
	end
  endtask

  // -----------------------------
  // Deterministic bundle generator
  // -----------------------------
  function automatic [63:0] make_bundle64(input longint unsigned pc);
	// Generates {inst1, inst0} pattern based on PC (deterministic).
	// We generate 2x32-bit and later truncate to 2*ILEN bits.
	begin
	  make_bundle64 = { (pc[31:0] ^ 32'h2222_0000),
						(pc[31:0] ^ 32'h1111_0000) };
	end
  endfunction

  //==============================================================
  // DUT0 parameters (RV32I-like)
  //==============================================================
  localparam int unsigned XLEN0 = 32;
  localparam int unsigned ILEN0 = 32;
  localparam logic [XLEN0-1:0] RESET_PC0 = 32'h0000_0000;
  localparam int unsigned BUNDLE_BYTES0 = 2 * (ILEN0/8);

  // DUT0 signals
  logic                 fetch_accept0;
  logic                 branch_req0;
  logic [XLEN0-1:0]      branch_pc0;

  logic                 ic_accept0;
  logic                 ic_valid0;
  logic [2*ILEN0-1:0]    ic_bundle0;

  logic                 ic_rd0;
  logic [XLEN0-1:0]      ic_pc0;

  logic                 fetch_valid0;
  logic [XLEN0-1:0]      fetch_pc0;
  logic [2*ILEN0-1:0]    fetch_bundle0;

  //==============================================================
  // Instantiate DUT0
  //==============================================================
  riscv_fetch #(
	.XLEN(XLEN0),
	.ILEN(ILEN0),
	.RESET_PC(RESET_PC0)
  ) dut0 (
	.clk_i(clk),
	.rst_ni(rst_n),

	.fetch_accept_i(fetch_accept0),

	.branch_request_i(branch_req0),
	.branch_pc_i(branch_pc0),

	.icache_accept_i(ic_accept0),
	.icache_valid_i(ic_valid0),
	.icache_bundle_i(ic_bundle0),

	.icache_rd_o(ic_rd0),
	.icache_pc_o(ic_pc0),

	.fetch_valid_o(fetch_valid0),
	.fetch_pc_o(fetch_pc0),
	.fetch_bundle_o(fetch_bundle0)
  );

  //==============================================================
  // Simple Cache Model for DUT0 (FSM)
  //
  // accept_delay = number of cycles to wait AFTER seeing ic_rd0
  //               before pulsing ic_accept0.
  // resp_delay   = number of cycles to wait AFTER accept pulse
  //               before pulsing ic_valid0.
  //
  // Both delays can be 0 (meaning immediate on the next clock edge logic).
  //==============================================================
  typedef enum logic [1:0] {C0_IDLE, C0_WAIT_ACC, C0_WAIT_RESP} cstate0_t;
  cstate0_t c0_state;

  int              c0_acc_cnt;
  int              c0_resp_cnt;
  longint unsigned c0_req_pc;

  int c0_accept_delay_cfg;
  int c0_resp_delay_cfg;

  task automatic cache0_program(input int accept_delay, input int resp_delay);
	begin
	  c0_accept_delay_cfg = accept_delay;
	  c0_resp_delay_cfg   = resp_delay;
	end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
	  if (!rst_n) begin
		ic_accept0 <= 1'b0;
		ic_valid0  <= 1'b0;
		ic_bundle0 <= '0;

		c0_state   <= C0_IDLE;
		c0_acc_cnt <= 0;
		c0_resp_cnt<= 0;
		c0_req_pc  <= 0;
	  end else begin
		// default: 1-cycle pulses
		ic_accept0 <= 1'b0;
		ic_valid0  <= 1'b0;

		// ------------------------------------------------------------
		// FLUSH cache-model transaction on redirect
		// (prevents late/stale responses after branch redirect)
		// ------------------------------------------------------------
		if (branch_req0) begin
		  c0_state    <= C0_IDLE;
		  c0_acc_cnt  <= 0;
		  c0_resp_cnt <= 0;
		  c0_req_pc   <= '0;
		  // ic_bundle0 can stay as-is (don't care) or clear it:
		  // ic_bundle0 <= '0;
		end else begin
		  case (c0_state)
			C0_IDLE: begin
			  if (ic_rd0) begin
				// latch request PC when request is issued
				c0_req_pc  <= ic_pc0;
				c0_acc_cnt <= c0_accept_delay_cfg;
				c0_state   <= C0_WAIT_ACC;
			  end
			end

			C0_WAIT_ACC: begin
			  if (c0_acc_cnt == 0) begin
				ic_accept0 <= 1'b1;
				c0_resp_cnt<= c0_resp_delay_cfg;
				c0_state   <= C0_WAIT_RESP;
			  end else begin
				c0_acc_cnt <= c0_acc_cnt - 1;
			  end
			end

			C0_WAIT_RESP: begin
			  if (c0_resp_cnt == 0) begin
				ic_valid0  <= 1'b1;
				ic_bundle0 <= make_bundle64(c0_req_pc)[2*ILEN0-1:0];
				c0_state   <= C0_IDLE;
			  end else begin
				c0_resp_cnt <= c0_resp_cnt - 1;
			  end
			end

			default: c0_state <= C0_IDLE;
		  endcase
		end
	  end
	end

  //==============================================================
  // Scoreboard helpers
  //==============================================================
  task automatic check_bundle0(input longint unsigned expected_pc);
	logic [2*ILEN0-1:0] expected_bundle;
	begin
	  expected_bundle = make_bundle64(expected_pc)[2*ILEN0-1:0];

	  if (fetch_pc0 !== expected_pc[XLEN0-1:0]) begin
		tb_fatal($sformatf("fetch_pc0 mismatch: expected=0x%08x got=0x%08x",
						   expected_pc[31:0], fetch_pc0));
	  end

	  if (fetch_bundle0 !== expected_bundle) begin
		tb_fatal($sformatf("fetch_bundle0 mismatch: expected=0x%0h got=0x%0h",
						   expected_bundle, fetch_bundle0));
	  end
	end
  endtask
  
  
  
  task automatic wait_fetch_valid_or_timeout(input int max_cycles);
	  int i;
	  begin
		for (i = 0; i < max_cycles; i++) begin
		  if (fetch_valid0 === 1'b1)
			return;
		  @(posedge clk);
		end

		// Timeout diagnostics
		$display("[%0t] TIMEOUT waiting for fetch_valid0", $time);
		$display("  fetch_valid0=%b fetch_accept0=%b", fetch_valid0, fetch_accept0);
		$display("  ic_rd0=%b ic_accept0=%b ic_valid0=%b", ic_rd0, ic_accept0, ic_valid0);
		$display("  ic_pc0=0x%08x fetch_pc0=0x%08x", ic_pc0, fetch_pc0);
		$display("  cache_state=%0d acc_cnt=%0d resp_cnt=%0d",
				 c0_state, c0_acc_cnt, c0_resp_cnt);
		tb_fatal("Timeout: fetch_valid0 never asserted");
	  end
	endtask

  
  //==============================================================
  // reset in order to separate between the tests
  //==============================================================
  task automatic do_reset();
	  begin
		rst_n = 1'b0;
		wait_cycles(3);
		rst_n = 1'b1;
		wait_cycles(1);
	  end
  endtask
  
  
  
  class fetch_txn;
	  // Random knobs per cycle
	  rand bit id_ready;          // drives fetch_accept0
	  rand bit do_redirect;       // drives branch_req0
	  rand logic [31:0] br_pc;    // drives branch_pc0

	  rand int accept_delay;      // cache accept delay
	  rand int resp_delay;        // cache response delay

	  // ----------------------------
	  // Constraints
	  // ----------------------------

	  // ID ready probability ~70%
	  constraint c_id_ready {
		id_ready dist { 1 := 70, 0 := 30 };
	  }

	  // Redirect probability ~5%
	  constraint c_redirect_prob {
		do_redirect dist { 1 := 5, 0 := 95 };
	  }

	  // Branch PC must be aligned to 8 bytes (2x32-bit bundle)
	  constraint c_br_align {
		(br_pc[2:0] == 3'b000);
	  }

	  // Keep branch PC in some reasonable range (optional)
	  constraint c_br_range {
		br_pc inside {[32'h0000_0000 : 32'h0000_7FF8]};
	  }

	  // Cache delays bounded
	  constraint c_cache_delays {
		accept_delay inside {[0:4]};
		resp_delay   inside {[0:8]};
	  }

	endclass



  //==============================================================
  // TEST 0: Reset behavior
  // Mission:
  // - After reset, first delivered bundle must match RESET_PC0
  //==============================================================
  task automatic test_reset_basic();
	begin
	  $display("\n--- TEST: reset_basic ---");
	  do_reset();

	  // Cache: immediate accept, response after 1 cycle
	  cache0_program(0, 1);

	  // Default drives
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;
	  branch_pc0    = '0;

	  // Apply reset
	  rst_n = 1'b0;
	  wait_cycles(3);
	  rst_n = 1'b1;

	  // Wait for first valid and check
	  wait (fetch_valid0 === 1'b1);
	  check_bundle0(RESET_PC0);

	  // consume
	  wait_cycles(1);

	  $display("PASS: reset_basic");
	end
  endtask

  //==============================================================
  // TEST 1: PC increment by bundle size
  // Mission:
  // - Each time ID consumes (valid&&accept), PC advances by BUNDLE_BYTES0 (8 bytes)

  // - Verify that every time ID consumes a bundle (valid && accept),
  //   the fetch stream advances by one bundle:
  //     PC_next = PC_curr + BUNDLE_BYTES0
  //
  // Notes:
  // - We keep fetch_accept0=1 during this test (ID always ready).
  // - We use a timeout instead of a raw wait to avoid hanging forever.
  // - We wait for fetch_valid0 to drop after consume so we won't re-check
  //   the same buffered bundle again.
  //==============================================================
  task automatic test_pc_increment();
	longint unsigned pc_exp;
	int k;
	bit v_pre;
	begin
	  $display("\n--- TEST: pc_increment ---");

	  // Make this test independent from previous tests
	  do_reset();

	  // Cache behavior: immediate accept, response after 1 cycle
	  cache0_program(0, 1);

	  // ID always ready (so consume should happen whenever valid is asserted)
	  fetch_accept0 = 1'b1;

	  // No redirects in this test
	  branch_req0   = 1'b0;
	  branch_pc0    = '0;

	  // Expected stream starts at RESET_PC0
	  pc_exp = RESET_PC0;

	  for (k = 0; k < 6; k++) begin
		// 1) Wait until DUT presents a valid bundle (with timeout)
		wait_fetch_valid_or_timeout(200);

		// 2) Check current bundle matches expected PC
		check_bundle0(pc_exp);

		// 3) Consume occurs on the clock edge when (valid && accept)
		//    Sample valid BEFORE the posedge (because valid may drop right after the edge)
		v_pre = fetch_valid0;
		@(posedge clk);

		if (!(v_pre && fetch_accept0)) begin
		  $display("DEBUG: v_pre=%b accept=%b valid_after=%b pc_exp=0x%08x fetch_pc0=0x%08x",
				   v_pre, fetch_accept0, fetch_valid0, pc_exp[31:0], fetch_pc0);
		  tb_fatal("Expected consume (valid&&accept) did not happen on this cycle");
		end

		// 4) IMPORTANT: wait until the old buffered value is gone,
		//    otherwise next loop may re-check the same bundle.
		wait (fetch_valid0 === 1'b0);

		// 5) Now advance expected PC
		pc_exp = pc_exp + BUNDLE_BYTES0;
	  end

	  $display("PASS: pc_increment");
	end
  endtask



  //==============================================================
  // TEST 2: ID stall holds buffer stable
  // Mission:
  // - When fetch_valid=1 but fetch_accept=0, outputs stay stable
  // - No new cache requests should be issued while buffer full
  //==============================================================
  task automatic test_id_stall_buffer_hold();
	longint unsigned hold_pc;
	logic [2*ILEN0-1:0] hold_bundle;
	begin
	  $display("\n--- TEST: id_stall_buffer_hold ---");
	  do_reset();

	  cache0_program(0, 1);
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;

	  // Wait for a valid bundle and capture it
	  wait (fetch_valid0 === 1'b1);
	  hold_pc     = fetch_pc0;
	  hold_bundle = fetch_bundle0;

	  // Stall ID
	  fetch_accept0 = 1'b0;
	  wait_cycles(5);

	  if (fetch_valid0 !== 1'b1) tb_fatal("fetch_valid0 dropped during ID stall");
	  if (fetch_pc0    !== hold_pc[XLEN0-1:0]) tb_fatal("fetch_pc0 changed during ID stall");
	  if (fetch_bundle0 !== hold_bundle) tb_fatal("fetch_bundle0 changed during ID stall");

	  // While buffer full, design should not issue new request
	  if (ic_rd0 === 1'b1) tb_fatal("ic_rd0 asserted while buffer full (unexpected)");

	  // Resume and consume
	  fetch_accept0 = 1'b1;
	  wait_cycles(1);

	  $display("PASS: id_stall_buffer_hold");
	end
  endtask

  //==============================================================
  // TEST 3: Cache accept latency keeps icache_pc stable
  // Mission:
  // - While waiting for icache_accept, icache_pc_o must remain stable
  //==============================================================
  task automatic test_cache_accept_latency_pc_stable();
	longint unsigned req_pc;
	int i;
	begin
	  $display("\n--- TEST: cache_accept_latency_pc_stable ---");
	  do_reset();

	  cache0_program(4, 2);
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;

	  // Wait for request pulse and capture request PC
	  wait (ic_rd0 === 1'b1);
	  req_pc = ic_pc0;

	  // For several cycles before accept, pc output should remain stable
	  for (i = 0; i < 5; i++) begin
		@(posedge clk);
		if (c0_state == C0_WAIT_ACC) begin
		  if (ic_pc0 !== req_pc[XLEN0-1:0]) begin
			tb_fatal($sformatf("ic_pc0 changed while pending accept: expected=0x%08x got=0x%08x",
							   req_pc[31:0], ic_pc0));
		  end
		end
	  end

	  // Eventually fetch_valid should assert with the requested PC bundle
	  wait (fetch_valid0 === 1'b1);
	  check_bundle0(req_pc);

	  // consume
	  wait_cycles(1);

	  $display("PASS: cache_accept_latency_pc_stable");
	end
  endtask

  //==============================================================
  // TEST 4: Cache response latency (fetch_valid stays low until ic_valid)
  // Mission:
  // - Even after accept, until response arrives, fetch_valid must stay 0
  //==============================================================
  task automatic test_cache_response_latency();
	longint unsigned req_pc;
	int i;
	begin
	  $display("\n--- TEST: cache_response_latency ---");
	  do_reset();

	  cache0_program(0, 6);
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;

	  wait (ic_rd0 === 1'b1);
	  req_pc = ic_pc0;

	  // During response delay, buffer must still be empty => fetch_valid=0
	  for (i = 0; i < 5; i++) begin
		@(posedge clk);
		if (fetch_valid0 === 1'b1) tb_fatal("fetch_valid0 asserted before ic_valid0");
	  end

	  wait (fetch_valid0 === 1'b1);
	  check_bundle0(req_pc);

	  wait_cycles(1);

	  $display("PASS: cache_response_latency");
	end
  endtask

  //==============================================================
  // TEST 5: Redirect while request pending (before accept)
  // Mission:
  // - Redirect must flush pending request and restart at branch_pc
  //==============================================================
  task automatic test_redirect_while_pending_before_accept();
	longint unsigned target_pc;
	begin
	  $display("\n--- TEST: redirect_while_pending_before_accept ---");
	  do_reset();

	  cache0_program(6, 2);
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;

	  // Wait for request to be issued
	  wait (ic_rd0 === 1'b1);

	  // Redirect before accept occurs
	  wait_cycles(2);
	  target_pc  = 32'h0000_2000;

	  branch_pc0 = target_pc[XLEN0-1:0];
	  branch_req0 = 1'b1;
	  wait_cycles(1);
	  branch_req0 = 1'b0;

	  // Speed up after redirect
	  cache0_program(0, 2);

	  wait (fetch_valid0 === 1'b1);
	  check_bundle0(target_pc);

	  wait_cycles(1);

	  $display("PASS: redirect_while_pending_before_accept");
	end
  endtask

  //==============================================================
  // TEST 6: Redirect after accept but before valid
  // Mission:
  // - Redirect should discard inflight response and fetch from branch_pc
  //==============================================================
  task automatic test_redirect_after_accept_before_valid();
	longint unsigned target_pc;
	begin
	  $display("\n--- TEST: redirect_after_accept_before_valid ---");
	  do_reset();

	  cache0_program(0, 8); // accept quickly, response late
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;

	  wait (ic_rd0 === 1'b1);
	  wait_cycles(2); // we're now in response wait window

	  target_pc = 32'h0000_3000;
	  branch_pc0 = target_pc[XLEN0-1:0];
	  branch_req0 = 1'b1;
	  wait_cycles(1);
	  branch_req0 = 1'b0;

	  cache0_program(0, 2);

	  wait (fetch_valid0 === 1'b1);
	  check_bundle0(target_pc);

	  wait_cycles(1);

	  $display("PASS: redirect_after_accept_before_valid");
	end
  endtask

  //==============================================================
  // TEST 7: Redirect while buffer full (ID stalled)
  // Mission:
  // - If buffer holds a bundle and ID stalls, redirect flushes buffer
  //==============================================================
  task automatic test_redirect_while_buffer_full();
	longint unsigned target_pc;
	begin
	  $display("\n--- TEST: redirect_while_buffer_full ---");
	  do_reset();

	  cache0_program(0, 1);
	  fetch_accept0 = 1'b1;
	  branch_req0   = 1'b0;

	  // Wait for valid
	  wait (fetch_valid0 === 1'b1);

	  // Stall ID to keep buffer full
	  fetch_accept0 = 1'b0;
	  wait_cycles(2);

	  target_pc = 32'h0000_4000;
	  branch_pc0 = target_pc[XLEN0-1:0];
	  branch_req0 = 1'b1;
	  wait_cycles(1);
	  branch_req0 = 1'b0;

	  cache0_program(0, 2);

	  wait (fetch_valid0 === 1'b1);
	  check_bundle0(target_pc);

	  // Let ID consume
	  fetch_accept0 = 1'b1;
	  wait_cycles(1);

	  $display("PASS: redirect_while_buffer_full");
	end
  endtask

  //==============================================================
  // TEST 8: Random stress
  // Mission:
  // - Random stalls, random cache delays, occasional redirects
  // - Check invariants that must ALWAYS hold, without trying to predict
  //   the exact PC stream (which requires a full reference model).
  //
  // Invariants checked:
  // 1) If fetch_valid0=1 -> fetch_bundle0 must match make_bundle(fetch_pc0)
  // 2) If fetch_valid0=1 && fetch_accept0=0 -> fetch_pc0 and fetch_bundle0 stable
  // 3) fetch_pc0 may change only on (consume) or right after a redirect flush
  //==============================================================
  task automatic test_random_stress();
	int i;
	int ad, rd;
	bit id_ready;
	bit do_redirect;
	longint unsigned tpc;

	// Previous-cycle sampled outputs for stability checks
	logic [XLEN0-1:0]    pc_prev;
	logic [2*ILEN0-1:0]  bundle_prev;
	bit                 valid_prev;

	// Pre-edge handshake samples
	bit v_pre, a_pre;

	begin
	  $display("\n--- TEST: random_stress ---");

	  do_reset();

	  // init prev
	  pc_prev     = '0;
	  bundle_prev = '0;
	  valid_prev  = 1'b0;

	  branch_req0   = 1'b0;
	  branch_pc0    = '0;
	  fetch_accept0 = 1'b1;

	  for (i = 0; i < 1000; i++) begin
		// Random cache delays
		ad = $urandom_range(0, 4);
		rd = $urandom_range(0, 6);
		cache0_program(ad, rd);

		// Random ID readiness (~70%)
		id_ready = ($urandom_range(0, 9) < 7);
		fetch_accept0 = id_ready;

		// Random redirect (~5%)
		do_redirect = ($urandom_range(0, 99) < 5);
		if (do_redirect) begin
		  tpc = {16'h0000, $urandom_range(0, 16'h7FFF)};
		  tpc = tpc & 32'hFFFF_FFF8; // align to bundle (8 bytes)
		  branch_pc0  = tpc[XLEN0-1:0];
		  branch_req0 = 1'b1;
		end else begin
		  branch_req0 = 1'b0;
		end

		// Sample pre-edge (consume happens at posedge based on these)
		v_pre = fetch_valid0;
		a_pre = fetch_accept0;

		@(posedge clk);

		// one-cycle pulse
		branch_req0 = 1'b0;

		// --------------------------------------------------------
		// Invariant #1: If valid, bundle must match fetch_pc0
		// --------------------------------------------------------
		if (fetch_valid0) begin
		  logic [2*ILEN0-1:0] exp_bundle;
		  exp_bundle = make_bundle64(fetch_pc0)[2*ILEN0-1:0];
		  if (fetch_bundle0 !== exp_bundle) begin
			$display("DBG i=%0d fetch_pc=%h exp_bundle=%h got_bundle=%h",
					 i, fetch_pc0, exp_bundle, fetch_bundle0);
			tb_fatal("Invariant fail: bundle does not match fetch_pc");
		  end
		end

		// --------------------------------------------------------
		// Invariant #2: If stalled while valid, outputs must be stable
		// --------------------------------------------------------
		if (valid_prev && (fetch_accept0 == 1'b0)) begin
		  // If it was valid previously and ID is stalling now, the DUT must hold
		  // Invariant #2: If stalled while valid, outputs must be stable
			// EXCEPT when a redirect happens (redirect flush is allowed to change outputs)
			if (valid_prev && (fetch_accept0 == 1'b0) && !do_redirect) begin
			  if (fetch_pc0 !== pc_prev) begin
				$display("DBG i=%0d pc_prev=%h pc_now=%h redirect=%b", i, pc_prev, fetch_pc0, do_redirect);
				tb_fatal("Invariant fail: fetch_pc changed during stall (no redirect)");
			  end
			  if (fetch_bundle0 !== bundle_prev) begin
				$display("DBG i=%0d bundle_prev=%h bundle_now=%h redirect=%b", i, bundle_prev, fetch_bundle0, do_redirect);
				tb_fatal("Invariant fail: fetch_bundle changed during stall (no redirect)");
			  end
			end

		end

		// --------------------------------------------------------
		// Invariant #3 (soft): fetch_pc changes should correlate with consume/redirect
		// We don't fully enforce exact PC value here, only that "random jumps"
		// don't happen without a reason.
		// --------------------------------------------------------
		if (valid_prev && (fetch_pc0 !== pc_prev)) begin
		  // fetch_pc changed while it was previously valid.
		  // This is allowed only if last cycle had consume (v_pre&&a_pre) OR redirect happened.
		  if (!(v_pre && a_pre) && !do_redirect) begin
			$display("DBG i=%0d pc_prev=%h pc_now=%h v_pre=%b a_pre=%b redirect=%b",
					 i, pc_prev, fetch_pc0, v_pre, a_pre, do_redirect);
			tb_fatal("Invariant fail: fetch_pc changed without consume or redirect");
		  end
		end

		// Update prev samples for next iteration
		valid_prev  = fetch_valid0;
		pc_prev     = fetch_pc0;
		bundle_prev = fetch_bundle0;
	  end

	  $display("PASS: random_stress");
	end
  endtask

  task automatic test_constrained_random();
	  fetch_txn t;
	  int i;

	  // samples for invariants
	  logic [XLEN0-1:0]   pc_prev;
	  logic [2*ILEN0-1:0] bundle_prev;
	  bit valid_prev;

	  bit br_pre;

	  begin
		$display("\n--- TEST: constrained_random ---");

		do_reset();

		t = new();

		// init
		fetch_accept0 = 1'b1;
		branch_req0   = 1'b0;
		branch_pc0    = '0;

		pc_prev     = '0;
		bundle_prev = '0;
		valid_prev  = 1'b0;

		for (i = 0; i < 2000; i++) begin

		  // Randomize a new "cycle plan"
		  if (!t.randomize())
			tb_fatal("randomize() failed");

		  // Only update cache delays when cache is idle (realistic constraint)
		  if (c0_state == C0_IDLE) begin
			cache0_program(t.accept_delay, t.resp_delay);
		  end

		  // Drive ID ready
		  fetch_accept0 = t.id_ready;

		  // Drive redirect (1-cycle pulse)
		  if (t.do_redirect) begin
			branch_pc0  = t.br_pc[XLEN0-1:0];
			branch_req0 = 1'b1;
		  end else begin
			branch_req0 = 1'b0;
		  end

		  // Sample redirect pre-edge for invariants
		  br_pre = branch_req0;

		  @(posedge clk);

		  // clear pulse
		  branch_req0 = 1'b0;

		  // -----------------------------
		  // Invariant checks (recommended)
		  // -----------------------------

		  // (1) If valid, bundle must match fetch_pc
		  if (fetch_valid0) begin
			logic [2*ILEN0-1:0] exp_bundle;
			exp_bundle = make_bundle64(fetch_pc0)[2*ILEN0-1:0];
			if (fetch_bundle0 !== exp_bundle) begin
			  $display("DBG i=%0d fetch_pc=%h exp=%h got=%h",
					   i, fetch_pc0, exp_bundle, fetch_bundle0);
			  tb_fatal("Invariant fail: bundle != make_bundle(fetch_pc)");
			end
		  end

		  // (2) If stalled (accept=0) and no redirect, hold outputs stable
		  if (valid_prev && (fetch_accept0 == 1'b0) && !br_pre) begin
			if (fetch_pc0 !== pc_prev)
			  tb_fatal("Invariant fail: fetch_pc changed during stall (no redirect)");
			if (fetch_bundle0 !== bundle_prev)
			  tb_fatal("Invariant fail: fetch_bundle changed during stall (no redirect)");
		  end

		  // Update prev samples
		  valid_prev  = fetch_valid0;
		  pc_prev     = fetch_pc0;
		  bundle_prev = fetch_bundle0;
		end

		$display("PASS: constrained_random");
	  end
	endtask


  //==============================================================
  // TB MAIN
  //==============================================================
  initial begin
	// Safe defaults
	rst_n = 1'b1;

	fetch_accept0 = 1'b0;
	branch_req0   = 1'b0;
	branch_pc0    = '0;

	// default cache configuration
	c0_accept_delay_cfg = 0;
	c0_resp_delay_cfg   = 1;

	// Run tests
	test_reset_basic();
	test_pc_increment();
	test_id_stall_buffer_hold();
	test_cache_accept_latency_pc_stable();
	test_cache_response_latency();
	test_redirect_while_pending_before_accept();
	test_redirect_after_accept_before_valid();
	test_redirect_while_buffer_full();
	test_random_stress();
	test_constrained_random();

	$display("\nALL TESTS PASSED ✅");
	$finish;
  end

endmodule
