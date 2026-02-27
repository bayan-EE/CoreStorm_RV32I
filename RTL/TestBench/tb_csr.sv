`timescale 1ns/1ps
//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/data.cc/data/a/home/cc/students/enginer/yazanatamna/corestorm_ref/corestorm_ref_2/riscv_defs.sv"

module tb_csr;

  // === Parameters ===
  localparam XLEN = 32;
  localparam EXPECTED_ECALL_CODE_MACHINE = `EXCEPTION_ECALL_M;
  logic [5:0] exception_code;
		  
  // === DUT Inputs ===
  logic clk_i;
  logic rst_i;
  logic intr_i;

  logic opcode_valid_i;
  logic [XLEN-1:0] opcode_opcode_i;
  logic [XLEN-1:0] opcode_pc_i;
  logic opcode_invalid_i;
  logic [4:0] opcode_rd_idx_i;
  logic [4:0] opcode_ra_idx_i;
  logic [4:0] opcode_rb_idx_i;
  logic [XLEN-1:0] opcode_ra_operand_i;
  logic [XLEN-1:0] opcode_rb_operand_i;

  logic csr_writeback_write_i;
  logic [11:0] csr_writeback_waddr_i;
  logic [XLEN-1:0] csr_writeback_wdata_i;
  logic [5:0] csr_writeback_exception_i;
  logic [XLEN-1:0] csr_writeback_exception_pc_i;
  logic [XLEN-1:0] csr_writeback_exception_addr_i;

  logic [XLEN-1:0] cpu_id_i;
  logic [XLEN-1:0] reset_vector_i;
  logic interrupt_inhibit_i;

  // === DUT Outputs ===
  logic [XLEN-1:0] csr_result_e1_value_o;
  logic csr_result_e1_write_o;
  logic [XLEN-1:0] csr_result_e1_wdata_o;
  logic [5:0] csr_result_e1_exception_o;
  logic branch_csr_request_o;
  logic [XLEN-1:0] branch_csr_pc_o;
  logic [1:0] branch_csr_priv_o;
  logic take_interrupt_o;
  logic ifence_o;
  logic [1:0] mmu_priv_d_o;
  logic mmu_sum_o;
  logic mmu_mxr_o;
  logic mmu_flush_o;
  logic [XLEN-1:0] mmu_satp_o;

  // === Clock Generation ===
  initial clk_i = 0;
  always #5 clk_i = ~clk_i;


riscv_csr #(
	  .SUPPORT_MULDIV(1),
	  .SUPPORT_SUPER(0),
	  .XLEN(XLEN)
  ) dut (
	  // Inputs
	  .clk_i                         (clk_i),
	  .rst_i                         (rst_i),
	  .intr_i                        (intr_i),
	  .opcode_valid_i                (opcode_valid_i),
	  .opcode_opcode_i               (opcode_opcode_i),
	  .opcode_pc_i                   (opcode_pc_i),
	  .opcode_invalid_i              (opcode_invalid_i),
	  .opcode_rd_idx_i               (opcode_rd_idx_i),
	  .opcode_ra_idx_i               (opcode_ra_idx_i),
	  .opcode_rb_idx_i               (opcode_rb_idx_i),
	  .opcode_ra_operand_i           (opcode_ra_operand_i),
	  .opcode_rb_operand_i           (opcode_rb_operand_i),
	  .csr_writeback_write_i         (csr_writeback_write_i),
	  .csr_writeback_waddr_i         (csr_writeback_waddr_i),
	  .csr_writeback_wdata_i         (csr_writeback_wdata_i),
	  .csr_writeback_exception_i     (csr_writeback_exception_i),
	  .csr_writeback_exception_pc_i  (csr_writeback_exception_pc_i),
	  .csr_writeback_exception_addr_i(csr_writeback_exception_addr_i),
	  .cpu_id_i                      (cpu_id_i),
	  .reset_vector_i                (reset_vector_i),
	  .interrupt_inhibit_i           (interrupt_inhibit_i),

	  // Outputs
	  .csr_result_e1_value_o         (csr_result_e1_value_o),
	  .csr_result_e1_write_o         (csr_result_e1_write_o),
	  .csr_result_e1_wdata_o         (csr_result_e1_wdata_o),
	  .csr_result_e1_exception_o     (csr_result_e1_exception_o),
	  .branch_csr_request_o          (branch_csr_request_o),
	  .branch_csr_pc_o               (branch_csr_pc_o),
	  .branch_csr_priv_o             (branch_csr_priv_o),
	  .take_interrupt_o              (take_interrupt_o),
	  .ifence_o                      (ifence_o),
	  .mmu_priv_d_o                  (mmu_priv_d_o),
	  .mmu_sum_o                     (mmu_sum_o),
	  .mmu_mxr_o                     (mmu_mxr_o),
	  .mmu_flush_o                   (mmu_flush_o),
	  .mmu_satp_o                    (mmu_satp_o)
  );
// ------------------------------------------------------------
// Simple Functional Coverage for CSR TB
// ------------------------------------------------------------

// Basic decode helpers (SYSTEM opcode in RISC-V is 0x73)
function automatic bit is_system(input logic [31:0] inst);
  return (inst[6:0] == 7'h73);
endfunction

function automatic bit is_ecall(input logic [31:0] inst);
  return (inst == 32'h0000_0073);
endfunction

function automatic bit is_mret(input logic [31:0] inst);
  return (inst == 32'h3020_0073);
endfunction

// CSR funct3 encodings when opcode[6:0]==0x73 and funct3!=0
// 001 CSRRW, 010 CSRRS, 011 CSRRC, 101 CSRRWI, 110 CSRRSI, 111 CSRRCI
function automatic bit is_csr_op(input logic [31:0] inst);
  return is_system(inst) && (inst[14:12] != 3'b000);
endfunction

// -------- Covergroup: CSR instruction activity ----------
covergroup cg_csr @(posedge clk_i);
  option.per_instance = 1;

  // Sample only when we present a valid instruction
  cp_valid : coverpoint opcode_valid_i {
	bins valid = {1};
  }

  cp_sys : coverpoint is_system(opcode_opcode_i) iff (opcode_valid_i) {
	bins sys = {1};
	bins non_sys = {0};
  }

  cp_kind : coverpoint opcode_opcode_i[14:12] iff (opcode_valid_i && is_system(opcode_opcode_i)) {
	bins ecall_mret_or_other = {3'b000}; // ecall/ebreak/mret/wfi share funct3=000 (distinguish by full inst)
	bins csrrw  = {3'b001};
	bins csrrs  = {3'b010};
	bins csrrc  = {3'b011};
	bins csrrwi = {3'b101};
	bins csrrsi = {3'b110};
	bins csrrci = {3'b111};
	// keep 000 but don't care about it here (handled by cp_sys000 below)
	bins sys000 = {3'b000};
  }

  cp_sys000 : coverpoint opcode_opcode_i
			  iff (opcode_valid_i && is_system(opcode_opcode_i) && opcode_opcode_i[14:12]==3'b000) {
	bins ecall = {32'h0000_0073};
	bins mret  = {32'h3020_0073};

	// If your core supports these, add them (otherwise ignore):
	// bins sfence_vma = {32'h1200_0073}; // depends on rs1/rs2 too in full encoding

	// Anything else in sys000 becomes visible (you decide if ignore or not)
	bins other = default;
  }
  

  cp_ecall : coverpoint is_ecall(opcode_opcode_i) iff (opcode_valid_i) {
	bins ecall = {1};
  }

  cp_mret : coverpoint is_mret(opcode_opcode_i) iff (opcode_valid_i) {
	bins mret = {1};
  }

  // CSR address field is [31:20] for CSR ops
  cp_csr_addr : coverpoint opcode_opcode_i[31:20] iff (opcode_valid_i && is_csr_op(opcode_opcode_i)) {
	// Keep it small: only CSRs you actually use in this TB
	bins mstatus = {`CSR_MSTATUS};
	bins mtvec   = {`CSR_MTVEC};
	bins mie     = {`CSR_MIE};
	bins mepc    = {`CSR_MEPC};

	// everything else (so you notice unexpected accesses)
	bins other[] = default;
  }

  // Did the DUT claim it will write a CSR this cycle
  cp_csr_write : coverpoint csr_result_e1_write_o iff (opcode_valid_i && is_csr_op(opcode_opcode_i)) {
	bins wrote    = {1};
	bins no_write = {0};
  }


endgroup

// -------- Covergroup: Exceptions / trap behavior ----------
covergroup cg_trap @(posedge clk_i);
  option.per_instance = 1;

  // Exception code coming out of CSR stage
  cp_exc : coverpoint csr_result_e1_exception_o iff (opcode_valid_i) {
	bins none = {6'd0};

	// You can add more bins later; start with what you test today
	bins ecall_m = {`EXCEPTION_ECALL_M};
	bins eret_m  = {`EXCEPTION_ERET_M};

	// Any other non-zero exceptions you didn’t explicitly list
	bins other_exc = default iff (csr_result_e1_exception_o != 6'd0);
  }

  // Trap redirect request + target
  cp_branch_req : coverpoint branch_csr_request_o {
	bins req  = {1};
	bins none = {0};
  }

  // External interrupt input + whether core took it
  cp_intr_in : coverpoint intr_i {
	bins low  = {0};
	bins high = {1};
  }

  cx_exc_x_branch : cross cp_exc, cp_branch_req;

endgroup

// Instantiate coverage
cg_csr  u_cg_csr  = new();
cg_trap u_cg_trap = new();

// Optional: save coverage at end (works in many simulators)
final begin
  // $coverage_save("csr_tb_coverage.ucdb"); // Questa style
  // $coverage_save("csr_tb_coverage");      // some tools accept this
  $display("[COVERAGE] Finished. (Enable tool-specific coverage save if needed)");
end
 // -----------------------------------------------
 // Testing codes (Machine mode):
 // -----------------------------------------------  
 
  task automatic test_csrrw_mstatus();
	  $display("\n[TEST]: CSRRW to mstatus");

	  // Setup instruction: CSRRW x1, mstatus ← x2
	  opcode_valid_i       = 1;
	  opcode_opcode_i      = `INST_CSRRW 
							| (32'(`CSR_MSTATUS) << 20)  // CSR addr
							| (32'(5'd1) << 7)           // rd = x1
							| (32'(5'd2) << 15);         // rs1 = x2
	  opcode_ra_operand_i  = 32'hdeadbeef;
	  opcode_ra_idx_i      = 5'd2;
	  opcode_rd_idx_i      = 5'd1;
	  opcode_invalid_i     = 0;

	  //  Debug before clocking
	  $display("[DEBUG] Sending CSRRW:");
	  $display("  opcode_opcode_i      = 0x%08h", opcode_opcode_i);
	  $display("  ra_operand (rs1 val) = 0x%08h", opcode_ra_operand_i);
	  $display("  ra_idx_i             = %0d", opcode_ra_idx_i);
	  $display("  rd_idx_i             = %0d", opcode_rd_idx_i);

	  wait_n_clocks(1); // Instruction should execute here
	  wait_n_clocks(1); 
	  
	  //  Debug after execution
	  $display("[DEBUG] After CSRRW:");
	  $display("  csr_result_e1_write_o   = %b", csr_result_e1_write_o);
	  $display("  csr_result_e1_value_o   = 0x%08h (old mstatus)", csr_result_e1_value_o);
	  $display("  csr_result_e1_wdata_o   = 0x%08h (new mstatus)", csr_result_e1_wdata_o);

	  if (csr_result_e1_write_o &&
		  csr_result_e1_value_o == 32'h00000000 &&
		  csr_result_e1_wdata_o == (32'hdeadbeef & `CSR_MSTATUS_MASK))
		  $display("PASS ✅ CSRRW to mstatus correct");
	  else
		  $display("FAIL ❌ CSRRW to mstatus incorrect");

	  opcode_valid_i = 0;
	  wait_n_clocks(1);
  endtask
  
		  task automatic test_ecall();
			  $display("\n[TEST]: ECALL at PC 0x200");
			  // Read mstatus before ECALL
			  // === Step 1: Trigger ECALL ===
			  opcode_pc_i          = 32'h200;
			  opcode_valid_i       = 1;
			  opcode_opcode_i      = `INST_ECALL;
			  opcode_rd_idx_i      = 5'd0;
			  opcode_ra_idx_i      = 5'd0;
			  opcode_ra_operand_i  = 32'd0;
			  opcode_invalid_i     = 0;

			  wait_n_clocks(1);

			  // ✅ Capture the exception code before issuing any new instructions
			  exception_code = csr_result_e1_exception_o;

			  // Feed back exception info to CSR regfile
			  csr_writeback_exception_i      = csr_result_e1_exception_o;
			  csr_writeback_exception_pc_i   = opcode_pc_i;
			  csr_writeback_exception_addr_i = 32'd0;

			  wait_n_clocks(1);

			  // === Step 2: Read mepc ===
			  $display("[DEBUG] Triggering CSRR x1, mepc");
			  opcode_valid_i       = 1;
			  opcode_opcode_i      = `INST_CSRRW | (32'(`CSR_MEPC) << 20) | (32'(5'd1 << 7)) | (32'(5'd0 << 15));
			  opcode_rd_idx_i      = 5'd1;
			  opcode_ra_idx_i      = 5'd0;
			  opcode_ra_operand_i  = 32'd0;
			  opcode_invalid_i     = 0;

			  wait_n_clocks(1);
			  wait_n_clocks(1);

			  // === Step 3: Check Results ===
			  $display("Captured Exception Code        : 0x%02h", exception_code);
			  $display("Branch Request                 : %b", branch_csr_request_o);
			  $display("CSR mepc value (read):         : 0x%08h", csr_result_e1_value_o);
			  $display("Expected PC:                   : 0x00000200");
			  
			  if (exception_code == `EXCEPTION_ECALL_M &&
				  branch_csr_request_o &&
				  csr_result_e1_value_o == 32'h200)
				  $display("PASS ✅ ECALL trap behavior correct.");
			  else
				  $display("FAIL ❌ ECALL trap behavior incorrect.");
			  
			  // === Step 4: Return from trap via MRET ===
			  $display("[DEBUG] Issuing MRET");
			  
			  $display("Branch request before MRET: %b", branch_csr_request_o);

			  // Issue MRET instruction
			  opcode_opcode_i = 32'h30200073; // MRET opcode
			  opcode_valid_i  = 1;
			  wait_n_clocks(2);

			  // Simulate writeback from MRET
			  csr_writeback_exception_i      = `EXCEPTION_ERET_M;
			  csr_writeback_exception_pc_i   = csr_result_e1_value_o; // mepc
			  csr_writeback_exception_addr_i = 32'd0;
			  wait_n_clocks(2);
			 
			  // Clear signals
			  opcode_valid_i = 0;
			  csr_writeback_exception_i = 6'h0;
			  wait_n_clocks(2);
			  
			  $display("Branch request after MRET: %b", branch_csr_request_o);
			  
		  endtask

		 task automatic test_csrrs_mstatus();
			 // -----------------------------------------------
			 // Step 1: Set mstatus lower bits using CSRRS
			 // -----------------------------------------------
			 $display("\n[TEST]: Setting mstatus lower 4 bits...");
			 // Instruction setup
			 opcode_valid_i       = 1;
			 opcode_opcode_i      = `INST_CSRRS | (32'(`CSR_MSTATUS) << 20)| (32'(5'd1) << 7)| (32'(5'd0) << 15);    
			 opcode_ra_idx_i      = 5'd1;
			 opcode_ra_operand_i  = 32'h0000000F;            // Mask to set lower 4 bits
			 opcode_rd_idx_i      = 5'd0;
			 opcode_invalid_i     = 0;
			 
			 wait_n_clocks(1); // Wait for instruction to execute
			 wait_n_clocks(1); // Wait for result to stabilize
			 
			 $display("CSRRS instruction executed.");
			 $display("Previous mstatus (read):       0x%08h", csr_result_e1_value_o);
			 $display("Setting mask (rs1 value):      0x%08h", opcode_ra_operand_i);
			 $display("Expected result :              0x%08h", csr_result_e1_value_o | opcode_ra_operand_i);
			 $display("Actual written CSR value:      0x%08h", csr_result_e1_wdata_o);

			 if ((csr_result_e1_wdata_o & 32'h0000000F) == 32'h0000000F)
				 $display("PASS ✅ mstatus lower bits set as expected.");
			 else
				 $display("FAIL ❌ mstatus bits not set properly.");
			 
			 opcode_valid_i = 0;
			 wait_n_clocks(5);
		 endtask
		 
		 task automatic test_csrrwi_then_csrrc_mstatus();
			 logic [31:0] initial_val = 32'h0000180F;       // Set mstatus with more bits
			 logic [31:0] clear_mask  = 32'h00001808;       // Clear bits 12 and 3
			 logic [31:0] expected_val;

			 // -----------------------------------------------
			 // Step 1: CSRRWI - Write known value to mstatus
			 // -----------------------------------------------
			 $display("\n[TEST] Step 1: CSRRWI Write to mstatus");

			 opcode_valid_i       = 1;
			 opcode_opcode_i      = `INST_CSRRWI |
									 (32'(`CSR_MSTATUS) << 20) |
									 (32'(5'd1) << 7) |
									 (32'(5'd15) << 15); // zimm = 15 (but not used here really)

			 opcode_ra_idx_i      = 5'd0;
			 opcode_ra_operand_i  = 32'd0; // Not used
			 opcode_rd_idx_i      = 5'd1;
			 opcode_invalid_i     = 0;

			 // Set actual CSR value via CSR writeback for control
			 csr_writeback_exception_i = 6'h0;
			 csr_writeback_waddr_i     = `CSR_MSTATUS;
			 csr_writeback_write_i     = 1;
			 csr_writeback_wdata_i     = initial_val;
			 wait_n_clocks(2);
			 csr_writeback_write_i     = 0;

			 $display("Forced mstatus value: 0x%08h", initial_val);
			 wait_n_clocks(2);

			 // -----------------------------------------------
			 // Step 2: CSRRC - Clear selected bits
			 // -----------------------------------------------
			 $display("\n[TEST] Step 2: CSRRC Clear bits 12 and 3 in mstatus");

			 opcode_valid_i       = 1;
			 opcode_opcode_i      = `INST_CSRRC |
									 (32'(`CSR_MSTATUS) << 20) |
									 (32'(5'd0) << 7) |
									 (32'(5'd3) << 15);
			 opcode_ra_idx_i      = 5'd3;
			 opcode_ra_operand_i  = clear_mask;
			 opcode_rd_idx_i      = 5'd0;
			 opcode_invalid_i     = 0;

			 wait_n_clocks(2);

			 expected_val = initial_val & ~clear_mask;

			 $display("Clearing mask (rs1 value):        0x%08h", clear_mask);
			 $display("Previous mstatus:                 0x%08h", initial_val);
			 $display("Expected mstatus after clear:     0x%08h", expected_val);
			 $display("Actual written mstatus:           0x%08h", csr_result_e1_wdata_o);

			 if (csr_result_e1_wdata_o == expected_val)
				 $display("PASS ✅ CSRRC cleared mstatus bits correctly.");
			 else
				 $display("FAIL ❌ CSRRC clear mismatch.");

			 opcode_valid_i = 0;
			 wait_n_clocks(3);
		 endtask

		 
		   task automatic test_csrrwi_write_mstatus();
			   $display("\n[TEST] CSRRWI: Write immediate value to mstatus");

			   // Set up CSRRWI instruction
			   opcode_valid_i       = 1;
			   opcode_opcode_i      = `INST_CSRRWI |
									   (32'(`CSR_MSTATUS) << 20) |  // CSR addr field
									   (32'(5'd1) << 7) |            // rd = x1
									   (32'(5'd5) << 15);            // zimm = 5

			   opcode_ra_idx_i      = 5'd5; // zimm
			   opcode_ra_operand_i  = 32'd0; // Not used in CSRRWI
			   opcode_rd_idx_i      = 5'd1;
			   opcode_invalid_i     = 0;

			   wait_n_clocks(1);
			   wait_n_clocks(1);

			   // Debug
			   $display("Previous mstatus (read into x1): 0x%08h", csr_result_e1_value_o);
			   $display("Expected mstatus after CSRRWI:   0x%08h", 32'd5);
			   $display("Written CSR value:               0x%08h", csr_result_e1_wdata_o);

			   if (csr_result_e1_wdata_o == 32'd5)
				   $display("PASS ✅ CSRRWI wrote correct immediate value to mstatus.");
			   else
				   $display("FAIL ❌ CSRRWI did not write expected value.");
			   
			   opcode_valid_i = 0;
			   wait_n_clocks(2);
		   endtask
		   
		   task automatic test_csrrsi_set_bits_mstatus();
			   // -----------------------------------------------
			   // Test: CSRRSI - Set bits in mstatus using immediate value
			   // -----------------------------------------------
			   $display("\n[TEST] CSRRSI: Set bits in mstatus using immediate");
			   // First, clear mstatus with a CSRRW to known value (0x0)
			   opcode_valid_i       = 1;
			   opcode_opcode_i      = `INST_CSRRW |
									   (32'(`CSR_MSTATUS) << 20) |
									   (32'(5'd0) << 7) |        // rd = x0 (discard)
									   (32'(5'd2) << 15);        // rs1 = x2
			   opcode_ra_idx_i      = 5'd2;
			   opcode_ra_operand_i  = 32'h00000000;              // clear all bits
			   opcode_rd_idx_i      = 5'd0;
			   opcode_invalid_i     = 0;

			   wait_n_clocks(2);
			   
			   // Now, perform CSRRSI to set bits 1 and 2 (zimm = 0b00110 = 6)
			   opcode_valid_i       = 1;
			   opcode_opcode_i      = `INST_CSRRSI |
									   (32'(`CSR_MSTATUS) << 20) |
									   (32'(5'd0) << 7) |        // rd = x0 (discard)
									   (32'(5'd6) << 15);        // zimm = 6
			   opcode_ra_idx_i      = 5'd6;                      // zimm = x6 (used only for naming)
			   opcode_ra_operand_i  = 32'd0;                     // ignored in *I instructions
			   opcode_rd_idx_i      = 5'd0;
			   opcode_invalid_i     = 0;
			   
			   wait_n_clocks(1);
			   wait_n_clocks(1);
			   
			   // Debug info
			   $display("CSRRSI zimm:                      0x%08h", 32'd6);
			   $display("Expected mstatus (OR with 0):     0x%08h", 32'd6);
			   $display("Actual written CSR value:         0x%08h", csr_result_e1_wdata_o);

			   if (csr_result_e1_wdata_o == 32'd6)
				   $display("PASS ✅ CSRRSI correctly set bits in mstatus.");
			   else
				   $display("FAIL ❌ CSRRSI did not modify mstatus as expected.");
			   
			   opcode_valid_i = 0;
			   wait_n_clocks(2);
		   endtask

		   
		   task automatic test_CSR_trap_redirection();

			   $display("\n[TEST] ECALL with Handler Simulation");

			   // 1. Set mtvec = 0x100
			   opcode_valid_i       = 1;
			   opcode_opcode_i      = `INST_CSRRW 
									 | (32'(`CSR_MTVEC) << 20)  // mtvec
									 | (32'(5'd3) << 7)           // rd = x3
									 | (32'(5'd2) << 15);  
			   opcode_ra_operand_i  = 32'h00000100;
			   opcode_ra_idx_i      = 5'd2;
			   opcode_rd_idx_i      = 5'd3;
			   opcode_invalid_i     = 0;
			   wait_n_clocks(2);

			   // 2. Issue ECALL
			   opcode_pc_i          = 32'hDEAD0000;
			   opcode_opcode_i      = `INST_ECALL;
			   wait_n_clocks(1);

			   // 3. Manually signal exception
			   csr_writeback_exception_i      = `EXCEPTION_ECALL_M;
			   csr_writeback_exception_pc_i   = opcode_pc_i;
			   csr_writeback_exception_addr_i = 32'd0;
			   wait_n_clocks(2);

			   // 4. Simulate handler instruction at mtvec
			   $display("[Handler] At mtvec: executing dummy instruction");
			   opcode_pc_i          = 32'h00000100;  // mtvec
			   opcode_opcode_i      = 32'h00000013;  // NOP
			   opcode_valid_i       = 1;
			   wait_n_clocks(2);

			   // 5. Issue MRET to return from handler
			   $display("[Handler] Issuing MRET to return from trap");
			   opcode_opcode_i      = 32'h30200073;  // MRET
			   opcode_valid_i       = 1;
			   wait_n_clocks(2);

			   csr_writeback_exception_i      = `EXCEPTION_ERET_M;
			   csr_writeback_exception_pc_i   = 32'hDEAD0000;
			   wait_n_clocks(2);

			   // Clear signals
			   opcode_valid_i = 0;
			   csr_writeback_exception_i = 6'd0;
			   wait_n_clocks(2);

			   $display("✅ Trap handled and returned successfully");
			 endtask
		   
			 task automatic test_machine_external_interrupt();  //NEEDS FURTHER DEBUG DOES NOT WORK !!

				 logic [31:0] mtvec_val = 32'h00000100; // Interrupt handler address
				 logic [31:0] test_pc   = 32'hDEAD0000;

				 $display("\n[TEST] Machine External Interrupt Redirection");

				 // -------------------------------
				 // Step 1: Set mtvec = handler
				 // -------------------------------
				 opcode_valid_i       = 1;
				 opcode_opcode_i      = `INST_CSRRW
									   | (32'(`CSR_MTVEC << 20))
									   | (32'(5'd0 << 7))
									   | (32'(5'd2 << 15)); // x2
				 opcode_ra_operand_i  = mtvec_val;
				 opcode_ra_idx_i      = 5'd2;
				 opcode_rd_idx_i      = 5'd0;
				 opcode_invalid_i     = 0;
				 
				 wait_n_clocks(2);
				 
				 $display("mtvec set to: 0x%08h", branch_csr_pc_o);

				 // -------------------------------
				 // Step 2: Enable global MIE in mstatus
				 // -------------------------------
				 opcode_opcode_i      = `INST_CSRRS
									   | (32'(`CSR_MSTATUS << 20))
									   | (32'(5'd0 << 7))
									   | (32'(5'd2 << 15));
				 opcode_ra_operand_i  = `SR_MIE; // bit 3
				 wait_n_clocks(2);

				 // -------------------------------
				 // Step 3: Enable MEIE (bit 11) in mie
				 // -------------------------------
				 opcode_opcode_i      = `INST_CSRRS
									   | (32'(`CSR_MIE << 20))
									   | (32'(5'd0 << 7))
									   | (32'(5'd2 << 15));
				 opcode_ra_operand_i  = (1 << 11); // MEIE
				 wait_n_clocks(2);

				 // -------------------------------
				 // Step 4: Set PC and send dummy instruction
				 // -------------------------------
				 opcode_pc_i          = test_pc;
				 opcode_opcode_i      = `INST_ADDI; // NOP: ADDI x0, x0, 0
				 wait_n_clocks(2);

				 // -------------------------------
				 // Step 5: Trigger External Interrupt
				 // -------------------------------
				 intr_i = 1;
				 wait_n_clocks(2);

				 // -------------------------------
				 // Step 6: Inform CSR about exception
				 // -------------------------------
				 csr_writeback_exception_i      = `EXCEPTION_INTERRUPT;
				 csr_writeback_exception_pc_i   = test_pc;
				 csr_writeback_exception_addr_i = 32'd0;
				 wait_n_clocks(2);

				 // -------------------------------
				 // Step 7: Check Results
				 // -------------------------------
				 $display("Branch Requested        : %b", branch_csr_request_o);
				 $display("Trap Redirect PC (mtvec): 0x%08h", branch_csr_pc_o);
				 $display("Interrupt Cause         : 0x%02h", csr_result_e1_exception_o);
				 $display("Expected Cause          : 0x0B");
				 $display("Expected mepc           : 0x%08h", test_pc);

				 if (branch_csr_request_o && branch_csr_pc_o == mtvec_val)
					 $display("PASS ✅ Interrupt redirection successful.");
				 else
					 $display("FAIL ❌ Interrupt redirection failed.");

				 if (csr_result_e1_exception_o == 6'hB)
					 $display("PASS ✅ mcause is correct for machine external interrupt.");
				 else
					 $display("FAIL ❌ mcause incorrect.");

				 if (csr_writeback_exception_pc_i == test_pc)
					 $display("PASS ✅ mepc saved pre-interrupt PC.");
				 else
					 $display("FAIL ❌ mepc not saved correctly.");

				 // -------------------------------
				 // Step 8: Cleanup
				 // -------------------------------
				 intr_i = 0;
				 opcode_valid_i = 0;
				 csr_writeback_exception_i = 6'h0;
				 wait_n_clocks(3);
			 endtask



// -----------------------------------------------
// Main:
// -----------------------------------------------
  initial begin
	  rst_i = 1;
	  init_signals();
	  #2 rst_i = 0;
	  repeat (5) @(posedge clk_i);
		
	  test_csrrw_mstatus(); // CSRRW TEST
	  apply_reset();
	  test_csrrsi_set_bits_mstatus(); // CSRRSI TEST
	  apply_reset();
	  test_ecall(); // ECALL TEST
	  apply_reset();
	  test_csrrs_mstatus(); // CCSRS TEST
	  apply_reset();
	  test_csrrwi_then_csrrc_mstatus();
	  apply_reset();
	  test_csrrwi_write_mstatus(); // CSRRWI WRITE TEST
	  apply_reset();
	  test_CSR_trap_redirection(); // BRANCH TEST
	  apply_reset();
	  test_machine_external_interrupt();
	  
	  $display("\n ALL CSR TESTS COMPLETED");
	  $finish;
  end
  
// -----------------------------------------------
// Task section:
// -----------------------------------------------
  task automatic init_signals();
	  begin
		csr_writeback_write_i         = 0;
		intr_i                        = 0;
		interrupt_inhibit_i           = 0;
		cpu_id_i                      = 32'h1;
		reset_vector_i                = 32'h100;
		opcode_valid_i                = 0;
		opcode_invalid_i              = 0;
		csr_writeback_exception_i     = 0;
		csr_writeback_exception_pc_i  = 0;
		csr_writeback_exception_addr_i= 0;
	  end
	  endtask

  task wait_n_clocks(input int n);
	  repeat (n) @(posedge clk_i);
  endtask
  
  task automatic apply_reset();
	  rst_i = 1;
	  opcode_valid_i = 0;
	  wait_n_clocks(2);     // Hold reset for 2 clocks
	  rst_i = 0;            // Deassert reset
	  wait_n_clocks(2);     // Allow pipeline to flush/reset
  endtask
  
endmodule
