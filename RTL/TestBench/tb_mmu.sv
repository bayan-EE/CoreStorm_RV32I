`timescale 1ns/1ps

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/data.cc/data/a/home/cc/students/enginer/yazanatamna/corestorm_ref/corestorm_ref_2/riscv_defs.sv"

module tb_lsu;
  // ------------------------------------------------------------
  // Clock / Reset
  // ------------------------------------------------------------
  logic clk_i;
  logic rst_i;

  // ------------------------------------------------------------
  // Privilege / control
  // ------------------------------------------------------------
  logic [1:0]  priv_d_i;
  logic        sum_i;
  logic        mxr_i;
  logic        flush_i;
  logic [31:0] satp_i;

  // ------------------------------------------------------------
  // FETCH INPUT
  // ------------------------------------------------------------
  logic        fetch_in_rd_i;
  logic        fetch_in_flush_i;
  logic        fetch_in_invalidate_i;
  logic [31:0] fetch_in_pc_i;
  logic [1:0]  fetch_in_priv_i;

  // ------------------------------------------------------------
  // FETCH MEMORY RESPONSE
  // ------------------------------------------------------------
  logic        fetch_out_accept_i;
  logic        fetch_out_valid_i;
  logic        fetch_out_error_i;
  logic [63:0] fetch_out_inst_i;

  // ------------------------------------------------------------
  // LSU INPUT
  // ------------------------------------------------------------
  logic [31:0] lsu_in_addr_i;
  logic [31:0] lsu_in_data_wr_i;
  logic        lsu_in_rd_i;
  logic [3:0]  lsu_in_wr_i;
  logic        lsu_in_cacheable_i;
  logic [10:0] lsu_in_req_tag_i;
  logic        lsu_in_invalidate_i;
  logic        lsu_in_writeback_i;
  logic        lsu_in_flush_i;

  // ------------------------------------------------------------
  // LSU RESPONSE FROM MEMORY
  // ------------------------------------------------------------
  logic [31:0] lsu_out_data_rd_i;
  logic        lsu_out_accept_i;
  logic        lsu_out_ack_i;
  logic        lsu_out_error_i;
  logic [10:0] lsu_out_resp_tag_i;

  // ------------------------------------------------------------
  // FETCH RETURN
  // ------------------------------------------------------------
  logic        fetch_in_accept_o;
  logic        fetch_in_valid_o;
  logic        fetch_in_error_o;
  logic [63:0] fetch_in_inst_o;

  logic        fetch_out_rd_o;
  logic        fetch_out_flush_o;
  logic        fetch_out_invalidate_o;
  logic [31:0] fetch_out_pc_o;

  logic        fetch_in_fault_o;

  // ------------------------------------------------------------
  // LSU RETURN
  // ------------------------------------------------------------
  logic [31:0] lsu_in_data_rd_o;
  logic        lsu_in_accept_o;
  logic        lsu_in_ack_o;
  logic        lsu_in_error_o;
  logic [10:0] lsu_in_resp_tag_o;

  logic [31:0] lsu_out_addr_o;
  logic [31:0] lsu_out_data_wr_o;
  logic        lsu_out_rd_o;
  logic [3:0]  lsu_out_wr_o;
  logic        lsu_out_cacheable_o;
  logic [10:0] lsu_out_req_tag_o;
  logic        lsu_out_invalidate_o;
  logic        lsu_out_writeback_o;
  logic        lsu_out_flush_o;

  logic        lsu_in_load_fault_o;
  logic        lsu_in_store_fault_o;
  
  // ------------------------------------------------------------
  // Instantiate DUT
  // ------------------------------------------------------------
  riscv_mmu #(
	.MEM_CACHE_ADDR_MIN(32'h0000_0000),
	.MEM_CACHE_ADDR_MAX(32'hFFFF_FFFF),
	.SUPPORT_MMU(1),
	.XLEN(32)
  ) dut (
	.*
  );
  
  // ------------------------------------------------------------
  // Helper tasks for riscv_mmu TB
  // ------------------------------------------------------------
  // Clock int
  always #5 clk_i = ~clk_i;
  
  // ------------------------------------------------------------
  // Local constants (avoid relying on defs.sv in TB)
  // ------------------------------------------------------------
  localparam logic [1:0] PRIV_U = 2'd0;
  localparam logic [1:0] PRIV_S = 2'd1;
  localparam logic [1:0] PRIV_M = 2'd3;
  // MMU uses a special response tag: resp_mmu_w = (lsu_out_resp_tag_i[9:7] == 3'b111)
  localparam logic [10:0] MMU_TAG = 11'b0_111_0000000;
  
  // Sv32 SATP: MODE at bit[31], PPN at [21:0]
  function automatic logic [31:0] make_satp_sv32(input logic mode, input logic [21:0] ppn);
	  make_satp_sv32 = {mode, 9'b0, ppn};
  endfunction

  // Sv32 PTE bits: [0]=V [1]=R [2]=W [3]=X [4]=U [5]=G [6]=A [7]=D
  function automatic logic [31:0] make_pte_sv32(
		  input logic        V, R, W, X, U, G, A, D,
		  input logic [21:0] ppn
	  );
		  // Sv32 PTE:
		  // [31:10] = PPN (22 bits)
		  // [9:8]   = RSW (2 bits, software) -> set 0
		  // [7] D [6] A [5] G [4] U [3] X [2] W [1] R [0] V
		  logic [9:0] flags;
		  begin
			  flags = {2'b00, D, A, G, U, X, W, R, V};
			  make_pte_sv32 = {ppn, flags};
		  end
	  endfunction
  
  // ----------------------------
  // Default all inputs (safe idle)
  // ----------------------------
  task automatic mmu_set_defaults();
  begin
	  // Priv/control
	  priv_d_i              = 2'b11;     // default MACHINE (adjust if your defs differ)
	  sum_i                 = 1'b0;
	  mxr_i                 = 1'b0;
	  flush_i               = 1'b0;
	  satp_i                = 32'b0;     // VM disabled by default

	  // Fetch in
	  fetch_in_rd_i         = 1'b0;
	  fetch_in_flush_i      = 1'b0;
	  fetch_in_invalidate_i = 1'b0;
	  fetch_in_pc_i         = 32'b0;
	  fetch_in_priv_i       = 2'b11;     // MACHINE

	  // Fetch out (memory -> mmu)
	  fetch_out_accept_i    = 1'b1;      // memory ready
	  fetch_out_valid_i     = 1'b0;
	  fetch_out_error_i     = 1'b0;
	  fetch_out_inst_i      = 64'b0;

	  // LSU in
	  lsu_in_addr_i         = 32'b0;
	  lsu_in_data_wr_i      = 32'b0;
	  lsu_in_rd_i           = 1'b0;
	  lsu_in_wr_i           = 4'b0000;
	  lsu_in_cacheable_i    = 1'b1;
	  lsu_in_req_tag_i      = 11'b0;
	  lsu_in_invalidate_i   = 1'b0;
	  lsu_in_writeback_i    = 1'b0;
	  lsu_in_flush_i        = 1'b0;

	  // LSU out response (memory -> mmu)
	  lsu_out_data_rd_i     = 32'b0;
	  lsu_out_accept_i      = 1'b1;      // memory ready to accept req
	  lsu_out_ack_i         = 1'b0;
	  lsu_out_error_i       = 1'b0;
	  lsu_out_resp_tag_i    = 11'b0;
  end
  endtask
  
  task automatic wait_n_clocks(input int n);
	  repeat (n) @(posedge clk_i);
  endtask
  
  // ----------------------------
  // Reset sequence
  // ----------------------------
  task automatic mmu_reset(int unsigned cycles = 5);
  begin
	  mmu_set_defaults();
	  rst_i = 1'b1;
	  repeat (cycles) @(posedge clk_i);
	  rst_i = 1'b0;
	  @(posedge clk_i);
  end
  endtask

  // ----------------------------
  // Drive an instruction fetch request (1-cycle pulse)
  // ----------------------------
  task automatic mmu_ifetch_req(input logic [31:0] pc,
								input logic [1:0]  priv);
  begin
	  fetch_in_pc_i   = pc;
	  fetch_in_priv_i = priv;
	  fetch_in_rd_i   = 1'b1;
	  @(posedge clk_i);
	  fetch_in_rd_i   = 1'b0;
  end
  endtask

  // ----------------------------
  // Provide instruction memory response (1-cycle valid)
  // ----------------------------
  task automatic mmu_ifetch_resp(input logic [63:0] inst,
		  input logic        err = 1'b0);
	begin
	fetch_out_inst_i  = inst;
	fetch_out_error_i = err;

	// assert for a full cycle
	fetch_out_valid_i = 1'b1;
	@(negedge clk_i);
	fetch_out_valid_i = 1'b0;
	fetch_out_error_i = 1'b0;
	end
	endtask

  // ----------------------------
  // Drive LSU load/store request (1-cycle pulse)
  //   - for LOAD: rd=1, wr=0
  //   - for STORE: rd=0, wr=byte_en (e.g. 4'b1111 for SW)
  // ----------------------------
  task automatic mmu_lsu_req(input logic [31:0] addr,
							 input logic        is_load,
							 input logic [3:0]  be,
							 input logic [31:0] wdata,
							 input logic [10:0] tag = 11'h001);
  begin
	  lsu_in_addr_i     = addr;
	  lsu_in_data_wr_i  = wdata;
	  lsu_in_rd_i       = is_load;
	  lsu_in_wr_i       = is_load ? 4'b0000 : be;
	  lsu_in_req_tag_i  = tag;

	  @(posedge clk_i);

	  lsu_in_rd_i       = 1'b0;
	  lsu_in_wr_i       = 4'b0000;
  end
  endtask

  // ----------------------------
  // Provide LSU memory response (1-cycle ack)
  // ----------------------------
  task automatic mmu_lsu_resp(input logic [31:0] rdata,
		  input logic        ack_err = 1'b0,
		  input logic [10:0] rtag = 11'h001);
	begin
	lsu_out_data_rd_i  = rdata;
	lsu_out_error_i    = ack_err;
	lsu_out_resp_tag_i = rtag;
	
	lsu_out_ack_i      = 1'b1;
	@(negedge clk_i);
	lsu_out_ack_i      = 1'b0;
	lsu_out_error_i    = 1'b0;
	end
	endtask

  // ----------------------------
  // Wait helpers (common for checks)
  // ----------------------------
  task automatic wait_fetch_valid(int unsigned timeout = 50);
  begin
	  repeat (timeout) begin
		  @(posedge clk_i);
		  if (fetch_in_valid_o) return;
	  end
	  $fatal(1, "TIMEOUT: fetch_in_valid_o did not assert");
  end
  endtask

  task automatic wait_lsu_ack(int unsigned timeout = 50);
  begin
	  repeat (timeout) begin
		  @(posedge clk_i);
		  if (lsu_in_ack_o) return;
	  end
	  $fatal(1, "TIMEOUT: lsu_in_ack_o did not assert");
  end
  endtask
  
  task automatic wait_mmu_pte_req(int timeout=50);
	  begin
		repeat(timeout) begin
		  @(posedge clk_i);
		  if (lsu_out_rd_o && (lsu_out_req_tag_o[9:7] == 3'b111)) return;
		end
		$fatal(1,"TIMEOUT: MMU did not request PTE via LSU");
	  end
  endtask
  
  // Wait until MMU issues a page-table read on LSU port (MMU tag)
  task automatic wait_mmu_ptw_req(
		  output logic [31:0] addr,
		  input  int unsigned timeout
	  );
	  begin
		  repeat (timeout) begin
			  @(posedge clk_i);
			  if (lsu_out_rd_o && (lsu_out_req_tag_o[9:7] == 3'b111)) begin
				  addr = lsu_out_addr_o;
				  return;
			  end
		  end
		  $fatal(1, "TIMEOUT: MMU did not issue PTW LSU read (tag[9:7]=111)");
	  end
  endtask
  
  // Respond to MMU PTW read (hold ack for a full cycle, safe)
  task automatic respond_mmu_pte(input logic [31:0] pte);
  begin
	  lsu_out_data_rd_i  = pte;
	  lsu_out_resp_tag_i = MMU_TAG; // must match [9:7]=111
	  lsu_out_error_i    = 1'b0;

	  lsu_out_ack_i      = 1'b1;
	  @(negedge clk_i);
	  lsu_out_ack_i      = 1'b0;
  end
  endtask
  
  task automatic mmu_respond_pte(input logic [31:0] pte_value);
	  begin
		  // respond as MMU-tagged LSU response
		  lsu_out_data_rd_i  = pte_value;
		  lsu_out_resp_tag_i = MMU_TAG;   // [9:7]=111
		  lsu_out_error_i    = 1'b0;

		  lsu_out_ack_i      = 1'b1;
		  @(negedge clk_i);               // keep pulse stable across posedge
		  lsu_out_ack_i      = 1'b0;
	  end
  endtask
  
  // ------------------------------------------------------------
  // TEST 1: IFETCH passthrough when MMU disabled
  // ------------------------------------------------------------
  task automatic test_ifetch_passthrough_no_mmu();
	  logic [31:0] pc;
	  logic [63:0] inst;
  begin
	  $display("\n==================================================");
	  $display("[TEST1] IFETCH passthrough when MMU disabled");
	  $display("==================================================");

	  // MMU disabled
	  satp_i = 32'b0;

	  // Ensure memory ready
	  fetch_out_accept_i = 1'b1;

	  pc   = 32'h0000_0100;
	  inst = 64'h0000_0013; // NOP-ish

	  $display("[TEST1] Step 1: CPU issues IFETCH request");
	  $display("[TEST1] Requested PC = 0x%08h", pc);

	  // Drive an ifetch request
	  mmu_ifetch_req(pc, PRIV_M);

	  $display("[TEST1] Step 2: Checking MMU output toward memory...");
	  $display("          fetch_out_rd_o  = %0b", fetch_out_rd_o);
	  $display("          fetch_out_pc_o  = 0x%08h", fetch_out_pc_o);

	  if (fetch_out_rd_o !== 1'b1)
		  $fatal(1, "[TEST1] ERROR: Expected fetch_out_rd_o=1 when MMU disabled");

	  if (fetch_out_pc_o !== pc)
		  $fatal(1, "[TEST1] ERROR: PC mismatch. expected=0x%08h got=0x%08h", pc, fetch_out_pc_o);

	  $display("[TEST1] Step 3: Memory returns instruction 0x%016h", inst);

	  // --------------------------------------------------------
	  // Memory returns instruction
	  // --------------------------------------------------------
	  fetch_out_inst_i  = inst;
	  fetch_out_error_i = 1'b0;
	  fetch_out_valid_i = 1'b1;

	  #1ps;

	  $display("[TEST1] Step 4: Checking MMU return path...");
	  $display("          fetch_in_valid_o = %0b", fetch_in_valid_o);
	  $display("          fetch_in_inst_o  = 0x%016h", fetch_in_inst_o);
	  $display("          fetch_in_fault_o = %0b", fetch_in_fault_o);

	  if (fetch_in_valid_o !== 1'b1)
		  $fatal(1, "[TEST1] ERROR: Expected fetch_in_valid_o=1 during memory response");

	  if (fetch_in_inst_o !== inst)
		  $fatal(1, "[TEST1] ERROR: Instruction mismatch. expected=0x%016h got=0x%016h",
				 inst, fetch_in_inst_o);

	  if (fetch_in_fault_o !== 1'b0)
		  $fatal(1, "[TEST1] ERROR: Unexpected page fault");

	  @(posedge clk_i);
	  fetch_out_valid_i = 1'b0;
	  fetch_out_error_i = 1'b0;

	  $display("--------------------------------------------------");
	  $display("[TEST1 RESULT]");
	  $display("  MMU Mode          : DISABLED");
	  $display("  Request PC        : 0x%08h", pc);
	  $display("  Output PC         : 0x%08h", fetch_out_pc_o);
	  $display("  Instruction       : 0x%016h", fetch_in_inst_o);
	  $display("  Fault             : %0b", fetch_in_fault_o);
	  $display("--------------------------------------------------");
	  $display("TEST1 PASSED ✅  (MMU correctly bypasses translation)");
	  $display("==================================================\n");
  end
  endtask
  // ------------------------------------------------------------
  // TEST 2: LSU load passthrough (MMU disabled)
  // ------------------------------------------------------------
  task automatic test_lsu_passthrough_no_mmu();
	  logic [31:0] addr;
	  logic [31:0] rdata;
	  logic [10:0] tag;
  begin
	  $display("\n==================================================");
	  $display("[TEST2] LSU LOAD passthrough when MMU disabled");
	  $display("==================================================");

	  satp_i = 32'b0;           // MMU disabled
	  priv_d_i = PRIV_M;        // doesn't matter when satp=0
	  lsu_out_accept_i = 1'b1;  // memory ready

	  addr = 32'h0000_2004;
	  rdata = 32'hAABB_CCDD;
	  tag = 11'h001;

	  $display("[TEST2] Step 1: CPU issues LOAD @ VA/PA = 0x%08h", addr);
	  mmu_lsu_req(addr, 1'b1, 4'b0000, 32'b0, tag);

	  $display("[TEST2] Step 2: Check MMU->MEM request");
	  $display("          lsu_out_rd_o   = %0b", lsu_out_rd_o);
	  $display("          lsu_out_addr_o = 0x%08h", lsu_out_addr_o);

	  if (lsu_out_rd_o !== 1'b1) $fatal(1, "[TEST2] ERROR: expected lsu_out_rd_o=1");
	  if (lsu_out_addr_o !== addr) $fatal(1, "[TEST2] ERROR: address mismatch exp=0x%08h got=0x%08h", addr, lsu_out_addr_o);

	  $display("[TEST2] Step 3: Memory returns data 0x%08h", rdata);

	  // drive response manually (race-safe)
	  lsu_out_data_rd_i  = rdata;
	  lsu_out_resp_tag_i = tag;
	  lsu_out_error_i    = 1'b0;
	  lsu_out_ack_i      = 1'b1;

	  #1ps;
	  $display("[TEST2] Step 4: Check CPU-side response");
	  $display("          lsu_in_ack_o      = %0b", lsu_in_ack_o);
	  $display("          lsu_in_data_rd_o  = 0x%08h", lsu_in_data_rd_o);
	  $display("          load_fault/store_fault = %0b/%0b", lsu_in_load_fault_o, lsu_in_store_fault_o);

	  if (lsu_in_ack_o !== 1'b1) $fatal(1, "[TEST2] ERROR: expected lsu_in_ack_o=1 during ack");
	  if (lsu_in_data_rd_o !== rdata) $fatal(1, "[TEST2] ERROR: data mismatch exp=0x%08h got=0x%08h", rdata, lsu_in_data_rd_o);
	  if (lsu_in_load_fault_o !== 1'b0) $fatal(1, "[TEST2] ERROR: unexpected load fault");

	  @(posedge clk_i);
	  lsu_out_ack_i   = 1'b0;
	  lsu_out_error_i = 1'b0;

	  $display("TEST2 PASSED ✅  (LSU path bypass works)");
	  $display("==================================================\n");
  end
  endtask
  // ------------------------------------------------------------
  // TEST 3: ITLB miss → 2-level page walk → translated fetch
  // ------------------------------------------------------------
  task automatic test_itlb_walk_and_translate();
	  logic [31:0] va_pc;
	  logic [21:0] root_ppn, l2_ppn, leaf_ppn;
	  logic [31:0] ptbr, exp_l1_addr, exp_l2_addr, exp_pa_pc;
	  logic [9:0]  vpn1, vpn0;
	  logic [31:0] got_addr;
	  logic [31:0] pte_l1, pte_l2;
	  logic [63:0] inst;
  begin
	  $display("\n==================================================");
	  $display("[TEST3] ITLB miss -> page walk (2-level) -> translate");
	  $display("==================================================");

	  // Enable MMU and use supervisor fetch (so vm_i_enable_w is active)
	  root_ppn = 22'h000100;        // root PT @ 0x0010_0000
	  satp_i   = make_satp_sv32(1'b1, root_ppn);
	  fetch_out_accept_i = 1'b1;
	  lsu_out_accept_i   = 1'b1;

	  // flush tlb
	  flush_i = 1'b1; @(posedge clk_i); flush_i = 1'b0;

	  va_pc = 32'h8040_1234;
	  vpn1  = va_pc[31:22];
	  vpn0  = va_pc[21:12];
	  ptbr  = {root_ppn, 12'b0};

	  exp_l1_addr = ptbr + {20'b0, vpn1, 2'b0};

	  $display("[TEST3] Step 1: IFETCH VA PC = 0x%08h (expect ITLB miss)", va_pc);
	  mmu_ifetch_req(va_pc, PRIV_S);

	  $display("[TEST3] Step 2: MMU should request L1 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l1_addr);
	  if (got_addr !== exp_l1_addr) $fatal(1, "[TEST3] ERROR: L1 PTE addr mismatch");

	  // L1 PTE = pointer to L2 table (non-leaf: R/W/X=0, V=1)
	  l2_ppn = 22'h000200;  // L2 table @ 0x0020_0000
	  pte_l1 = make_pte_sv32(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, l2_ppn);
	  $display("[TEST3] Step 3: Respond L1 PTE -> next level table @ 0x%08h", {l2_ppn,12'b0});
	  respond_mmu_pte(pte_l1);

	  exp_l2_addr = {l2_ppn, 12'b0} + {20'b0, vpn0, 2'b0};

	  $display("[TEST3] Step 4: MMU should request L2 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l2_addr);
	  if (got_addr !== exp_l2_addr) $fatal(1, "[TEST3] ERROR: L2 PTE addr mismatch");

	  // L2 leaf PTE = executable page
	  leaf_ppn = 22'h000300; // page base @ 0x0030_0000
	  pte_l2   = make_pte_sv32(1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, leaf_ppn);
	  exp_pa_pc = {leaf_ppn, va_pc[11:0]};

	  $display("[TEST3] Step 5: Respond L2 leaf PTE -> PA base 0x%08h (exec allowed)", {leaf_ppn,12'b0});
	  respond_mmu_pte(pte_l2);
	  wait_n_clocks(2);
	  
	  // Trigger another fetch -> because itlb_valid_q is still 0, MMU will walk again
	  mmu_ifetch_req(va_pc, PRIV_S);

	  // Expect L1 again
	  $display("[TEST3] PTW#2: MMU should request L1 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l1_addr);
	  if (got_addr !== exp_l1_addr) $fatal(1, "[TEST3] ERROR: L1 PTE addr mismatch (PTW#2)");
	  respond_mmu_pte(pte_l1);

	  // Expect L2 again
	  $display("[TEST3] PTW#2: MMU should request L2 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l2_addr);
	  if (got_addr !== exp_l2_addr) $fatal(1, "[TEST3] ERROR: L2 PTE addr mismatch (PTW#2)");
	  respond_mmu_pte(pte_l2);

	  // Give MMU time to finish update
	  wait_n_clocks(2);
	  
	  // Now ITLB should be filled; re-issue fetch and expect translated PC
	  $display("[TEST3] Step 6: Re-issue IFETCH (expect ITLB hit + translated PC)");

	  // Drive request manually so we can check while rd is still asserted
	  fetch_in_pc_i   = va_pc;
	  fetch_in_priv_i = PRIV_S;
	  fetch_in_rd_i   = 1'b1;

	  #1ps;
	  $display("          fetch_out_rd_o = %0b", fetch_out_rd_o);
	  $display("          fetch_out_pc_o = 0x%08h (expected 0x%08h)", fetch_out_pc_o, exp_pa_pc);

	  if (fetch_out_rd_o !== 1'b1)
		  $fatal(1, "[TEST3] ERROR: expected fetch_out_rd_o=1 on ITLB hit");

	  if (fetch_out_pc_o !== exp_pa_pc)
		  $fatal(1, "[TEST3] ERROR: translated PC mismatch. got=0x%08h exp=0x%08h",
				 fetch_out_pc_o, exp_pa_pc);

	  // End request pulse
	  @(posedge clk_i);
	  fetch_in_rd_i = 1'b0;

	  // Provide instruction from memory and check passthrough
	  inst = 64'hDEAD_BEEF_CAFE_BABE;
	  $display("[TEST3] Step 7: Memory returns instruction 0x%016h", inst);

	  fetch_out_inst_i  = inst;
	  fetch_out_error_i = 1'b0;
	  fetch_out_valid_i = 1'b1;

	  #1ps;
	  $display("[TEST3] Step 8: CPU sees valid=%0b inst=0x%016h fault=%0b",
			   fetch_in_valid_o, fetch_in_inst_o, fetch_in_fault_o);

	  if (fetch_in_valid_o !== 1'b1) $fatal(1, "[TEST3] ERROR: expected fetch_in_valid_o=1");
	  if (fetch_in_inst_o  !== inst) $fatal(1, "[TEST3] ERROR: instruction mismatch");
	  if (fetch_in_fault_o !== 1'b0) $fatal(1, "[TEST3] ERROR: unexpected fault");

	  @(posedge clk_i);
	  fetch_out_valid_i = 1'b0;

	  $display("TEST3 PASSED ✅  (PTW + translation works)");
	  $display("==================================================\n");
  end
  endtask
  // ------------------------------------------------------------
  // TEST 4: IFETCH page fault (leaf PTE has X=0)
  // ------------------------------------------------------------
  task automatic test_ifetch_fault_no_exec();
	  logic [31:0] va_pc;
	  logic [21:0] root_ppn, l2_ppn, leaf_ppn;
	  logic [31:0] ptbr, exp_l1_addr, exp_l2_addr;
	  logic [9:0]  vpn1, vpn0;
	  logic [31:0] got_addr;
	  logic [31:0] pte_l1, pte_l2;
  begin
	  $display("\n==================================================");
	  $display("[TEST4] IFETCH page fault when X=0 (not executable)");
	  $display("==================================================");

	  // Enable MMU in supervisor fetch
	  root_ppn = 22'h000140;        // root PT base
	  satp_i   = make_satp_sv32(1'b1, root_ppn);
	  fetch_out_accept_i = 1'b1;
	  lsu_out_accept_i   = 1'b1;

	  // flush tlb
	  flush_i = 1'b1; @(posedge clk_i); flush_i = 1'b0;

	  va_pc = 32'h8040_5678;
	  vpn1  = va_pc[31:22];
	  vpn0  = va_pc[21:12];
	  ptbr  = {root_ppn, 12'b0};

	  exp_l1_addr = ptbr + {20'b0, vpn1, 2'b0};

	  $display("[TEST4] Step 1: IFETCH VA PC = 0x%08h (expect ITLB miss)", va_pc);
	  mmu_ifetch_req(va_pc, PRIV_S);

	  $display("[TEST4] Step 2: MMU should request L1 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l1_addr);
	  if (got_addr !== exp_l1_addr) $fatal(1, "[TEST4] ERROR: L1 PTE addr mismatch");

	  // L1 PTE points to L2 table
	  l2_ppn = 22'h000240;  // L2 table @ 0x0024_0000
	  pte_l1 = make_pte_sv32(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, l2_ppn);
	  $display("[TEST4] Step 3: Respond L1 PTE -> next level table @ 0x%08h", {l2_ppn,12'b0});
	  respond_mmu_pte(pte_l1);

	  exp_l2_addr = {l2_ppn, 12'b0} + {20'b0, vpn0, 2'b0};

	  $display("[TEST4] Step 4: MMU should request L2 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l2_addr);
	  if (got_addr !== exp_l2_addr) $fatal(1, "[TEST4] ERROR: L2 PTE addr mismatch");

	  // Leaf PTE: V=1 but X=0  => instruction page fault
	  leaf_ppn = 22'h000340; // page base @ 0x0034_0000
	  pte_l2   = make_pte_sv32(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, leaf_ppn); // X=0

	  $display("[TEST4] Step 5: Respond leaf PTE with X=0 (should fault)");
	  respond_mmu_pte(pte_l2);

	  // Workaround: repeat PTW once so itlb_valid_q becomes 1 (same as TEST3)
	  $display("[TEST4] Workaround: repeat PTW once (to make itlb_valid_q go high)");
	  wait_n_clocks(2);

	  mmu_ifetch_req(va_pc, PRIV_S);

	  // L1 again
	  wait_mmu_ptw_req(got_addr, 100);
	  if (got_addr !== exp_l1_addr) $fatal(1, "[TEST4] ERROR: L1 PTE addr mismatch (PTW#2)");
	  respond_mmu_pte(pte_l1);

	  // L2 again
	  wait_mmu_ptw_req(got_addr, 100);
	  if (got_addr !== exp_l2_addr) $fatal(1, "[TEST4] ERROR: L2 PTE addr mismatch (PTW#2)");
	  respond_mmu_pte(pte_l2);

	  wait_n_clocks(2);

	  // Now ITLB hit exists but exec is forbidden -> MMU must block memory read and raise fault
	  $display("[TEST4] Step 6: Re-issue IFETCH (expect FAULT, no memory read)");

	  fetch_in_pc_i   = va_pc;
	  fetch_in_priv_i = PRIV_S;
	  fetch_in_rd_i   = 1'b1;

	  #1ps;
	  $display("          fetch_out_rd_o = %0b (expected 0)", fetch_out_rd_o);
	  if (fetch_out_rd_o !== 1'b0)
		  $fatal(1, "[TEST4] ERROR: expected fetch_out_rd_o=0 on exec fault");

	  @(posedge clk_i);
	  fetch_in_rd_i = 1'b0;

	  // fault is registered (pc_fault_q) and should show as fetch_in_fault_o
	  @(posedge clk_i);
	  $display("[TEST4] Step 7: CPU fault outputs: valid=%0b fault=%0b", fetch_in_valid_o, fetch_in_fault_o);

	  if (fetch_in_valid_o !== 1'b1) $fatal(1, "[TEST4] ERROR: expected fetch_in_valid_o=1 due to fault");
	  if (fetch_in_fault_o !== 1'b1) $fatal(1, "[TEST4] ERROR: expected fetch_in_fault_o=1");

	  $display("TEST4 PASSED ✅  (exec permission fault works)");
	  $display("==================================================\n");
  end
  endtask
  // ------------------------------------------------------------
  // TEST 5: DTLB miss -> 2-level page walk -> translated LOAD
  // ------------------------------------------------------------
  task automatic test_dtlb_load_walk_and_translate();
	  logic [31:0] va;
	  logic [21:0] root_ppn, l2_ppn, leaf_ppn;
	  logic [31:0] ptbr, exp_l1_addr, exp_l2_addr, exp_pa;
	  logic [9:0]  vpn1, vpn0;
	  logic [31:0] got_addr;
	  logic [31:0] pte_l1, pte_l2;
	  logic [31:0] rdata;
	  logic [10:0] cpu_tag;
  begin
	  $display("\n==================================================");
	  $display("[TEST5] DTLB miss -> page walk (2-level) -> translated LOAD");
	  $display("==================================================");

	  // Enable MMU for data side: satp.MODE=1 and priv_d_i != M
	  root_ppn = 22'h000150;
	  satp_i   = make_satp_sv32(1'b1, root_ppn);
	  priv_d_i = PRIV_S;

	  lsu_out_accept_i = 1'b1;

	  // flush tlb
	  flush_i = 1'b1; @(posedge clk_i); flush_i = 1'b0;

	  va    = 32'h8050_1234;
	  vpn1  = va[31:22];
	  vpn0  = va[21:12];
	  ptbr  = {root_ppn, 12'b0};

	  exp_l1_addr = ptbr + {20'b0, vpn1, 2'b0};

	  cpu_tag = 11'h055;

	  $display("[TEST5] Step 1: Issue LOAD VA = 0x%08h (expect DTLB miss -> PTW)", va);
	  mmu_lsu_req(va, 1'b1, 4'b0000, 32'b0, cpu_tag);

	  $display("[TEST5] Step 2: MMU should request L1 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l1_addr);
	  if (got_addr !== exp_l1_addr) $fatal(1, "[TEST5] ERROR: L1 PTE addr mismatch");

	  // L1 PTE -> L2 table
	  l2_ppn = 22'h000250;  // L2 @ 0x0025_0000
	  pte_l1 = make_pte_sv32(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, l2_ppn);
	  $display("[TEST5] Step 3: Respond L1 PTE -> next level table @ 0x%08h", {l2_ppn,12'b0});
	  respond_mmu_pte(pte_l1);

	  exp_l2_addr = {l2_ppn, 12'b0} + {20'b0, vpn0, 2'b0};

	  $display("[TEST5] Step 4: MMU should request L2 PTE via LSU");
	  wait_mmu_ptw_req(got_addr, 100);
	  $display("          MMU PTW addr = 0x%08h (expected 0x%08h)", got_addr, exp_l2_addr);
	  if (got_addr !== exp_l2_addr) $fatal(1, "[TEST5] ERROR: L2 PTE addr mismatch");

	  // Leaf PTE: readable page (R=1) for load
	  leaf_ppn = 22'h000350; // base @ 0x0035_0000
	  pte_l2   = make_pte_sv32(1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, leaf_ppn);
	  exp_pa   = {leaf_ppn, va[11:0]};

	  $display("[TEST5] Step 5: Respond leaf PTE (R=1) -> PA base 0x%08h", {leaf_ppn,12'b0});
	  respond_mmu_pte(pte_l2);

	  // Give MMU time to finish update
	  wait_n_clocks(2);

	  // Re-issue load: should now translate and send real mem read
	  $display("[TEST5] Step 6: Re-issue LOAD (expect DTLB hit + translated PA read)");

	  // Drive LOAD manually so we can check while request is asserted
	  lsu_in_addr_i    = va;
	  lsu_in_data_wr_i = 32'b0;
	  lsu_in_rd_i      = 1'b1;
	  lsu_in_wr_i      = 4'b0000;
	  lsu_in_req_tag_i = cpu_tag;

	  #1ps;
	  $display("          lsu_out_rd_o   = %0b", lsu_out_rd_o);
	  $display("          lsu_out_addr_o = 0x%08h (expected 0x%08h)", lsu_out_addr_o, exp_pa);
	  $display("          lsu_out_req_tag_o = 0x%03h (expected cpu tag 0x%03h)", lsu_out_req_tag_o, cpu_tag);

	  if (lsu_out_rd_o !== 1'b1) $fatal(1, "[TEST5] ERROR: expected lsu_out_rd_o=1 on DTLB hit");
	  if (lsu_out_addr_o !== exp_pa) $fatal(1, "[TEST5] ERROR: translated PA mismatch");
	  if (lsu_out_req_tag_o !== cpu_tag) $fatal(1, "[TEST5] ERROR: tag mismatch (should pass CPU tag)");

	  // End request pulse
	  @(posedge clk_i);
	  lsu_in_rd_i = 1'b0;
	  if (lsu_out_addr_o !== exp_pa) $fatal(1, "[TEST5] ERROR: translated PA mismatch");
	  if (lsu_out_req_tag_o !== cpu_tag) $fatal(1, "[TEST5] ERROR: tag mismatch (should pass CPU tag)");

	  // Memory returns load data
	  rdata = 32'hCAFE_BABE;
	  $display("[TEST5] Step 7: Memory returns rdata=0x%08h", rdata);

	  lsu_out_data_rd_i  = rdata;
	  lsu_out_resp_tag_i = cpu_tag;
	  lsu_out_error_i    = 1'b0;
	  lsu_out_ack_i      = 1'b1;

	  #1ps;
	  $display("[TEST5] Step 8: CPU sees ack=%0b rdata=0x%08h load_fault=%0b",
			   lsu_in_ack_o, lsu_in_data_rd_o, lsu_in_load_fault_o);

	  if (lsu_in_ack_o !== 1'b1) $fatal(1, "[TEST5] ERROR: expected lsu_in_ack_o=1");
	  if (lsu_in_data_rd_o !== rdata) $fatal(1, "[TEST5] ERROR: load data mismatch");
	  if (lsu_in_load_fault_o !== 1'b0) $fatal(1, "[TEST5] ERROR: unexpected load fault");

	  @(posedge clk_i);
	  lsu_out_ack_i = 1'b0;

	  $display("TEST5 PASSED ✅  (DTLB + translated LOAD works)");
	  $display("==================================================\n");
  end
  endtask
  // ------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------
  initial begin
	  // Test calls
	  clk_i = 0;
	  mmu_reset();
	  test_ifetch_passthrough_no_mmu();
	  mmu_reset();
	  test_lsu_passthrough_no_mmu();
	  mmu_reset();
	  test_itlb_walk_and_translate();
	  mmu_reset();
	  test_ifetch_fault_no_exec();
	  mmu_reset();
	  test_dtlb_load_walk_and_translate();
	$display("\nALL LSU TESTS FINISHED");
	$finish;
  end
  endmodule