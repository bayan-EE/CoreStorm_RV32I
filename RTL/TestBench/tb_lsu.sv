`timescale 1ns/1ps

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/data.cc/data/a/home/cc/students/enginer/yazanatamna/corestorm_ref/corestorm_ref_2/riscv_defs.sv"

module tb_lsu;

  // Clock / reset
  logic clk_i, rst_i;

  // ------------------------------------------------------------
  // DUT inputs
  // ------------------------------------------------------------
  logic         opcode_valid_i;
  logic [31:0]  opcode_opcode_i;
  logic [31:0]  opcode_pc_i;
  logic         opcode_invalid_i;
  logic [4:0]   opcode_rd_idx_i;
  logic [4:0]   opcode_ra_idx_i;
  logic [4:0]   opcode_rb_idx_i;
  logic [31:0]  opcode_ra_operand_i;
  logic [31:0]  opcode_rb_operand_i;

  logic [31:0]  mem_data_rd_i;
  logic         mem_accept_i;
  logic         mem_ack_i;
  logic         mem_error_i;
  logic [10:0]  mem_resp_tag_i;
  logic         mem_load_fault_i;
  logic         mem_store_fault_i;
  
  // ------------------------------------------------------------
  // DUT outputs
  // ------------------------------------------------------------
  wire [31:0]   mem_addr_o;
  wire [31:0]   mem_data_wr_o;
  wire          mem_rd_o;
  wire [3:0]    mem_wr_o;
  wire          mem_cacheable_o;
  wire [10:0]   mem_req_tag_o;
  wire          mem_invalidate_o;
  wire          mem_writeback_o;
  wire          mem_flush_o;

  wire          writeback_valid_o;
  wire [31:0]   writeback_value_o;
  wire [5:0]    writeback_exception_o;
  wire          stall_o;
  
  // ------------------------------------------------------------
  // Coverage
  // ------------------------------------------------------------

  covergroup cg_lsu @(posedge clk_i);

	// Did we see load or store requests
	cp_req_type: coverpoint {mem_rd_o, (mem_wr_o != 4'b0)} {
	  bins load  = {2'b10};
	  bins store = {2'b01};
	}

	// Store masks observed
	cp_store_mask: coverpoint mem_wr_o iff (mem_wr_o != 4'b0) {
	  bins sb_lane0 = {4'b0001};
	  bins sb_lane1 = {4'b0010};
	  bins sb_lane2 = {4'b0100};
	  bins sb_lane3 = {4'b1000};
	  bins sh_low   = {4'b0011};
	  bins sh_high  = {4'b1100};
	  bins sw_all   = {4'b1111};
	}

	// Writeback valid
	cp_wb_valid: coverpoint writeback_valid_o {
	  bins valid = {1};
	}

	// Stall behavior
	cp_stall: coverpoint stall_o {
	  bins stall_seen = {1};
	}
	
  endgroup
  
  // ------------------------------------------------------------
  // Instantiate DUT
  // ------------------------------------------------------------
  riscv_lsu #(
	.MEM_CACHE_ADDR_MIN(32'h0000_0000),
	.MEM_CACHE_ADDR_MAX(32'hFFFF_FFFF),
	.XLEN(32)
  ) dut (
	.*
  );
  
  // Coverage call
  cg_lsu lsu_cov = new();
  
  // Clock
  always #5 clk_i = ~clk_i;

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  task automatic wait_n_clocks(input int n);
	repeat (n) @(posedge clk_i);
  endtask
  
  task automatic end_test_cleanup();
	  begin
		// Stop driving an opcode
		@(negedge clk_i);
		opcode_valid_i = 1'b0;
		opcode_opcode_i = 32'h0;
		opcode_pc_i = 32'h0;
		opcode_ra_operand_i = 32'h0;
		opcode_rb_operand_i = 32'h0;
		opcode_rd_idx_i = 5'h0;
		opcode_ra_idx_i = 5'h0;
		opcode_rb_idx_i = 5'h0;
		opcode_invalid_i = 1'b0;

		// Clear memory response inputs (avoid sticky fault/error)
		mem_ack_i         = 1'b0;
		mem_error_i       = 1'b0;
		mem_load_fault_i  = 1'b0;
		mem_store_fault_i = 1'b0;
		mem_data_rd_i     = 32'h0;

		// Keep accept high unless you're testing backpressure
		mem_accept_i      = 1'b1;

		// One quiet cycle
		@(posedge clk_i);
		#1step;
	  end
  endtask
  // SS
  task automatic mem_ack_wait_wb(
		  input  logic [31:0] rdata,
		  output logic        wb_v,
		  output logic [31:0] wb_val,
		  output logic [5:0]  wb_exc
		);
		  int guard;
		begin
		  mem_data_rd_i = rdata;

		  // pulse ack
		  @(negedge clk_i);
		  mem_ack_i = 1'b1;

		  // wait for writeback_valid_o (up to 20 cycles)
		  guard = 0;
		  while (!writeback_valid_o) begin
			@(posedge clk_i);
			guard++;
			if (guard > 20) begin
			  $display("FAIL ❌ mem_ack_wait_wb timeout waiting for writeback_valid_o");
			  break;
			end
		  end

		  #1step;
		  wb_v   = writeback_valid_o;
		  wb_val = writeback_value_o;
		  wb_exc = writeback_exception_o;

		  $display("[DEBUG] (ACK) wb_valid=%0d wb_val=0x%08h wb_exc=0x%0h",
				   wb_v, wb_val, wb_exc);

		  @(negedge clk_i);
		  mem_ack_i = 1'b0;
		end
  endtask
  
  task automatic wait_saw_wr_mask(output logic [3:0] seen_mask);
	  begin
		seen_mask = 4'b0000;
		while (seen_mask == 4'b0000) begin
		  @(posedge clk_i);
		  if (mem_wr_o != 4'b0000)
			seen_mask = mem_wr_o;
		end
		#1step;
	  end
  endtask
  
  task automatic wait_lsu_ready();
	  int guard;
	  begin
		guard = 0;
		while (stall_o) begin
		  @(posedge clk_i);
		  guard++;
		  if (guard > 1200) begin
			$display("FAIL ❌ wait_lsu_ready timeout (stall stuck high)");
			disable wait_lsu_ready;
		  end
		end
	  end
  endtask
  
  task automatic mem_ack_with_data(
		  input  logic [31:0] rdata,
		  output logic        wb_v,
		  output logic [31:0] wb_val,
		  output logic [5:0]  wb_exc
		);
		  begin
			mem_data_rd_i = rdata;

			@(negedge clk_i);
			mem_ack_i = 1'b1;

			@(posedge clk_i);
			#1step;
			wb_v   = writeback_valid_o;
			wb_val = writeback_value_o;
			wb_exc = writeback_exception_o;

			$display("[DEBUG] (ACK) wb_valid=%0d wb_val=0x%08h wb_exc=0x%0h",
					 wb_v, wb_val, wb_exc);

			@(negedge clk_i);
			mem_ack_i = 1'b0;
		  end
		endtask
  
  task automatic clear_inputs();
	opcode_valid_i        = 0;
	opcode_opcode_i       = 32'h0;
	opcode_pc_i           = 32'h0;
	opcode_invalid_i      = 0;
	opcode_rd_idx_i       = 5'h0;
	opcode_ra_idx_i       = 5'h0;
	opcode_rb_idx_i       = 5'h0;
	opcode_ra_operand_i   = 32'h0;
	opcode_rb_operand_i   = 32'h0;

	mem_data_rd_i         = 32'h0;
	mem_accept_i          = 1'b1;
	mem_ack_i             = 1'b0;
	mem_error_i           = 1'b0;
	mem_resp_tag_i        = 11'h0;
	mem_load_fault_i      = 1'b0;
	mem_store_fault_i     = 1'b0;
  endtask

  // Drive an opcode for 1 cycle (like your issue TB style)
  task automatic drive_op(
	input logic        v,
	input logic [31:0] pc,
	input logic [31:0] insn,
	input logic [31:0] rs1_val,
	input logic [31:0] rs2_val,
	input logic [4:0]  rd,
	input logic [4:0]  rs1,
	input logic [4:0]  rs2
  );
  begin
	@(negedge clk_i);
	opcode_valid_i       = v;
	opcode_pc_i          = pc;
	opcode_opcode_i      = insn;
	opcode_ra_operand_i  = rs1_val;
	opcode_rb_operand_i  = rs2_val;
	opcode_rd_idx_i      = rd;
	opcode_ra_idx_i      = rs1;
	opcode_rb_idx_i      = rs2;
	opcode_invalid_i     = 1'b0;
  end
  endtask
  
  task automatic hard_reset_lsu();
	  begin
		rst_i = 1'b1;
		repeat (2) @(posedge clk_i);
		rst_i = 1'b0;
		repeat (1) @(posedge clk_i);
	  end
	  endtask
  // Simple memory "response" helper:
  // - Optionally delay ack by N cycles
  // - Provide read data and/or error/page fault flags
  task automatic mem_respond(
	input int          ack_delay_cycles,
	input logic [31:0] rdata,
	input logic        is_error,
	input logic        load_pf,
	input logic        store_pf
  );
  begin
	mem_data_rd_i     = rdata;
	mem_error_i       = is_error;
	mem_load_fault_i  = load_pf;
	mem_store_fault_i = store_pf;

	// wait
	wait_n_clocks(ack_delay_cycles);

	// pulse ack for 1 cycle
	@(negedge clk_i);
	mem_ack_i = 1'b1;
	wait_n_clocks(1);
	@(negedge clk_i);
	mem_ack_i = 1'b0;

	// clear error flags after response
	mem_error_i       = 1'b0;
	mem_load_fault_i  = 1'b0;
	mem_store_fault_i = 1'b0;
  end
  endtask

  // ------------------------------------------------------------
  // Instruction builders
  // ------------------------------------------------------------
  // I-type load: imm[11:0] rs1 funct3 rd opcode(0000011)
  function automatic logic [31:0] mk_load_i(
	input int imm12,
	input int rs1,
	input int funct3,
	input int rd
  );
	logic [31:0] ins;
	begin
	  ins = 32'h0;
	  ins[6:0]   = 7'b0000011;       // LOAD
	  ins[11:7]  = rd[4:0];
	  ins[14:12] = funct3[2:0];
	  ins[19:15] = rs1[4:0];
	  ins[31:20] = imm12[11:0];
	  mk_load_i  = ins;
	end
  endfunction

  // S-type store: imm[11:5] rs2 rs1 funct3 imm[4:0] opcode(0100011)
  function automatic logic [31:0] mk_store_s(
	input int imm12,
	input int rs1,
	input int rs2,
	input int funct3
  );
	logic [31:0] ins;
	begin
	  ins = 32'h0;
	  ins[6:0]   = 7'b0100011;       // STORE
	  ins[11:7]  = imm12[4:0];
	  ins[14:12] = funct3[2:0];
	  ins[19:15] = rs1[4:0];
	  ins[24:20] = rs2[4:0];
	  ins[31:25] = imm12[11:5];
	  mk_store_s = ins;
	end
  endfunction

  // CSR immediate form for this LSU: it only checks CSR op is CSRRS? (it checks CSR* via INST_CSRRW_MASK == INST_CSRRW)
  // We'll build a "CSRRW x0, csr, rs1" shape (opcode 1110011, funct3=001)
  function automatic logic [31:0] mk_csrrw(
	input int csr12,
	input int rs1,
	input int rd
  );
	logic [31:0] ins;
	begin
	  ins = 32'h0;
	  ins[6:0]   = 7'b1110011;       // SYSTEM
	  ins[11:7]  = rd[4:0];
	  ins[14:12] = 3'b001;           // CSRRW
	  ins[19:15] = rs1[4:0];
	  ins[31:20] = csr12[11:0];
	  mk_csrrw   = ins;
	end
  endfunction

  // ------------------------------------------------------------
  // Tests:
  // ------------------------------------------------------------
  // TEST 1: LW aligned
  // ------------------------------------------------------------
  task automatic test1_lw_aligned();
	logic [31:0] ins;
	logic        wb_v;
	logic [31:0] wb_val;
	logic [5:0]  wb_exc;
	$display("\n[TEST1]: LW aligned -> mem_rd request + writeback");

	clear_inputs();
	end_test_cleanup();
	wait_lsu_ready();

	// LW rd=x5, rs1=x1, imm=4  (addr = rs1_val + 4)
	ins = mk_load_i(12'h004, /*rs1*/1, /*funct3 LW*/3'b010, /*rd*/5);

	// Drive opcode for 1 cycle
	drive_op(1, 32'h0000_0100, ins, 32'h0000_1000, 32'h0, 5, 1, 0);

	// After LSU latches request (posedge), check request outputs
	@(posedge clk_i);
	#1step;
	$display("[DEBUG] (REQ) mem_rd_o=%0d mem_wr_o=%b mem_addr_o=0x%08h stall_o=%0d",
			 mem_rd_o, mem_wr_o, mem_addr_o, stall_o);

	if (mem_rd_o && mem_wr_o == 4'b0000 && mem_addr_o == 32'h0000_1004)
	  $display("PASS ✅ LW request formed correctly");
	else
	  $display("FAIL ❌ LW request wrong (expect mem_rd=1, addr=0x00001004)");

	// Now return data with an ack and check WB on ack cycle
	mem_ack_with_data(32'hAABB_CCDD, wb_v, wb_val, wb_exc);

	if (wb_v && wb_val == 32'hAABB_CCDD && wb_exc == 6'h00)
		$display("PASS ✅ LW writeback correct");
	  else
		$display("FAIL ❌ LW writeback wrong");

	// Stop driving opcode
	drive_op(0, 32'h0, 32'h0, 32'h0, 32'h0, 0, 0, 0);
	@(posedge clk_i);
  endtask

  // ------------------------------------------------------------
  // TEST 2: SW aligned
  // ------------------------------------------------------------
  task automatic test2_sw_aligned();
	logic [31:0] ins;
	logic        wb_v;
	logic [31:0] wb_val;
	logic [5:0]  wb_exc;

	$display("\n[TEST2]: SW aligned -> mem_wr=1111, wdata passthrough");

	clear_inputs();
	end_test_cleanup();
	wait_lsu_ready();

	// SW rs2=x2 -> [rs1+imm], funct3=010
	// base=0x2000, imm=8 => addr=0x2008
	ins = mk_store_s(12'h008, /*rs1*/1, /*rs2*/2, /*funct3 SW*/3'b010);

	// Drive packet (keep valid until we finish)
	drive_op(1, 32'h0000_0200, ins, 32'h0000_2000, 32'h1122_3344, 0, 1, 2);

	// For SW, sample request 2 cycles later (LSU pipeline)
	wait_n_clocks(2);

	$display("[DEBUG] (REQ) mem_rd_o=%0d mem_wr_o=%b mem_addr_o=0x%08h mem_wdata=0x%08h stall_o=%0d",
			 mem_rd_o, mem_wr_o, mem_addr_o, mem_data_wr_o, stall_o);

	if (!mem_rd_o && mem_wr_o == 4'hF && mem_addr_o == 32'h0000_2008 && mem_data_wr_o == 32'h1122_3344)
	  $display("PASS ✅ SW request formed correctly");
	else
	  $display("FAIL ❌ SW request wrong");

	// Complete store (ack pulse) and capture WB pulse
	mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);

	if (wb_v && wb_exc == 6'h00)
	  $display("PASS ✅ SW completed (no exception)");
	else
	  $display("FAIL ❌ SW completion wrong");

	// Stop driving opcode
	drive_op(0, 32'h0, 32'h0, 32'h0, 32'h0, 0, 0, 0);
	@(posedge clk_i);
  endtask
  // ------------------------------------------------------------
  // TEST 3: LB Signed 
  // ------------------------------------------------------------
  task automatic test3_lb_signed();
	  logic [31:0] ins;
	  logic        wb_v;
	  logic [31:0] wb_val;
	  logic [5:0]  wb_exc;
	  logic saw_rd;
	  saw_rd = 0;
	  
	  $display("\n[TEST3]: LB signed -> sign-extend byte");

	  clear_inputs();
	  end_test_cleanup();
	  wait_lsu_ready();

	  // LB rd=x5, rs1=x1, imm=1  addr = 0x3001 (lane=1)
	  ins = mk_load_i(12'h001, 1, 3'b000, 5);

	  // drive opcode (like your style)
	  drive_op(1, 32'h0000_0300, ins, 32'h0000_3000, 32'h0, 5, 1, 0);

	  // Wait until LSU asserts mem_rd_o at least once (may be masked later)
	  while (!saw_rd) begin
		@(posedge clk_i);
		if (mem_rd_o) saw_rd = 1'b1;
	  end
	  
	  #1step;
	  $display("[DEBUG] (REQ) mem_rd_o=%0d mem_wr_o=%b mem_addr_o=0x%08h stall_o=%0d",
			   mem_rd_o, mem_wr_o, mem_addr_o, stall_o);

	  if (saw_rd && mem_addr_o == 32'h0000_3000)
		$display("PASS ✅ LB request ok");
	  else
		$display("FAIL ❌ LB request wrong");

	  // Put 0x80 in byte lane 1 => rdata = 0x00008000
	  // LB from addr+1 should sign-extend to 0xFFFF_FF80
	  mem_ack_wait_wb(32'h0000_8000, wb_v, wb_val, wb_exc);

	  if (wb_v && wb_exc == 0 && wb_val == 32'hFFFF_FF80)
		$display("PASS ✅ LB sign-extend correct");
	  else
		$display("FAIL ❌ LB sign-extend wrong (got 0x%08h exc=0x%0h)", wb_val, wb_exc);

	  // stop driving opcode
	  drive_op(0, 0,0,0,0, 0,0,0);
	  @(posedge clk_i);
	endtask
  // ------------------------------------------------------------
  // TEST 4: LBU Unsigned 
  // ------------------------------------------------------------
	task automatic test4_lbu_unsigned();
		logic [31:0] ins;
		logic        wb_v;
		logic [31:0] wb_val;
		logic [5:0]  wb_exc;
		logic        saw_rd;

		$display("\n[TEST4]: LBU -> zero-extend byte");

		clear_inputs();
		end_test_cleanup();
		wait_lsu_ready();

		// LBU rd=x6, rs1=x1, imm=2  addr=0x4002 (lane=2)
		ins = mk_load_i(12'h002, 1, 3'b100, 6);

		// Drive opcode (your format)
		drive_op(1, 32'h0000_0400, ins, 32'h0000_4000, 32'h0, 6, 1, 0);

		// Wait until LSU asserted mem_rd_o at least once (it may be masked later)
		saw_rd = 1'b0;
		while (!saw_rd) begin
		  @(posedge clk_i);
		  if (mem_rd_o) saw_rd = 1'b1;
		end
		#1step;

		$display("[DEBUG] (REQ) mem_rd_o=%0d mem_wr_o=%b mem_addr_o=0x%08h stall_o=%0d",
				 mem_rd_o, mem_wr_o, mem_addr_o, stall_o);

		// Address output is word-aligned by LSU -> expect 0x4000
		if (saw_rd && mem_addr_o == 32'h0000_4000)
		  $display("PASS ✅ LBU request ok");
		else
		  $display("FAIL ❌ LBU request wrong");

		// For addr=0x4002 (lane=2), put 0x80 in byte lane2 -> rdata = 0x0080_0000
		// LBU should zero-extend -> 0x0000_0080
		mem_ack_wait_wb(32'h0080_0000, wb_v, wb_val, wb_exc);

		if (wb_v && wb_exc == 0 && wb_val == 32'h0000_0080)
		  $display("PASS ✅ LBU zero-extend correct");
		else
		  $display("FAIL ❌ LBU zero-extend wrong (got 0x%08h exc=0x%0h)", wb_val, wb_exc);

		// Stop driving opcode
		drive_op(0, 0,0,0,0, 0,0,0);
		@(posedge clk_i);
	endtask
  // ------------------------------------------------------------
  // TEST 5: LH signed 
  // ------------------------------------------------------------
	task automatic test5_lh_signed();
		logic [31:0] ins;
		logic        wb_v;
		logic [31:0] wb_val;
		logic [5:0]  wb_exc;
		logic        saw_rd;

		$display("\n[TEST5]: LH signed -> sign-extend halfword");

		clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		// LH rd=x7, rs1=x1, imm=2 => addr=0x5002 (upper halfword)
		ins = mk_load_i(12'h002, 1, 3'b001, 7);
		drive_op(1, 32'h0000_0500, ins, 32'h0000_5000, 32'h0, 7, 1, 0);

		saw_rd = 0;
		while (!saw_rd) begin @(posedge clk_i); if (mem_rd_o) saw_rd = 1; end
		#1step;

		if (saw_rd && mem_addr_o == 32'h0000_5000) $display("PASS ✅ LH request ok");
		else $display("FAIL ❌ LH request wrong");

		// For addr=0x5002, use upper halfword bits[31:16]
		// put 0x8001 there => sign-extend -> 0xFFFF8001
		mem_ack_wait_wb(32'h8001_0000, wb_v, wb_val, wb_exc);

		if (wb_v && wb_exc==0 && wb_val==32'hFFFF_8001) $display("PASS ✅ LH sign-extend correct");
		else $display("FAIL ❌ LH wrong (val=0x%08h exc=0x%0h)", wb_val, wb_exc);

		drive_op(0,0,0,0,0,0,0,0);
		@(posedge clk_i);
	endtask
  // ------------------------------------------------------------
  // TEST 6: LHU unsigned 
  // ------------------------------------------------------------
	task automatic test6_lhu_unsigned();
		logic [31:0] ins;
		logic        wb_v;
		logic [31:0] wb_val;
		logic [5:0]  wb_exc;
		logic        saw_rd;

		$display("\n[TEST6]: LHU -> zero-extend halfword");

		clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		// LHU rd=x8, rs1=x1, imm=0 => addr=0x6000 (lower halfword)
		ins = mk_load_i(12'h000, 1, 3'b101, 8);
		drive_op(1, 32'h0000_0600, ins, 32'h0000_6000, 32'h0, 8, 1, 0);

		saw_rd = 0;
		while (!saw_rd) begin @(posedge clk_i); if (mem_rd_o) saw_rd = 1; end
		#1step;

		if (saw_rd && mem_addr_o == 32'h0000_6000) $display("PASS ✅ LHU request ok");
		else $display("FAIL ❌ LHU request wrong");

		// lower halfword = 0x8001 -> zero extend => 0x00008001
		mem_ack_wait_wb(32'h0000_8001, wb_v, wb_val, wb_exc);

		if (wb_v && wb_exc==0 && wb_val==32'h0000_8001) $display("PASS ✅ LHU zero-extend correct");
		else $display("FAIL ❌ LHU wrong (val=0x%08h exc=0x%0h)", wb_val, wb_exc);

		drive_op(0,0,0,0,0,0,0,0);
		@(posedge clk_i);
	endtask
  // ------------------------------------------------------------
  // TEST 7: SB store lane mask + data shift
  // ------------------------------------------------------------
	task automatic test7_sb_lane3();
		logic [31:0] ins;
		logic        wb_v;
		logic [31:0] wb_val;
		logic [5:0]  wb_exc;
		logic [3:0]  seen_mask;

		$display("\n[TEST7]: SB lane3 -> mem_wr mask and shifted data");

		clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		ins = mk_store_s(12'h003, 1, 2, 3'b000);
		drive_op(1, 32'h0000_0700, ins, 32'h0000_7000, 32'h0000_00AA, 0, 1, 2);

		wait_saw_wr_mask(seen_mask);

		$display("[DEBUG] seen_mask=%b mem_addr_o=0x%08h mem_wdata=0x%08h mem_wr_now=%b",
				 seen_mask, mem_addr_o, mem_data_wr_o, mem_wr_o);

		if (mem_addr_o==32'h0000_7000 && seen_mask==4'b1000)
		  $display("PASS ✅ SB mask ok");
		else
		  $display("FAIL ❌ SB mask wrong (seen=%b addr=0x%08h)", seen_mask, mem_addr_o);

		if (mem_data_wr_o == 32'hAA00_0000)
		  $display("PASS ✅ SB data shift ok");
		else
		  $display("FAIL ❌ SB data shift wrong (wdata=0x%08h)", mem_data_wr_o);

		mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);
		if (wb_v && wb_exc==0) $display("PASS ✅ SB completed");
		else $display("FAIL ❌ SB completion wrong exc=0x%0h", wb_exc);

		drive_op(0,0,0,0,0,0,0,0);
		@(posedge clk_i);
	  endtask
  // ------------------------------------------------------------
  // TEST 8: SH store mask + data shift (upper halfword)
  // ------------------------------------------------------------
	  task automatic test8_sh_upper();
		  logic [31:0] ins;
		  logic        wb_v;
		  logic [31:0] wb_val;
		  logic [5:0]  wb_exc;
		  logic [3:0]  seen_mask;

		  $display("\n[TEST8]: SH upper -> mask 1100 and shifted data");

		  clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		  ins = mk_store_s(12'h002, 1, 2, 3'b001);
		  drive_op(1, 32'h0000_0800, ins, 32'h0000_8000, 32'h0000_BEEF, 0, 1, 2);

		  wait_saw_wr_mask(seen_mask);

		  $display("[DEBUG] seen_mask=%b mem_addr_o=0x%08h mem_wdata=0x%08h mem_wr_now=%b",
				   seen_mask, mem_addr_o, mem_data_wr_o, mem_wr_o);

		  if (mem_addr_o==32'h0000_8000 && seen_mask==4'b1100)
			$display("PASS ✅ SH mask ok");
		  else
			$display("FAIL ❌ SH mask wrong (seen=%b addr=0x%08h)", seen_mask, mem_addr_o);

		  if (mem_data_wr_o == 32'hBEEF_0000)
			$display("PASS ✅ SH data shift ok");
		  else
			$display("FAIL ❌ SH data shift wrong (wdata=0x%08h)", mem_data_wr_o);

		  mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);
		  if (wb_v && wb_exc==0) $display("PASS ✅ SH completed");
		  else $display("FAIL ❌ SH completion wrong exc=0x%0h", wb_exc);

		  drive_op(0,0,0,0,0,0,0,0);
		  @(posedge clk_i);
		endtask
	// ------------------------------------------------------------
	// TEST 9: Backpressure (mem_accept_i=0 should stall request launch)
	// ------------------------------------------------------------
	task automatic test9_backpressure_stall();
		logic [31:0] ins;

		$display("\n[TEST9]: Backpressure -> mem_accept_i=0 causes stall");

		clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		// LW normal
		ins = mk_load_i(12'h000, 1, 3'b010, 5);

		// block memory accept
		mem_accept_i = 1'b0;

		drive_op(1, 32'h0000_0900, ins, 32'h0000_9000, 32'h0, 5, 1, 0);

		// wait a couple cycles and check stall asserted
		wait_n_clocks(2);
		#1step;

		if (stall_o) $display("PASS ✅ stall_o asserted under backpressure");
		else $display("FAIL ❌ stall_o not asserted under backpressure");

		// release accept + cleanup
		mem_accept_i = 1'b1;
		drive_op(0,0,0,0,0,0,0,0);
		@(posedge clk_i);
	endtask
	// ------------------------------------------------------------
	// TEST 10: SB lane0 (mask 0001)
	// ------------------------------------------------------------
	task automatic test10_sb_lane0();
		logic [31:0] ins;
		logic        wb_v;
		logic [31:0] wb_val;
		logic [5:0]  wb_exc;
		logic [3:0]  seen_mask;

		$display("\n[TEST10]: SB lane0 -> mask 0001");

		clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		// base=0x9000, imm=0 => addr=0x9000 lane0
		ins = mk_store_s(12'h000, 1, 2, 3'b000); // SB
		drive_op(1, 32'h0000_0A00, ins, 32'h0000_9000, 32'h0000_00AA, 0, 1, 2);

		wait_saw_wr_mask(seen_mask);
		$display("[DEBUG] seen_mask=%b addr=0x%08h wdata=0x%08h", seen_mask, mem_addr_o, mem_data_wr_o);

		if (mem_addr_o==32'h0000_9000 && seen_mask==4'b0001) $display("PASS ✅ SB lane0 mask ok");
		else $display("FAIL ❌ SB lane0 mask wrong (seen=%b addr=0x%08h)", seen_mask, mem_addr_o);

		// Expected shifted data for lane0 = 0x000000AA
		if (mem_data_wr_o == 32'h0000_00AA) $display("PASS ✅ SB lane0 data ok");
		else $display("FAIL ❌ SB lane0 data wrong (wdata=0x%08h)", mem_data_wr_o);

		mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);
		if (wb_v && wb_exc==0) $display("PASS ✅ SB lane0 completed");
		else $display("FAIL ❌ SB lane0 completion wrong exc=0x%0h", wb_exc);

		drive_op(0,0,0,0,0,0,0,0);
		@(posedge clk_i);
	endtask
  // ------------------------------------------------------------
  // TEST 11: SB lane1 (mask 0010)
  // ------------------------------------------------------------
	task automatic test11_sb_lane1();
		logic [31:0] ins;
		logic        wb_v;
		logic [31:0] wb_val;
		logic [5:0]  wb_exc;
		logic [3:0]  seen_mask;

		$display("\n[TEST11]: SB lane1 -> mask 0010");

		clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		// base=0x9000, imm=1 => addr=0x9001 lane1
		ins = mk_store_s(12'h001, 1, 2, 3'b000); // SB
		drive_op(1, 32'h0000_0A10, ins, 32'h0000_9000, 32'h0000_00AA, 0, 1, 2);

		wait_saw_wr_mask(seen_mask);
		$display("[DEBUG] seen_mask=%b addr=0x%08h wdata=0x%08h", seen_mask, mem_addr_o, mem_data_wr_o);

		if (mem_addr_o==32'h0000_9000 && seen_mask==4'b0010) $display("PASS ✅ SB lane1 mask ok");
		else $display("FAIL ❌ SB lane1 mask wrong (seen=%b addr=0x%08h)", seen_mask, mem_addr_o);

		// lane1 => 0x0000AA00
		if (mem_data_wr_o == 32'h0000_AA00) $display("PASS ✅ SB lane1 data ok");
		else $display("FAIL ❌ SB lane1 data wrong (wdata=0x%08h)", mem_data_wr_o);

		mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);
		if (wb_v && wb_exc==0) $display("PASS ✅ SB lane1 completed");
		else $display("FAIL ❌ SB lane1 completion wrong exc=0x%0h", wb_exc);

		drive_op(0,0,0,0,0,0,0,0);
		@(posedge clk_i);
	endtask
	// ------------------------------------------------------------
	// TEST 12: SB lane2 (mask 0100)
	// ------------------------------------------------------------
	  task automatic test12_sb_lane2();
		  logic [31:0] ins;
		  logic        wb_v;
		  logic [31:0] wb_val;
		  logic [5:0]  wb_exc;
		  logic [3:0]  seen_mask;

		  $display("\n[TEST12]: SB lane2 -> mask 0100");

		  clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		  // base=0x9000, imm=2 => addr=0x9002 lane2
		  ins = mk_store_s(12'h002, 1, 2, 3'b000); // SB
		  drive_op(1, 32'h0000_0A20, ins, 32'h0000_9000, 32'h0000_00AA, 0, 1, 2);

		  wait_saw_wr_mask(seen_mask);
		  $display("[DEBUG] seen_mask=%b addr=0x%08h wdata=0x%08h", seen_mask, mem_addr_o, mem_data_wr_o);

		  if (mem_addr_o==32'h0000_9000 && seen_mask==4'b0100) $display("PASS ✅ SB lane2 mask ok");
		  else $display("FAIL ❌ SB lane2 mask wrong (seen=%b addr=0x%08h)", seen_mask, mem_addr_o);

		  // lane2 => 0x00AA0000
		  if (mem_data_wr_o == 32'h00AA_0000) $display("PASS ✅ SB lane2 data ok");
		  else $display("FAIL ❌ SB lane2 data wrong (wdata=0x%08h)", mem_data_wr_o);

		  mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);
		  if (wb_v && wb_exc==0) $display("PASS ✅ SB lane2 completed");
		  else $display("FAIL ❌ SB lane2 completion wrong exc=0x%0h", wb_exc);

		  drive_op(0,0,0,0,0,0,0,0);
		  @(posedge clk_i);
	  endtask
	  // ------------------------------------------------------------
	  // TEST 13: Sh low (mask 0011)
	  // ------------------------------------------------------------
	  task automatic test13_sh_low();
		  logic [31:0] ins;
		  logic        wb_v;
		  logic [31:0] wb_val;
		  logic [5:0]  wb_exc;
		  logic [3:0]  seen_mask;

		  $display("\n[TEST13]: SH low -> mask 0011");

		  clear_inputs(); end_test_cleanup(); wait_lsu_ready();

		  // base=0xA000, imm=0 => addr=0xA000 lower halfword
		  ins = mk_store_s(12'h000, 1, 2, 3'b001); // SH
		  drive_op(1, 32'h0000_0A30, ins, 32'h0000_A000, 32'h0000_BEEF, 0, 1, 2);

		  wait_saw_wr_mask(seen_mask);
		  $display("[DEBUG] seen_mask=%b addr=0x%08h wdata=0x%08h", seen_mask, mem_addr_o, mem_data_wr_o);

		  if (mem_addr_o==32'h0000_A000 && seen_mask==4'b0011) $display("PASS ✅ SH low mask ok");
		  else $display("FAIL ❌ SH low mask wrong (seen=%b addr=0x%08h)", seen_mask, mem_addr_o);

		  // low halfword => 0x0000BEEF
		  if (mem_data_wr_o == 32'h0000_BEEF) $display("PASS ✅ SH low data ok");
		  else $display("FAIL ❌ SH low data wrong (wdata=0x%08h)", mem_data_wr_o);

		  mem_ack_with_data(32'h0, wb_v, wb_val, wb_exc);
		  if (wb_v && wb_exc==0) $display("PASS ✅ SH low completed");
		  else $display("FAIL ❌ SH low completion wrong exc=0x%0h", wb_exc);

		  drive_op(0,0,0,0,0,0,0,0);
		  @(posedge clk_i);
		endtask
  // ------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------
  initial begin
	clk_i = 0;
	rst_i = 1;
	clear_inputs();

	wait_n_clocks(2);
	rst_i = 0;

	// Test calls
	test1_lw_aligned();
	hard_reset_lsu();
	test2_sw_aligned();
	hard_reset_lsu();
	test3_lb_signed();
	hard_reset_lsu();
	test4_lbu_unsigned();
	hard_reset_lsu();
	test5_lh_signed();
	hard_reset_lsu();
	test6_lhu_unsigned();
	hard_reset_lsu();
	test7_sb_lane3();
	hard_reset_lsu();
	test8_sh_upper();
	hard_reset_lsu();
	test9_backpressure_stall();
	hard_reset_lsu();
	test10_sb_lane0();
	hard_reset_lsu();
	test11_sb_lane1();
	hard_reset_lsu();
	test12_sb_lane2();
	hard_reset_lsu();
	test13_sh_low();
	hard_reset_lsu();
	$display("\nALL LSU TESTS FINISHED");
	$display("LSU coverage = %0.2f %%", lsu_cov.get_coverage());
	$finish;
  end

endmodule