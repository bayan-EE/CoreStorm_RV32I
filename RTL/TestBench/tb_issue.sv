`timescale 1ns/1ps

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/data.cc/data/a/home/cc/students/enginer/yazanatamna/corestorm_ref/corestorm_ref_2/riscv_defs.sv"

module tb_issue;

  // Clock / reset
  logic clk_i, rst_i;

  // -------------------------
  // DUT inputs (declare all)
  // -------------------------
  logic        fetch0_valid_i;
  logic [31:0] fetch0_instr_i, fetch0_pc_i;
  logic        fetch0_fault_fetch_i, fetch0_fault_page_i;
  logic        fetch0_instr_exec_i, fetch0_instr_lsu_i, fetch0_instr_branch_i;
  logic        fetch0_instr_mul_i, fetch0_instr_div_i, fetch0_instr_csr_i;
  logic        fetch0_instr_rd_valid_i, fetch0_instr_invalid_i;

  logic        fetch1_valid_i;
  logic [31:0] fetch1_instr_i, fetch1_pc_i;
  logic        fetch1_fault_fetch_i, fetch1_fault_page_i;
  logic        fetch1_instr_exec_i, fetch1_instr_lsu_i, fetch1_instr_branch_i;
  logic        fetch1_instr_mul_i, fetch1_instr_div_i, fetch1_instr_csr_i;
  logic        fetch1_instr_rd_valid_i, fetch1_instr_invalid_i;

  // Branch feedback inputs (tie off simple)
  logic        branch_exec0_request_i, branch_exec0_is_taken_i, branch_exec0_is_not_taken_i;
  logic [31:0] branch_exec0_source_i;
  logic        branch_exec0_is_call_i, branch_exec0_is_ret_i, branch_exec0_is_jmp_i;
  logic [31:0] branch_exec0_pc_i;

  logic        branch_d_exec0_request_i;
  logic [31:0] branch_d_exec0_pc_i;
  logic [1:0]  branch_d_exec0_priv_i;

  logic        branch_exec1_request_i, branch_exec1_is_taken_i, branch_exec1_is_not_taken_i;
  logic [31:0] branch_exec1_source_i;
  logic        branch_exec1_is_call_i, branch_exec1_is_ret_i, branch_exec1_is_jmp_i;
  logic [31:0] branch_exec1_pc_i;

  logic        branch_d_exec1_request_i;
  logic [31:0] branch_d_exec1_pc_i;
  logic [1:0]  branch_d_exec1_priv_i;

  logic        branch_csr_request_i;
  logic [31:0] branch_csr_pc_i;
  logic [1:0]  branch_csr_priv_i;

  // Writebacks (tie off / simple drive)
  logic [31:0] writeback_exec0_value_i, writeback_exec1_value_i;
  logic        writeback_mem_valid_i;
  logic [31:0] writeback_mem_value_i;
  logic [5:0]  writeback_mem_exception_i;
  logic [31:0] writeback_mul_value_i;
  logic        writeback_div_valid_i;
  logic [31:0] writeback_div_value_i;

  // CSR result e1 (tie off)
  logic [31:0] csr_result_e1_value_i;
  logic        csr_result_e1_write_i;
  logic [31:0] csr_result_e1_wdata_i;
  logic [5:0]  csr_result_e1_exception_i;

  logic        lsu_stall_i;
  logic        take_interrupt_i;

  // Slot0 type (based on your predecode inputs)
  logic [2:0] slot0_type, slot1_type;

  // Encode instruction type
  localparam logic [2:0]
	T_NONE   = 3'd0,
	T_EXEC   = 3'd1,
	T_LSU    = 3'd2,
	T_BRANCH = 3'd3,
	T_MUL    = 3'd4,
	T_DIV    = 3'd5,
	T_CSR    = 3'd6;

  // Derive types from your fetch flags (priority order)
  always_comb begin
	slot0_type = T_NONE;
	if (fetch0_valid_i) begin
	  if (fetch0_instr_csr_i)      slot0_type = T_CSR;
	  else if (fetch0_instr_div_i) slot0_type = T_DIV;
	  else if (fetch0_instr_mul_i) slot0_type = T_MUL;
	  else if (fetch0_instr_lsu_i) slot0_type = T_LSU;
	  else if (fetch0_instr_branch_i) slot0_type = T_BRANCH;
	  else if (fetch0_instr_exec_i) slot0_type = T_EXEC;
	end

	slot1_type = T_NONE;
	if (fetch1_valid_i) begin
	  if (fetch1_instr_csr_i)      slot1_type = T_CSR;
	  else if (fetch1_instr_div_i) slot1_type = T_DIV;
	  else if (fetch1_instr_mul_i) slot1_type = T_MUL;
	  else if (fetch1_instr_lsu_i) slot1_type = T_LSU;
	  else if (fetch1_instr_branch_i) slot1_type = T_BRANCH;
	  else if (fetch1_instr_exec_i) slot1_type = T_EXEC;
	end
  end

  // -------------------------
  // DUT outputs
  // -------------------------
  wire fetch0_accept_o, fetch1_accept_o;
  wire branch_request_o;
  wire [31:0] branch_pc_o;
  wire [1:0]  branch_priv_o;

  wire branch_info_request_o;
  wire branch_info_is_taken_o, branch_info_is_not_taken_o;
  wire [31:0] branch_info_source_o;
  wire branch_info_is_call_o, branch_info_is_ret_o, branch_info_is_jmp_o;
  wire [31:0] branch_info_pc_o;

  wire exec0_opcode_valid_o, exec1_opcode_valid_o;
  wire lsu_opcode_valid_o, csr_opcode_valid_o, mul_opcode_valid_o, div_opcode_valid_o;

  wire [31:0] opcode0_opcode_o, opcode0_pc_o;
  wire opcode0_invalid_o;
  wire [4:0] opcode0_rd_idx_o, opcode0_ra_idx_o, opcode0_rb_idx_o;
  wire [31:0] opcode0_ra_operand_o, opcode0_rb_operand_o;

  wire [31:0] opcode1_opcode_o, opcode1_pc_o;
  wire opcode1_invalid_o;
  wire [4:0] opcode1_rd_idx_o, opcode1_ra_idx_o, opcode1_rb_idx_o;
  wire [31:0] opcode1_ra_operand_o, opcode1_rb_operand_o;

  wire [31:0] lsu_opcode_opcode_o, lsu_opcode_pc_o;
  wire lsu_opcode_invalid_o;
  wire [4:0] lsu_opcode_rd_idx_o, lsu_opcode_ra_idx_o, lsu_opcode_rb_idx_o;
  wire [31:0] lsu_opcode_ra_operand_o, lsu_opcode_rb_operand_o;

  wire [31:0] mul_opcode_opcode_o, mul_opcode_pc_o;
  wire mul_opcode_invalid_o;
  wire [4:0] mul_opcode_rd_idx_o, mul_opcode_ra_idx_o, mul_opcode_rb_idx_o;
  wire [31:0] mul_opcode_ra_operand_o, mul_opcode_rb_operand_o;

  wire [31:0] csr_opcode_opcode_o, csr_opcode_pc_o;
  wire csr_opcode_invalid_o;
  wire [4:0] csr_opcode_rd_idx_o, csr_opcode_ra_idx_o, csr_opcode_rb_idx_o;
  wire [31:0] csr_opcode_ra_operand_o, csr_opcode_rb_operand_o;

  wire csr_writeback_write_o;
  wire [11:0] csr_writeback_waddr_o;
  wire [31:0] csr_writeback_wdata_o;
  wire [5:0]  csr_writeback_exception_o;
  wire [31:0] csr_writeback_exception_pc_o;
  wire [31:0] csr_writeback_exception_addr_o;

  wire exec0_hold_o, exec1_hold_o, mul_hold_o;
  wire interrupt_inhibit_o; 
  
  // “Blocked slot1” event: fetch1 valid but not accepted while fetch0 accepted
  wire slot1_blocked_w = fetch1_valid_i && fetch0_accept_o && !fetch1_accept_o;

  // “Dual issued” event
  wire dual_issued_w = exec0_opcode_valid_o && exec1_opcode_valid_o;
  
  logic [31:0] tb_expected_pc;

  // update expected PC when the DUT accepts fetches
  always_ff @(posedge clk_i) begin
	if (rst_i) begin
	  tb_expected_pc <= 32'h0;
	end else begin
	  // If the DUT accepted both, it advanced by 8
	  if (fetch0_accept_o && fetch1_accept_o)
		tb_expected_pc <= tb_expected_pc + 32'd8;
	  // If only slot0 accepted, it advanced by 4
	  else if (fetch0_accept_o)
		tb_expected_pc <= tb_expected_pc + 32'd4;
	end
  end
  
  // -------------------------
  // Coverage Tests
  // -------------------------
  covergroup cg_issue_plus @(posedge clk_i);

	  // -------------------------
	  // Basic issue outcomes
	  // -------------------------
	  cp_issue_mode: coverpoint {exec0_opcode_valid_o, exec1_opcode_valid_o} {
		bins no_issue    = {2'b00};
		bins single_only = {2'b10};
		bins dual_issue  = {2'b11};
	  }

	  // -------------------------
	  // Fetch acceptance patterns
	  // -------------------------
	  cp_accept: coverpoint {fetch0_accept_o, fetch1_accept_o} {
		bins none    = {2'b00};
		bins f0_only = {2'b10};
		bins both    = {2'b11};
	  }

	  // -------------------------
	  // Slot0 / Slot1 instruction type seen (from predecode)
	  // -------------------------
	  cp_slot0_type: coverpoint slot0_type {
		bins exec   = {T_EXEC};
		bins lsu    = {T_LSU};
		bins br     = {T_BRANCH};
		bins mul    = {T_MUL};
		bins div    = {T_DIV};
		bins csr    = {T_CSR};
		bins none   = {T_NONE};
	  }

	  cp_slot1_type: coverpoint slot1_type {
		bins exec   = {T_EXEC};
		bins lsu    = {T_LSU};
		bins br     = {T_BRANCH};
		bins mul    = {T_MUL};
		bins div    = {T_DIV};
		bins csr    = {T_CSR};
		bins none   = {T_NONE};
	  }

	  // -------------------------
	  // Dual-issue pairing coverage (what types you issued together)
	  // Only count when dual issue actually happened
	  // -------------------------
	  cp_dual_pair: coverpoint {slot0_type, slot1_type} iff (dual_issued_w) {
		bins exec_exec   = { {T_EXEC,   T_EXEC} };
		bins exec_lsu    = { {T_EXEC,   T_LSU}  };
		bins exec_mul    = { {T_EXEC,   T_MUL}  };
		bins exec_br     = { {T_EXEC,   T_BRANCH} };
		bins lsu_exec    = { {T_LSU,    T_EXEC} };
		illegal_bins mul_exec = { {T_MUL,    T_EXEC}   };
		illegal_bins br_exec  = { {T_BRANCH, T_EXEC}   };
		// You can add more bins if you expect them to be legal
	  }

	  // -------------------------
	  // Blocking / hazard-like behavior
	  // -------------------------
	  cp_slot1_blocked: coverpoint slot1_blocked_w {
		bins blocked = {1};
	  }

	  // -------------------------
	  // Stalls / global blocks
	  // -------------------------
	  cp_lsu_stall: coverpoint lsu_stall_i {
		bins stall = {1};
	  }
	  
	  cp_interrupt: coverpoint take_interrupt_i {
		  bins intr = {1};
	}

	  // -------------------------
	  // Branch request seen
	  // -------------------------
	  cp_branch_req: coverpoint branch_request_o {
		bins br = {1};
	  }

	endgroup

	cg_issue_plus issue_cov = new();
	
  // -------------------------
  // Instantiate DUT
  // -------------------------
  riscv_issue #(
	.SUPPORT_MULDIV(1),
	.SUPPORT_DUAL_ISSUE(1),
	.SUPPORT_LOAD_BYPASS(1),
	.SUPPORT_MUL_BYPASS(1),
	.SUPPORT_REGFILE_XILINX(0)
  ) dut (
	.* 
  );

  // Clock
  always #5 clk_i = ~clk_i;

  // -------------------------
  // Helpers: pack a dummy R-type to set rs1/rs2/rd fields
  // -------------------------
  task automatic wait_n_clocks(input int n);
	  repeat (n) @(posedge clk_i);
  endtask
  
	task automatic set_issue_pc(input logic [31:0] new_pc);
		// Force issue stage PC to a known value using CSR branch path
		branch_csr_pc_i      = new_pc;
		branch_csr_priv_i    = 2'b11;      // Machine (adjust if your PRIV encoding differs)
		branch_csr_request_i = 1'b1;
		wait_n_clocks(1);
		branch_csr_request_i = 1'b0;
		wait_n_clocks(1);                  // give it a clean cycle
	endtask
	
	task automatic drive_pair_at_expected_pc(
			input logic f0_exec, input logic f0_lsu, input logic f0_br, input logic f0_mul, input logic f0_div, input logic f0_csr, input logic f0_rd_valid,
			input logic f1_exec, input logic f1_lsu, input logic f1_br, input logic f1_mul, input logic f1_div, input logic f1_csr, input logic f1_rd_valid
		  );
			logic [31:0] pc0, pc1;
			begin
			  pc0 = tb_expected_pc;
			  pc1 = tb_expected_pc + 32'd4;

			  // Drive on negedge so signals are stable before posedge sampling
			  @(negedge clk_i);
			  clear_fetch();
			  drive_fetch0(1, pc0, mk_rtype(1,2,3), f0_exec,f0_lsu,f0_br,f0_mul,f0_div,f0_csr, f0_rd_valid);
			  drive_fetch1(1, pc1, mk_rtype(4,5,6), f1_exec,f1_lsu,f1_br,f1_mul,f1_div,f1_csr, f1_rd_valid);
			end
	endtask
	
	function automatic logic [31:0] mk_rtype(input int rd, input int rs1, input int rs2);
	  logic [31:0] ins;
	  begin
		ins = 32'b0;
		ins[11:7]  = rd[4:0];
		ins[19:15] = rs1[4:0];
		ins[24:20] = rs2[4:0];
		mk_rtype = ins;
	  end
	endfunction
	
	task automatic clear_longlat_pending();
		// Clear DIV pending (if any)
		writeback_div_valid_i = 1'b1;
		writeback_div_value_i = 32'h0;
		wait_n_clocks(1);
		writeback_div_valid_i = 1'b0;

		// Clear CSR pending (if any)
		// (CSR completion is signaled through csr_result_e1_write_i / exception inputs)
		csr_result_e1_write_i     = 1'b1;
		csr_result_e1_value_i     = 32'h0;
		csr_result_e1_wdata_i     = 32'h0;
		csr_result_e1_exception_i = 6'h00;
		wait_n_clocks(1);
		csr_result_e1_write_i     = 1'b0;

		wait_n_clocks(1);
	endtask
	
	task automatic clear_fetch();
	  fetch0_valid_i = 0;
	  fetch1_valid_i = 0;

	  fetch0_instr_exec_i = 0; fetch0_instr_lsu_i = 0; fetch0_instr_branch_i = 0;
	  fetch0_instr_mul_i  = 0; fetch0_instr_div_i = 0; fetch0_instr_csr_i    = 0;
	  fetch0_instr_rd_valid_i = 0; fetch0_instr_invalid_i = 0;
	  fetch0_fault_fetch_i = 0; fetch0_fault_page_i = 0;
	  fetch0_instr_i = 32'b0; fetch0_pc_i = 32'b0;

	  fetch1_instr_exec_i = 0; fetch1_instr_lsu_i = 0; fetch1_instr_branch_i = 0;
	  fetch1_instr_mul_i  = 0; fetch1_instr_div_i = 0; fetch1_instr_csr_i    = 0;
	  fetch1_instr_rd_valid_i = 0; fetch1_instr_invalid_i = 0;
	  fetch1_fault_fetch_i = 0; fetch1_fault_page_i = 0;
	  fetch1_instr_i = 32'b0; fetch1_pc_i = 32'b0;
	endtask

	task automatic drive_fetch0(
	  input logic v, input logic [31:0] pc, input logic [31:0] ins,
	  input logic is_exec, input logic is_lsu, input logic is_branch,
	  input logic is_mul,  input logic is_div, input logic is_csr,
	  input logic rd_valid
	);
	begin
	  fetch0_valid_i          = v;
	  fetch0_pc_i             = pc;
	  fetch0_instr_i          = ins;
	  fetch0_fault_fetch_i    = 0;
	  fetch0_fault_page_i     = 0;
	  fetch0_instr_exec_i     = is_exec;
	  fetch0_instr_lsu_i      = is_lsu;
	  fetch0_instr_branch_i   = is_branch;
	  fetch0_instr_mul_i      = is_mul;
	  fetch0_instr_div_i      = is_div;
	  fetch0_instr_csr_i      = is_csr;
	  fetch0_instr_rd_valid_i = rd_valid;
	  fetch0_instr_invalid_i  = 0;
	end
	endtask

	task automatic drive_fetch1(
	  input logic v, input logic [31:0] pc, input logic [31:0] ins,
	  input logic is_exec, input logic is_lsu, input logic is_branch,
	  input logic is_mul,  input logic is_div, input logic is_csr,
	  input logic rd_valid
	);
	begin
	  fetch1_valid_i          = v;
	  fetch1_pc_i             = pc;
	  fetch1_instr_i          = ins;
	  fetch1_fault_fetch_i    = 0;
	  fetch1_fault_page_i     = 0;
	  fetch1_instr_exec_i     = is_exec;
	  fetch1_instr_lsu_i      = is_lsu;
	  fetch1_instr_branch_i   = is_branch;
	  fetch1_instr_mul_i      = is_mul;
	  fetch1_instr_div_i      = is_div;
	  fetch1_instr_csr_i      = is_csr;
	  fetch1_instr_rd_valid_i = rd_valid;
	  fetch1_instr_invalid_i  = 0;
	end
	endtask

  // -------------------------
  // Test sequence
  // -------------------------
  initial begin
	// Init defaults
	clk_i = 0; rst_i = 1;

	// tie-offs
	branch_exec0_request_i=0; branch_exec0_is_taken_i=0; branch_exec0_is_not_taken_i=0;
	branch_exec0_source_i=0; branch_exec0_is_call_i=0; branch_exec0_is_ret_i=0; branch_exec0_is_jmp_i=0;
	branch_exec0_pc_i=0;
	branch_d_exec0_request_i=0; branch_d_exec0_pc_i=0; branch_d_exec0_priv_i=0;

	branch_exec1_request_i=0; branch_exec1_is_taken_i=0; branch_exec1_is_not_taken_i=0;
	branch_exec1_source_i=0; branch_exec1_is_call_i=0; branch_exec1_is_ret_i=0; branch_exec1_is_jmp_i=0;
	branch_exec1_pc_i=0;
	branch_d_exec1_request_i=0; branch_d_exec1_pc_i=0; branch_d_exec1_priv_i=0;

	branch_csr_request_i=0; branch_csr_pc_i=0; branch_csr_priv_i=0;

	writeback_exec0_value_i=0; writeback_exec1_value_i=0;
	writeback_mem_valid_i=0; writeback_mem_value_i=0; writeback_mem_exception_i=0;
	writeback_mul_value_i=0;
	writeback_div_valid_i=0; writeback_div_value_i=0;

	csr_result_e1_value_i=0; csr_result_e1_write_i=0; csr_result_e1_wdata_i=0; csr_result_e1_exception_i=0;

	lsu_stall_i=0; take_interrupt_i=0;

	// Clear fetch
	drive_fetch0(0, 32'h0, 32'h0, 0,0,0,0,0,0,0);
	drive_fetch1(0, 32'h0, 32'h0, 0,0,0,0,0,0,0);

	// Release reset
	wait_n_clocks(2);
	rst_i = 0;
	
	// Helper Test calls
	test_lsu_type();
	test_mul_type();
	test_div_type();
	test_csr_type();
	test_branch_type();
	test_interrupt_block();
	test_slot1_lsu();
	test_slot1_mul();
	test_slot1_div();
	test_slot1_csr();
	test_slot1_branch();
	
	// Test calls 
	test_single_issue_fetch0();
	test_dual_issue_exec_exec();
	test_raw_hazard_blocks_second();
	test_lsu_stall_blocks_issue();
	test_dual_exec_lsu();
	test_dual_exec_mul();
	test_dual_exec_branch();
	test_dual_lsu_exec();
	$display("\n[COVERAGE] issue_cov = %0.2f%%", issue_cov.get_coverage());
	$display("\nALL TESTS FINISHED");
	$finish;
  end
  
  	task automatic test_lsu_type();
	  	$display("\n[TEST]: LSU instruction coverage");

	  	clear_fetch();
	  	drive_fetch0(1, 32'h20, mk_rtype(5,1,2),
				   0,1,0,0,0,0, 1);  // lsu=1

	  	wait_n_clocks(1);

	  	clear_fetch();
	  	wait_n_clocks(1);
	  endtask
	
	task automatic test_mul_type();
		$display("\n[TEST]: MUL instruction coverage");

		clear_fetch();
		drive_fetch0(1, 32'h24, mk_rtype(6,1,2),
					 0,0,0,1,0,0, 1);  // mul=1

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	  endtask
	
	task automatic test_div_type();
		$display("\n[TEST]: DIV instruction coverage");

		clear_fetch();
		drive_fetch0(1, 32'h28, mk_rtype(7,1,2),
					 0,0,0,0,1,0, 1);  // div=1

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	
	task automatic test_csr_type();
		$display("\n[TEST]: CSR instruction coverage");

		clear_fetch();
		drive_fetch0(1, 32'h2C, mk_rtype(8,1,2),
					 0,0,0,0,0,1, 1);  // csr=1

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	
	task automatic test_branch_type();
		$display("\n[TEST]: Branch instruction coverage");

		clear_fetch();
		drive_fetch0(1, 32'h30, mk_rtype(9,1,2),
					 0,0,1,0,0,0, 0);  // branch=1

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	
	task automatic test_interrupt_block();
		$display("\n[TEST]: Interrupt coverage");

		clear_fetch();
		take_interrupt_i = 1;

		drive_fetch0(1, 32'h34, mk_rtype(10,1,2),
					 1,0,0,0,0,0, 1);

		wait_n_clocks(1);

		take_interrupt_i = 0;
		clear_fetch();
		wait_n_clocks(1);
	endtask
	
	task automatic test_slot1_lsu();
		$display("\n[TEST]: Slot1 LSU coverage");

		clear_fetch();
		drive_fetch0(1, 32'h100, mk_rtype(1,2,3), 1,0,0,0,0,0, 1); // harmless exec
		drive_fetch1(1, 32'h104, mk_rtype(2,3,4), 0,1,0,0,0,0, 1); // lsu in slot1

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	task automatic test_slot1_mul();
		$display("\n[TEST]: Slot1 MUL coverage");

		clear_fetch();
		drive_fetch0(1, 32'h110, mk_rtype(1,2,3), 1,0,0,0,0,0, 1);
		drive_fetch1(1, 32'h114, mk_rtype(2,3,4), 0,0,0,1,0,0, 1);

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	task automatic test_slot1_div();
		$display("\n[TEST]: Slot1 DIV coverage");

		clear_fetch();
		drive_fetch0(1, 32'h120, mk_rtype(1,2,3), 1,0,0,0,0,0, 1);
		drive_fetch1(1, 32'h124, mk_rtype(2,3,4), 0,0,0,0,1,0, 1);

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	task automatic test_slot1_csr();
		$display("\n[TEST]: Slot1 CSR coverage");

		clear_fetch();
		drive_fetch0(1, 32'h130, mk_rtype(1,2,3), 1,0,0,0,0,0, 1);
		drive_fetch1(1, 32'h134, mk_rtype(2,3,4), 0,0,0,0,0,1, 1);

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	endtask
	task automatic test_slot1_branch();
		$display("\n[TEST]: Slot1 Branch coverage");

		clear_fetch();
		drive_fetch0(1, 32'h140, mk_rtype(1,2,3), 1,0,0,0,0,0, 1);
		drive_fetch1(1, 32'h144, mk_rtype(2,3,4), 0,0,1,0,0,0, 0);

		wait_n_clocks(1);

		clear_fetch();
		wait_n_clocks(1);
	  endtask
	
	// ---- Test 1: Single issue (only fetch0)
	task automatic test_single_issue_fetch0();
		$display("\n[TEST]: Single issue - fetch0 only (exec)");

		// Setup: one exec instruction in fetch0 at PC=0
		clear_fetch();
		drive_fetch0(1, 32'h0000_0000, mk_rtype(1,2,3),
					 1,0,0,0,0,0, 1);
		drive_fetch1(0, 32'h0000_0004, 32'h0,
					 0,0,0,0,0,0, 0);

		// Debug before clocking
		$display("[DEBUG] Sending fetch0:");
		$display("  fetch0_pc_i      = 0x%08h", fetch0_pc_i);
		$display("  fetch0_instr_i   = 0x%08h", fetch0_instr_i);
		$display("  fetch0_exec      = %0d", fetch0_instr_exec_i);

		wait_n_clocks(1);

		// Debug after issue
		$display("[DEBUG] After 1 cycle:");
		$display("  fetch0_accept_o     = %b", fetch0_accept_o);
		$display("  exec0_opcode_valid  = %b", exec0_opcode_valid_o);
		$display("  exec1_opcode_valid  = %b", exec1_opcode_valid_o);
		$display("  opcode0_pc_o        = 0x%08h", opcode0_pc_o);
		$display("  opcode0_opcode_o    = 0x%08h", opcode0_opcode_o);

		if (fetch0_accept_o && exec0_opcode_valid_o && !exec1_opcode_valid_o)
		  $display("PASS ✅ Single issue behaved correctly");
		else
		  $display("FAIL ❌ Single issue unexpected behavior");

		clear_fetch();
		wait_n_clocks(1);
	  endtask

	// ---- Test 2: Dual issue (fetch0 + fetch1, both exec, no hazards)
	
	  task automatic test_dual_issue_exec_exec();
		  $display("\n[TEST]: Dual issue - exec + exec (no hazards)");

		  // Setup: two independent exec ops
		  clear_fetch();
		  drive_fetch0(1, 32'h0000_0004, mk_rtype(4,5,6),  1,0,0,0,0,0, 1);
		  drive_fetch1(1, 32'h0000_0008, mk_rtype(7,8,9),  1,0,0,0,0,0, 1);

		  // Debug before clocking
		  $display("[DEBUG] Sending fetch0+fetch1:");
		  $display("  f0: pc=0x%08h instr=0x%08h rd=%0d rs1=%0d rs2=%0d",
				   fetch0_pc_i, fetch0_instr_i, fetch0_instr_i[11:7], fetch0_instr_i[19:15], fetch0_instr_i[24:20]);
		  $display("  f1: pc=0x%08h instr=0x%08h rd=%0d rs1=%0d rs2=%0d",
				   fetch1_pc_i, fetch1_instr_i, fetch1_instr_i[11:7], fetch1_instr_i[19:15], fetch1_instr_i[24:20]);

		  wait_n_clocks(1);

		  // Debug after issue
		  $display("[DEBUG] After 1 cycle:");
		  $display("  fetch0_accept_o     = %b", fetch0_accept_o);
		  $display("  fetch1_accept_o     = %b", fetch1_accept_o);
		  $display("  exec0_opcode_valid  = %b", exec0_opcode_valid_o);
		  $display("  exec1_opcode_valid  = %b", exec1_opcode_valid_o);
		  $display("  opcode0_pc_o        = 0x%08h", opcode0_pc_o);
		  $display("  opcode1_pc_o        = 0x%08h", opcode1_pc_o);

		  if (exec0_opcode_valid_o && exec1_opcode_valid_o && fetch0_accept_o && fetch1_accept_o)
			$display("PASS ✅ Dual issue worked (both issued)");
		  else
			$display("FAIL ❌ Dual issue did not issue both");

		  clear_fetch();
		  wait_n_clocks(1);
		endtask

	// ---- Test 3: Hazard stall (slot1 reads rd of slot0)
	
		task automatic test_raw_hazard_blocks_second();
			$display("\n[TEST]: RAW hazard - slot1 depends on slot0 rd (expect no dual issue)");

			// slot0 writes x10
			// slot1 reads x10 as rs1 => should NOT issue in pipe1 same cycle
			clear_fetch();
			drive_fetch0(1, 32'h0000_000C, mk_rtype(10,1,2), 1,0,0,0,0,0, 1);
			drive_fetch1(1, 32'h0000_0010, mk_rtype(3,10,4), 1,0,0,0,0,0, 1);

			// Debug before clocking
			$display("[DEBUG] Sending dependent pair:");
			$display("  slot0: rd=%0d rs1=%0d rs2=%0d", fetch0_instr_i[11:7], fetch0_instr_i[19:15], fetch0_instr_i[24:20]);
			$display("  slot1: rd=%0d rs1=%0d rs2=%0d", fetch1_instr_i[11:7], fetch1_instr_i[19:15], fetch1_instr_i[24:20]);

			wait_n_clocks(1);

			// Debug after issue
			$display("[DEBUG] After 1 cycle:");
			$display("  exec0_opcode_valid  = %b", exec0_opcode_valid_o);
			$display("  exec1_opcode_valid  = %b", exec1_opcode_valid_o);
			$display("  fetch0_accept_o     = %b", fetch0_accept_o);
			$display("  fetch1_accept_o     = %b", fetch1_accept_o);

			if (exec0_opcode_valid_o && !exec1_opcode_valid_o)
			  $display("PASS ✅ RAW hazard prevented second issue");
			else
			  $display("FAIL ❌ Expected exec1 not to issue");

			clear_fetch();
			wait_n_clocks(1);
		  endtask

	// ---- Test 4: LSU stall blocks issue
		  task automatic test_lsu_stall_blocks_issue();
			  $display("\n[TEST]: LSU stall - lsu_stall_i=1 should block issuing");

			  clear_fetch();
			  lsu_stall_i = 1;

			  drive_fetch0(1, 32'h0000_0014, mk_rtype(11,1,2), 1,0,0,0,0,0, 1);
			  drive_fetch1(0, 32'h0, 32'h0, 0,0,0,0,0,0, 0);

			  // Debug before clocking
			  $display("[DEBUG] LSU stall asserted, sending fetch0:");
			  $display("  lsu_stall_i     = %b", lsu_stall_i);
			  $display("  fetch0_valid_i  = %b", fetch0_valid_i);

			  wait_n_clocks(1);

			  // Debug after
			  $display("[DEBUG] After 1 cycle:");
			  $display("  exec0_opcode_valid  = %b", exec0_opcode_valid_o);
			  $display("  fetch0_accept_o     = %b", fetch0_accept_o);

			  if (!exec0_opcode_valid_o && !fetch0_accept_o)
				$display("PASS ✅ LSU stall blocked issue");
			  else
				$display("FAIL ❌ LSU stall did not block as expected");

			  lsu_stall_i = 0;
			  clear_fetch();
			  wait_n_clocks(1);
		  endtask
		  
	// ---- Test 5: EXEC + lsu:
		  task automatic test_dual_exec_lsu();
			  $display("\n[TEST]: Dual pair coverage - EXEC + LSU");

			  clear_fetch();
			  lsu_stall_i = 0;
			  take_interrupt_i = 0;
			  clear_longlat_pending();
			  set_issue_pc(32'h0000_0200);

			  drive_fetch0(1, 32'h0000_0200, mk_rtype(1,2,3), 1,0,0,0,0,0, 1); // EXEC
			  drive_fetch1(1, 32'h0000_0204, mk_rtype(4,5,6), 0,1,0,0,0,0, 1); // LSU

			  wait_n_clocks(1);

			  $display("[DEBUG] f0_acc=%0d f1_acc=%0d e0=%0d e1=%0d lsu_valid=%0d",
					   fetch0_accept_o, fetch1_accept_o, exec0_opcode_valid_o, exec1_opcode_valid_o, lsu_opcode_valid_o);

			  if (exec0_opcode_valid_o && exec1_opcode_valid_o)
				$display("PASS ✅ dual-issued EXEC+LSU");
			  else
				$display("FAIL ❌ did not dual-issue EXEC+LSU");

			  clear_fetch();
			  wait_n_clocks(1);
		  endtask
		  
	// ---- Test 6: EXEC + MUL:
			task automatic test_dual_exec_mul();
				$display("\n[TEST]: Dual pair coverage - EXEC + MUL");

				clear_fetch();
				lsu_stall_i = 0;
				take_interrupt_i = 0;
				clear_longlat_pending();
				set_issue_pc(32'h0000_0210);

				drive_fetch0(1, 32'h0000_0210, mk_rtype(1,2,3), 1,0,0,0,0,0, 1); // EXEC
				drive_fetch1(1, 32'h0000_0214, mk_rtype(4,5,6), 0,0,0,1,0,0, 1); // MUL

				wait_n_clocks(1);

				$display("[DEBUG] f0_acc=%0d f1_acc=%0d e0=%0d e1=%0d mul_valid=%0d",
						 fetch0_accept_o, fetch1_accept_o, exec0_opcode_valid_o, exec1_opcode_valid_o, mul_opcode_valid_o);

				if (exec0_opcode_valid_o && exec1_opcode_valid_o)
				  $display("PASS ✅ dual-issued EXEC+MUL");
				else
				  $display("FAIL ❌ did not dual-issue EXEC+MUL");

				clear_fetch();
				wait_n_clocks(1);
			endtask
			
	// ---- Test 7: EXEC + BRANCH:
			task automatic test_dual_exec_branch();
				$display("\n[TEST]: Dual pair coverage - EXEC + BRANCH");

				clear_fetch();
				lsu_stall_i = 0;
				take_interrupt_i = 0;
				clear_longlat_pending();
				set_issue_pc(32'h0000_0220);

				drive_fetch0(1, 32'h0000_0220, mk_rtype(1,2,3), 1,0,0,0,0,0, 1); // EXEC
				drive_fetch1(1, 32'h0000_0224, mk_rtype(0,4,5), 0,0,1,0,0,0, 0); // BRANCH

				wait_n_clocks(1);

				$display("[DEBUG] f0_acc=%0d f1_acc=%0d e0=%0d e1=%0d",
						 fetch0_accept_o, fetch1_accept_o, exec0_opcode_valid_o, exec1_opcode_valid_o);

				if (exec0_opcode_valid_o && exec1_opcode_valid_o)
				  $display("PASS ✅ dual-issued EXEC+BRANCH");
				else
				  $display("FAIL ❌ did not dual-issue EXEC+BRANCH");

				clear_fetch();
				wait_n_clocks(1);
			endtask
			
			// ---- Test 8: LSU + EXEC
			task automatic test_dual_lsu_exec();
			  $display("\n[TEST]: Dual pair coverage - LSU + EXEC");

			  clear_fetch();
			  lsu_stall_i = 0;
			  take_interrupt_i = 0;
			  clear_longlat_pending();
			  // Force DUT expected PC to match our fetch PCs
			  set_issue_pc(32'h0000_0218);

			  drive_fetch0(1, 32'h0000_0218, mk_rtype(1,2,3), 0,1,0,0,0,0, 1); // LSU
			  drive_fetch1(1, 32'h0000_021C, mk_rtype(4,5,6), 1,0,0,0,0,0, 1); // EXEC

			  wait_n_clocks(1);

			  $display("[DEBUG] f0_acc=%0d f1_acc=%0d  exec0_valid=%0d exec1_valid=%0d  lsu_valid=%0d",
					   fetch0_accept_o, fetch1_accept_o, exec0_opcode_valid_o, exec1_opcode_valid_o, lsu_opcode_valid_o);

			  if (exec0_opcode_valid_o && exec1_opcode_valid_o)
				$display("PASS ✅ dual-issued LSU+EXEC");
			  else
				$display("FAIL ❌ did not dual-issue LSU+EXEC");

			  clear_fetch();
			  wait_n_clocks(1);
			endtask
		
endmodule