`timescale 1ns/1ps

module tb_icache;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam int CLK_PERIOD_NS = 10;
  localparam int MEM_WORDS     = 8192;   // enough backing memory words (32-bit)
  localparam int NUM_RANDOM_OPS = 300;

  // --------------------------------------------------------------------------
  // DUT I/O
  // --------------------------------------------------------------------------
  logic         clk_i;
  logic         rst_i;

  logic         req_rd_i;
  logic         req_flush_i;
  logic         req_invalidate_i;
  logic [31:0]  req_pc_i;

  logic         axi_awready_i;
  logic         axi_wready_i;
  logic         axi_bvalid_i;
  logic [1:0]   axi_bresp_i;
  logic [3:0]   axi_bid_i;
  logic         axi_arready_i;
  logic         axi_rvalid_i;
  logic [31:0]  axi_rdata_i;
  logic [1:0]   axi_rresp_i;
  logic [3:0]   axi_rid_i;
  logic         axi_rlast_i;

  logic         req_accept_o;
  logic         req_valid_o;
  logic         req_error_o;
  logic [63:0]  req_inst_o;

  logic         axi_awvalid_o;
  logic [31:0]  axi_awaddr_o;
  logic [3:0]   axi_awid_o;
  logic [7:0]   axi_awlen_o;
  logic [1:0]   axi_awburst_o;
  logic         axi_wvalid_o;
  logic [31:0]  axi_wdata_o;
  logic [3:0]   axi_wstrb_o;
  logic         axi_wlast_o;
  logic         axi_bready_o;
  logic         axi_arvalid_o;
  logic [31:0]  axi_araddr_o;
  logic [3:0]   axi_arid_o;
  logic [7:0]   axi_arlen_o;
  logic [1:0]   axi_arburst_o;
  logic         axi_rready_o;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  icache #(
	.AXI_ID(0)
  ) dut (
	.clk_i            (clk_i),
	.rst_i            (rst_i),
	.req_rd_i         (req_rd_i),
	.req_flush_i      (req_flush_i),
	.req_invalidate_i (req_invalidate_i),
	.req_pc_i         (req_pc_i),

	.axi_awready_i    (axi_awready_i),
	.axi_wready_i     (axi_wready_i),
	.axi_bvalid_i     (axi_bvalid_i),
	.axi_bresp_i      (axi_bresp_i),
	.axi_bid_i        (axi_bid_i),
	.axi_arready_i    (axi_arready_i),
	.axi_rvalid_i     (axi_rvalid_i),
	.axi_rdata_i      (axi_rdata_i),
	.axi_rresp_i      (axi_rresp_i),
	.axi_rid_i        (axi_rid_i),
	.axi_rlast_i      (axi_rlast_i),

	.req_accept_o     (req_accept_o),
	.req_valid_o      (req_valid_o),
	.req_error_o      (req_error_o),
	.req_inst_o       (req_inst_o),

	.axi_awvalid_o    (axi_awvalid_o),
	.axi_awaddr_o     (axi_awaddr_o),
	.axi_awid_o       (axi_awid_o),
	.axi_awlen_o      (axi_awlen_o),
	.axi_awburst_o    (axi_awburst_o),
	.axi_wvalid_o     (axi_wvalid_o),
	.axi_wdata_o      (axi_wdata_o),
	.axi_wstrb_o      (axi_wstrb_o),
	.axi_wlast_o      (axi_wlast_o),
	.axi_bready_o     (axi_bready_o),
	.axi_arvalid_o    (axi_arvalid_o),
	.axi_araddr_o     (axi_araddr_o),
	.axi_arid_o       (axi_arid_o),
	.axi_arlen_o      (axi_arlen_o),
	.axi_arburst_o    (axi_arburst_o),
	.axi_rready_o     (axi_rready_o)
  );

  // --------------------------------------------------------------------------
  // Clock
  // --------------------------------------------------------------------------
  initial begin
	clk_i = 1'b0;
	forever #(CLK_PERIOD_NS/2) clk_i = ~clk_i;
  end

  // --------------------------------------------------------------------------
  // Backing memory model (32-bit words)
  // --------------------------------------------------------------------------
  logic [31:0] mem32 [0:MEM_WORDS-1];

  // Optional error injection per aligned 32-byte line address
  bit inject_err_by_line [bit[31:0]];

  // AXI read channel model state
  logic        ar_pending_q;
  logic [31:0] ar_addr_q;
  logic [7:0]  ar_len_q;
  logic [3:0]  ar_id_q;
  int unsigned rbeat_q;
  int unsigned ar_stall_cycles_q;
  int unsigned r_gap_cycles_q;
  int unsigned beat_idx;
  logic [31:0] beat_addr;
	
  // --------------------------------------------------------------------------
  // Scoreboard / counters
  // --------------------------------------------------------------------------
  int pass_count;
  int fail_count;
  int miss_count;
  int hit_count;
  int refill_count;
  int flush_count;
  int inval_count;
  int err_count;

  logic [31:0] sb_last_pc_q;
  logic        sb_req_pending_q;
  logic [63:0] sb_expected_inst_q;
  logic        sb_expected_error_q;

  // --------------------------------------------------------------------------
  // Coverage support
  // --------------------------------------------------------------------------
  typedef enum int {
	OP_RD_HIT  = 0,
	OP_RD_MISS = 1,
	OP_FLUSH   = 2,
	OP_INVAL   = 3,
	OP_ERRMISS = 4
  } op_e;

  op_e cov_op;
  logic cov_req_accept;
  logic cov_req_valid;
  logic cov_req_error;
  logic [1:0] cov_state;
  logic cov_tag_hit_any;
  logic cov_replace_way;

  // Hierarchical observation for coverage/debug
  always_comb begin
	cov_state       = dut.state_q;
	cov_tag_hit_any = dut.tag_hit_any_w;
	cov_replace_way = dut.replace_way_q;
	cov_req_accept  = req_accept_o;
	cov_req_valid   = req_valid_o;
	cov_req_error   = req_error_o;
  end

  covergroup cg_icache @(posedge clk_i);
	option.per_instance = 1;

	cp_op: coverpoint cov_op {
	  bins rd_hit   = {OP_RD_HIT};
	  bins rd_miss  = {OP_RD_MISS};
	  bins flush    = {OP_FLUSH};
	  bins inval    = {OP_INVAL};
	  bins errmiss  = {OP_ERRMISS};
	}

	cp_state: coverpoint cov_state {
	  bins flush_st    = {0};
	  bins lookup_st   = {1};
	  bins refill_st   = {2};
	  bins relookup_st = {3};
	}

	cp_accept: coverpoint cov_req_accept {
	  bins no  = {0};
	  bins yes = {1};
	}

	cp_valid: coverpoint cov_req_valid {
	  bins no  = {0};
	  bins yes = {1};
	}

	cp_error: coverpoint cov_req_error {
	  bins no  = {0};
	  bins yes = {1};
	}

	cp_hit: coverpoint cov_tag_hit_any {
	  bins miss = {0};
	  bins hit  = {1};
	}

	cp_way: coverpoint cov_replace_way {
	  bins way0 = {0};
	  bins way1 = {1};
	}

	cross_op_state: cross cp_op, cp_state;
	cross_op_hit:   cross cp_op, cp_hit;
	cross_err:      cross cp_op, cp_error;
  endgroup

  cg_icache cg = new();

  // --------------------------------------------------------------------------
  // Helper functions
  // --------------------------------------------------------------------------
  function automatic [31:0] line_align32(input [31:0] addr);
	line_align32 = {addr[31:5], 5'b0};
  endfunction

  function automatic int unsigned mem_idx(input [31:0] byte_addr);
	mem_idx = (byte_addr >> 2) % MEM_WORDS;
  endfunction

  // For a given PC, the cache returns a 64-bit entry selected by addr>>3.
  // Lower 3 address bits are ignored by data RAM.
  function automatic [63:0] expected_inst64(input [31:0] pc);
	logic [31:0] a0, a1;
	begin
	  a0 = {pc[31:3], 3'b000};       // lower word address in 64b chunk
	  a1 = a0 + 32'd4;               // upper word address
	  expected_inst64 = {mem32[mem_idx(a1)], mem32[mem_idx(a0)]};
	end
  endfunction

  // --------------------------------------------------------------------------
  // Simple memory init pattern
  // --------------------------------------------------------------------------
  task automatic init_memory;
	int i;
	begin
	  for (i = 0; i < MEM_WORDS; i++) begin
		mem32[i] = 32'hA5000000 ^ i ^ (i << 8);
	  end
	  inject_err_by_line.delete();
	end
  endtask

  // --------------------------------------------------------------------------
  // Reset + default drive
  // --------------------------------------------------------------------------
  task automatic drive_defaults;
	begin
	  req_rd_i         = 1'b0;
	  req_flush_i      = 1'b0;
	  req_invalidate_i = 1'b0;
	  req_pc_i         = '0;

	  axi_awready_i    = 1'b0;
	  axi_wready_i     = 1'b0;
	  axi_bvalid_i     = 1'b0;
	  axi_bresp_i      = 2'b00;
	  axi_bid_i        = 4'b0;
	end
  endtask

  task automatic reset_dut;
	  int timeout;
	  begin
		drive_defaults();

		rst_i = 1'b1;
		repeat (4) @(posedge clk_i);
		rst_i = 1'b0;

		// Wait until the cache finishes its power-up flush
		timeout = 2000;
		while ((dut.state_q != dut.STATE_LOOKUP) && (timeout > 0)) begin
		  @(posedge clk_i);
		  timeout--;
		end

		if (timeout == 0) begin
		  $error("[%0t] Timeout waiting DUT to exit reset/flush and enter LOOKUP", $time);
		  fail_count = fail_count + 1;
		end
	  end
	endtask

  // --------------------------------------------------------------------------
  // AXI memory model
  // --------------------------------------------------------------------------
  // Behavior:
  // - Accepts AR when DUT raises ARVALID
  // - Can randomly stall ARREADY
  // - Returns burst of 8 beats, 32-bit each
  // - Can inject RRESP error for selected lines
  //
  // This is a simple, single-outstanding-read model.
  // --------------------------------------------------------------------------
  always @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
	  axi_arready_i <= 1'b0;
	  axi_rvalid_i  <= 1'b0;
	  axi_rdata_i   <= '0;
	  axi_rresp_i   <= 2'b00;
	  axi_rid_i     <= '0;
	  axi_rlast_i   <= 1'b0;

	  ar_pending_q      <= 1'b0;
	  ar_addr_q         <= '0;
	  ar_len_q          <= '0;
	  ar_id_q           <= '0;
	  rbeat_q           <= 0;
	  ar_stall_cycles_q <= 0;
	  r_gap_cycles_q    <= 0;
	end
	else begin
	  // Defaults each cycle
	  axi_arready_i <= 1'b0;
	  axi_rvalid_i  <= 1'b0;
	  axi_rdata_i   <= axi_rdata_i;
	  axi_rresp_i   <= 2'b00;
	  axi_rid_i     <= ar_id_q;
	  axi_rlast_i   <= 1'b0;

	  // If no active burst and no pending accepted AR, decide whether to accept AR
	  if (!ar_pending_q && (rbeat_q == 0)) begin
		if (ar_stall_cycles_q != 0) begin
		  ar_stall_cycles_q <= ar_stall_cycles_q - 1;
		end
		else begin
		  // random ARREADY stalls
		  if (axi_arvalid_o && ($urandom_range(0,3) != 0)) begin
			axi_arready_i <= 1'b1;
			ar_pending_q  <= 1'b1;
			ar_addr_q     <= axi_araddr_o;
			ar_len_q      <= axi_arlen_o;
			ar_id_q       <= axi_arid_o;
			rbeat_q       <= axi_arlen_o + 1; // number of beats
			refill_count  <= refill_count + 1;
			// random gap before first R beat
			r_gap_cycles_q <= $urandom_range(0,2);
		  end
		  else if (axi_arvalid_o) begin
			axi_arready_i <= 1'b0;
			ar_stall_cycles_q <= $urandom_range(0,2);
		  end
		end
	  end

	  // Drive R channel for active burst
	  if (ar_pending_q && (rbeat_q != 0)) begin
		if (r_gap_cycles_q != 0) begin
		  r_gap_cycles_q <= r_gap_cycles_q - 1;
		end
		else if (axi_rready_o) begin
		  axi_rvalid_i <= 1'b1;
		  axi_rid_i    <= ar_id_q;

		  // Beat index from 0..7, each beat is 4 bytesד
		  beat_idx  = (ar_len_q + 1) - rbeat_q;
		  beat_addr = ar_addr_q + beat_idx*4;

		  axi_rdata_i <= mem32[mem_idx(beat_addr)];

		  if (inject_err_by_line.exists(line_align32(ar_addr_q))) begin
			axi_rresp_i <= 2'b10; // SLVERR
		  end
		  else begin
			axi_rresp_i <= 2'b00; // OKAY
		  end

		  if (rbeat_q == 1) begin
			axi_rlast_i   <= 1'b1;
			ar_pending_q  <= 1'b0;
			rbeat_q       <= 0;
		  end
		  else begin
			axi_rlast_i   <= 1'b0;
			rbeat_q       <= rbeat_q - 1;
			r_gap_cycles_q <= $urandom_range(0,1);
		  end
		end
	  end
	end
  end

  // --------------------------------------------------------------------------
  // Scoreboard check on req_valid_o
  // --------------------------------------------------------------------------
  always @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
	  sb_req_pending_q    <= 1'b0;
	  sb_last_pc_q        <= '0;
	  sb_expected_inst_q  <= '0;
	  sb_expected_error_q <= 1'b0;
	end
	else begin
	  // Track accepted read requests
	  if (req_rd_i && req_accept_o) begin
		sb_req_pending_q    <= 1'b1;
		sb_last_pc_q        <= req_pc_i;
		sb_expected_inst_q  <= expected_inst64(req_pc_i);
		sb_expected_error_q <= inject_err_by_line.exists(line_align32(req_pc_i));
	  end

	  // When DUT says valid, compare data
	  if (req_valid_o) begin
		if (!sb_req_pending_q) begin
		  $error("[%0t] req_valid_o asserted without tracked pending request", $time);
		  fail_count <= fail_count + 1;
		end
		else begin
		  if (req_inst_o !== sb_expected_inst_q) begin
			$error("[%0t] DATA MISMATCH pc=%08h got=%016h exp=%016h",
				   $time, sb_last_pc_q, req_inst_o, sb_expected_inst_q);
			fail_count <= fail_count + 1;
		  end
		  else begin
			pass_count <= pass_count + 1;
		  end

		  if (req_error_o !== sb_expected_error_q) begin
			$error("[%0t] ERROR FLAG MISMATCH pc=%08h got=%0b exp=%0b",
				   $time, sb_last_pc_q, req_error_o, sb_expected_error_q);
			fail_count <= fail_count + 1;
		  end
		end
		sb_req_pending_q <= 1'b0;
	  end
	end
  end

  // --------------------------------------------------------------------------
  // Debug hit/miss counters
  // --------------------------------------------------------------------------
  always @(posedge clk_i) begin
	if (!rst_i) begin
	  if (req_rd_i && req_accept_o) begin
		// not yet sure if hit or miss that cycle from user perspective,
		// but later we sample current tag compare heuristic
	  end

	  if (dut.state_q == dut.STATE_LOOKUP && dut.lookup_valid_q && !dut.tag_hit_any_w) begin
		miss_count <= miss_count + 1;
	  end

	  if (req_valid_o) begin
		hit_count <= hit_count + 1;
	  end

	  if (req_flush_i && req_accept_o) begin
		flush_count <= flush_count + 1;
	  end

	  if (req_invalidate_i && req_accept_o) begin
		inval_count <= inval_count + 1;
	  end

	  if (axi_rvalid_i && axi_rready_o && (axi_rresp_i != 2'b00)) begin
		err_count <= err_count + 1;
	  end
	end
  end

  // --------------------------------------------------------------------------
  // Utility tasks
  // --------------------------------------------------------------------------
  task automatic wait_n(input int n);
	repeat (n) @(posedge clk_i);
  endtask

  task automatic wait_req_accept;
	begin
	  while (!req_accept_o) @(posedge clk_i);
	end
  endtask

  task automatic issue_read_and_wait_valid(input [31:0] pc, input op_e kind);
	  int timeout;
	  bit accepted;
	  begin
		cov_op    = kind;
		accepted  = 1'b0;

		// Present request and HOLD until DUT accepts it
		req_pc_i <= pc;
		req_rd_i <= 1'b1;

		timeout = 2000;
		while (!accepted && (timeout > 0)) begin
		  @(posedge clk_i);
		  if (req_rd_i && req_accept_o)
			accepted = 1'b1;
		  timeout--;
		end

		req_rd_i <= 1'b0;
		req_pc_i <= '0;

		if (!accepted) begin
		  $error("[%0t] Timeout waiting for req_accept_o for pc=%08h", $time, pc);
		  fail_count = fail_count + 1;
		  return;
		end

		// Now wait for response
		timeout = 1000;
		while (!req_valid_o && (timeout > 0)) begin
		  @(posedge clk_i);
		  timeout--;
		end

		if (timeout == 0) begin
		  $error("[%0t] Timeout waiting for req_valid_o for pc=%08h", $time, pc);
		  fail_count = fail_count + 1;
		end
	  end
	endtask

	task automatic issue_flush;
		int timeout;
		bit accepted;
		begin
		  cov_op   = OP_FLUSH;
		  accepted = 1'b0;

		  req_flush_i <= 1'b1;

		  timeout = 2000;
		  while (!accepted && (timeout > 0)) begin
			@(posedge clk_i);
			if (req_flush_i && req_accept_o)
			  accepted = 1'b1;
			timeout--;
		  end

		  req_flush_i <= 1'b0;

		  if (!accepted) begin
			$error("[%0t] Timeout waiting flush accept", $time);
			fail_count = fail_count + 1;
			return;
		  end

		  timeout = 4000;
		  while ((dut.state_q != dut.STATE_LOOKUP) && (timeout > 0)) begin
			@(posedge clk_i);
			timeout--;
		  end

		  if (timeout == 0) begin
			$error("[%0t] Timeout waiting flush to finish", $time);
			fail_count = fail_count + 1;
		  end
		end
	  endtask

  task automatic issue_invalidate(input [31:0] pc);
	  int timeout;
	  bit accepted;
	  begin
		cov_op   = OP_INVAL;
		accepted = 1'b0;

		req_pc_i         <= pc;
		req_invalidate_i <= 1'b1;

		timeout = 2000;
		while (!accepted && (timeout > 0)) begin
		  @(posedge clk_i);
		  if (req_invalidate_i && req_accept_o)
			accepted = 1'b1;
		  timeout--;
		end

		req_invalidate_i <= 1'b0;
		req_pc_i         <= '0;

		if (!accepted) begin
		  $error("[%0t] Timeout waiting invalidate accept for pc=%08h", $time, pc);
		  fail_count = fail_count + 1;
		  return;
		end

		timeout = 1000;
		while ((dut.state_q != dut.STATE_LOOKUP) && (timeout > 0)) begin
		  @(posedge clk_i);
		  timeout--;
		end

		if (timeout == 0) begin
		  $error("[%0t] Timeout waiting invalidate to finish pc=%08h", $time, pc);
		  fail_count = fail_count + 1;
		end
	  end
	endtask

  // --------------------------------------------------------------------------
  // Directed tests
  // --------------------------------------------------------------------------
  task automatic test_basic_miss_then_hit;
	logic [31:0] pc;
	begin
	  $display("\n[TEST] basic_miss_then_hit");
	  pc = 32'h0000_0040;

	  // First access: miss -> refill -> valid
	  issue_read_and_wait_valid(pc, OP_RD_MISS);

	  // Second access to same PC should be hit
	  issue_read_and_wait_valid(pc, OP_RD_HIT);
	end
  endtask

  task automatic test_two_addresses_same_line;
	logic [31:0] pc0, pc1;
	begin
	  $display("\n[TEST] two_addresses_same_line");
	  pc0 = 32'h0000_0080; // line-aligned
	  pc1 = pc0 + 32'd8;   // same 32B line, different 64b slot

	  issue_read_and_wait_valid(pc0, OP_RD_MISS);
	  issue_read_and_wait_valid(pc1, OP_RD_HIT);
	end
  endtask

  task automatic test_flush;
	logic [31:0] pc;
	begin
	  $display("\n[TEST] flush");
	  pc = 32'h0000_0100;

	  issue_read_and_wait_valid(pc, OP_RD_MISS);
	  issue_read_and_wait_valid(pc, OP_RD_HIT);

	  issue_flush();

	  // after flush, same access should miss/refill again
	  issue_read_and_wait_valid(pc, OP_RD_MISS);
	end
  endtask

  task automatic test_invalidate_single_line;
	logic [31:0] pc_a, pc_b;
	begin
	  $display("\n[TEST] invalidate_single_line");
	  pc_a = 32'h0000_0200;
	  pc_b = 32'h0000_0240; // different line

	  issue_read_and_wait_valid(pc_a, OP_RD_MISS);
	  issue_read_and_wait_valid(pc_b, OP_RD_MISS);

	  issue_read_and_wait_valid(pc_a, OP_RD_HIT);
	  issue_read_and_wait_valid(pc_b, OP_RD_HIT);

	  issue_invalidate(pc_a);

	  // A should miss again, B should remain hit
	  issue_read_and_wait_valid(pc_a, OP_RD_MISS);
	  issue_read_and_wait_valid(pc_b, OP_RD_HIT);
	end
  endtask

  task automatic test_refill_error;
	logic [31:0] pc;
	begin
	  $display("\n[TEST] refill_error");
	  pc = 32'h0000_0300;

	  inject_err_by_line[line_align32(pc)] = 1'b1;
	  issue_read_and_wait_valid(pc, OP_ERRMISS);

	  // remove error and access again after invalidate so line is reloaded cleanly
	  inject_err_by_line.delete(line_align32(pc));
	  issue_invalidate(pc);
	  issue_read_and_wait_valid(pc, OP_RD_MISS);
	end
  endtask

  task automatic test_way_toggle_pressure;
	logic [31:0] pc0, pc1, pc2;
	begin
	  $display("\n[TEST] way_toggle_pressure");
	  // same index [12:5], different tags
	  pc0 = 32'h0000_1000;
	  pc1 = 32'h0000_3000;
	  pc2 = 32'h0000_5000;

	  // These addresses share the same lower index bits if chosen carefully.
	  // We keep them separated by 0x2000 to change tag while preserving [12:5].
	  issue_read_and_wait_valid(pc0, OP_RD_MISS);
	  issue_read_and_wait_valid(pc1, OP_RD_MISS);
	  issue_read_and_wait_valid(pc0, OP_RD_HIT);
	  issue_read_and_wait_valid(pc1, OP_RD_HIT);

	  // Third one likely evicts one of the previous ways depending on toggle
	  issue_read_and_wait_valid(pc2, OP_RD_MISS);

	  // These accesses are legal regardless of replacement result; if evicted they will refill
	  issue_read_and_wait_valid(pc0, OP_RD_MISS);
	  issue_read_and_wait_valid(pc1, OP_RD_MISS);
	end
  endtask

  // --------------------------------------------------------------------------
  // Random traffic
  // --------------------------------------------------------------------------
  task automatic random_tests;
	int i;
	int sel;
	logic [31:0] pc;
	logic [31:0] base_pool [0:15];
	begin
	  $display("\n[TEST] random_tests");

	  // Build a pool with some repeated indices/tags to create hits and conflicts
	  base_pool[0]  = 32'h0000_0000;
	  base_pool[1]  = 32'h0000_0040;
	  base_pool[2]  = 32'h0000_0080;
	  base_pool[3]  = 32'h0000_00C0;
	  base_pool[4]  = 32'h0000_1000;
	  base_pool[5]  = 32'h0000_3000;
	  base_pool[6]  = 32'h0000_5000;
	  base_pool[7]  = 32'h0000_7000;
	  base_pool[8]  = 32'h0000_0200;
	  base_pool[9]  = 32'h0000_0240;
	  base_pool[10] = 32'h0000_0280;
	  base_pool[11] = 32'h0000_02C0;
	  base_pool[12] = 32'h0000_1100;
	  base_pool[13] = 32'h0000_3100;
	  base_pool[14] = 32'h0000_5100;
	  base_pool[15] = 32'h0000_7100;

	  for (i = 0; i < NUM_RANDOM_OPS; i++) begin
		sel = $urandom_range(0,99);

		// Most operations are reads
		if (sel < 75) begin
			pc = base_pool[$urandom_range(0,15)] + ($urandom_range(0,3) * 8);

			if (dut.state_q == dut.STATE_LOOKUP && dut.lookup_valid_q && dut.tag_hit_any_w)
			  cov_op = OP_RD_HIT;
			else
			  cov_op = OP_RD_MISS;

			issue_read_and_wait_valid(pc, cov_op);
		  end
		  else if (sel < 88) begin
			issue_flush();
		  end
		  else begin
			pc = base_pool[$urandom_range(0,15)] + ($urandom_range(0,3) * 8);
			issue_invalidate(pc);
		  end

		// occasional idle cycles
		wait_n($urandom_range(0,3));
	  end
	end
  endtask

  // --------------------------------------------------------------------------
  // Assertions / sanity checks
  // --------------------------------------------------------------------------
  always @(posedge clk_i) begin
	if (!rst_i) begin
	  // I-cache should never drive AXI write channel
	  if (axi_awvalid_o !== 1'b0) begin
		$error("[%0t] axi_awvalid_o should stay 0", $time);
		fail_count <= fail_count + 1;
	  end
	  if (axi_wvalid_o !== 1'b0) begin
		$error("[%0t] axi_wvalid_o should stay 0", $time);
		fail_count <= fail_count + 1;
	  end
	  if (axi_bready_o !== 1'b0) begin
		$error("[%0t] axi_bready_o should stay 0", $time);
		fail_count <= fail_count + 1;
	  end
	end
  end

  // --------------------------------------------------------------------------
  // Main
  // --------------------------------------------------------------------------
  initial begin
	init_memory();
	reset_dut();

	test_basic_miss_then_hit();
	test_two_addresses_same_line();
	test_flush();
	test_invalidate_single_line();
	test_refill_error();
	test_way_toggle_pressure();
	random_tests();

	wait_n(20);

	$display("\n============================================================");
	$display("ICACHE TB SUMMARY");
	$display("  pass_count   = %0d", pass_count);
	$display("  fail_count   = %0d", fail_count);
	$display("  hit_count    = %0d", hit_count);
	$display("  miss_count   = %0d", miss_count);
	$display("  refill_count = %0d", refill_count);
	$display("  flush_count  = %0d", flush_count);
	$display("  inval_count  = %0d", inval_count);
	$display("  err_count    = %0d", err_count);
	$display("  coverage     = %0.2f %%", cg.get_coverage());
	$display("============================================================\n");

	if (fail_count == 0) begin
	  $display("TB PASSED");
	end
	else begin
	  $display("TB FAILED");
	end

	$finish;
  end

endmodule