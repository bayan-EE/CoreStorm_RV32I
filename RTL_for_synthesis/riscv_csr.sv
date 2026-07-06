module riscv_csr
//-----------------------------------------------------------------
// Parameters
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MULDIV   = 1 // Enable MUL/DIV-related CSRs and logic
    ,parameter SUPPORT_SUPER    = 0 // Enable Supervisor mode (S-mode, MMU, satp)
	,parameter XLEN = 32  // Register width (RV32)
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // -Inputs-
	// Clock / Reset
     input           clk_i
    ,input           rst_i 
	// Interrupts
    ,input           intr_i
	// Instruction interface (from pipeline)
    ,input           opcode_valid_i
    ,input  [XLEN-1:0]  opcode_opcode_i
    ,input  [XLEN-1:0]  opcode_pc_i
    ,input           opcode_invalid_i
    ,input  [4:0]  opcode_rd_idx_i
    ,input  [4:0]  opcode_ra_idx_i
    ,input  [4:0]  opcode_rb_idx_i
    ,input  [XLEN-1:0]  opcode_ra_operand_i  
    ,input  [XLEN-1:0]  opcode_rb_operand_i 
	// Writeback feedback (from WB stage)    
	,input           csr_writeback_write_i
    ,input  [11:0]   csr_writeback_waddr_i
    ,input  [XLEN-1:0]  csr_writeback_wdata_i
    ,input  [5:0]  csr_writeback_exception_i
    ,input  [XLEN-1:0]  csr_writeback_exception_pc_i
    ,input  [XLEN-1:0]  csr_writeback_exception_addr_i
	// Core identification / boot
    ,input  [XLEN-1:0]  cpu_id_i
    ,input  [XLEN-1:0]  reset_vector_i
    ,input           interrupt_inhibit_i

    // -Outputs-
	// CSR execution results (to EX stage)
    ,output [XLEN-1:0]  csr_result_e1_value_o
    ,output          csr_result_e1_write_o
    ,output [XLEN-1:0]  csr_result_e1_wdata_o
    ,output [5:0]  csr_result_e1_exception_o
	// Control-flow redirection
    ,output          branch_csr_request_o
    ,output [XLEN-1:0]  branch_csr_pc_o
    ,output [1:0]  branch_csr_priv_o
	// Interrupt handling
    ,output          take_interrupt_o
	// Fence / cache control
    ,output          ifence_o
	// MMU / privilege outputs
    ,output [1:0]  mmu_priv_d_o
    ,output          mmu_sum_o
    ,output          mmu_mxr_o
    ,output          mmu_flush_o
    ,output [XLEN-1:0] mmu_satp_o
);

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/data.cc/data/a/home/cc/students/enginer/yazanatamna/corestorm_ref/corestorm_ref_2/riscv_defs.sv"

//-----------------------------------------------------------------
// Registers / Wires
//-----------------------------------------------------------------
wire ecall_w      = opcode_valid_i && ((opcode_opcode_i & `INST_ECALL_MASK ) == `INST_ECALL ); // Detect ECALL instruction
wire ebreak_w     = opcode_valid_i && ((opcode_opcode_i & `INST_EBREAK_MASK) == `INST_EBREAK); // Detect EBREAK instruction
wire eret_w       = opcode_valid_i && ((opcode_opcode_i & `INST_ERET_MASK  ) == `INST_ERET  ); // Detect xRET instruction (mret / sret / uret)
wire [1:0] eret_priv_w  = opcode_opcode_i[29:28];

wire csrrw_w      = opcode_valid_i && ((opcode_opcode_i & `INST_CSRRW_MASK ) == `INST_CSRRW ); // Detect CSRRW instruction
wire csrrs_w      = opcode_valid_i && ((opcode_opcode_i & `INST_CSRRS_MASK ) == `INST_CSRRS ); // Detect CSRRS instruction
wire csrrc_w      = opcode_valid_i && ((opcode_opcode_i & `INST_CSRRC_MASK ) == `INST_CSRRC ); // Detect CSRRC instruction
wire csrrwi_w     = opcode_valid_i && ((opcode_opcode_i & `INST_CSRRWI_MASK) == `INST_CSRRWI); // Detect CSRRWI instruction (immediate)
wire csrrsi_w     = opcode_valid_i && ((opcode_opcode_i & `INST_CSRRSI_MASK) == `INST_CSRRSI); // Detect CSRRSI instruction (immediate)
wire csrrci_w     = opcode_valid_i && ((opcode_opcode_i & `INST_CSRRCI_MASK) == `INST_CSRRCI); // Detect CSRRCI instruction (immediate)

wire wfi_w        = opcode_valid_i && ((opcode_opcode_i & `INST_WFI_MASK   ) == `INST_WFI   ); // Detect WFI instruction (halt until interrupt)
wire fence_w      = opcode_valid_i && ((opcode_opcode_i & `INST_FENCE_MASK ) == `INST_FENCE ); // Detect FENCE instruction (memory ordering barrier)
wire sfence_w     = opcode_valid_i && ((opcode_opcode_i & `INST_SFENCE_MASK) == `INST_SFENCE); // Detect SFENCE.VMA instruction (flush TLB entries)
wire ifence_w     = opcode_valid_i && ((opcode_opcode_i & `INST_IFENCE_MASK) == `INST_IFENCE); // Detect FENCE.I instruction (flush instruction cache / pipeline)

//-----------------------------------------------------------------
// CSR handling
//-----------------------------------------------------------------
wire [1:0]       current_priv_w;  // Current CPU privilege level (U/S/M)
reg [1:0]        csr_priv_r; // Required privilege level of accessed CSR
reg              csr_readonly_r; // CSR is read-only (writes not allowed)
reg              csr_write_r; // Instruction attempts to write CSR
reg              set_r; // CSR set operation requested
reg              clr_r; // CSR clear operation requested
reg              csr_fault_r; // Illegal CSR access detected
reg [XLEN-1:0]   data_r; // Data used for CSR modification

always_comb
begin
	set_r = csrrw_w | csrrs_w | csrrwi_w | csrrsi_w; // Detect CSR operations that set bits
	clr_r = csrrw_w | csrrc_w | csrrwi_w | csrrci_w;// Detect CSR operations that clear bits
	csr_priv_r = opcode_opcode_i[29:28]; // Extract required privilege level from CSR address field
	csr_readonly_r  = (opcode_opcode_i[31:30] == 2'd3); // CSR is read-only if top CSR address bits are 11
	csr_write_r = (opcode_ra_idx_i != 5'b0) | csrrw_w | csrrwi_w; // CSR write occurs if rs1 != x0 or instruction forces write
	data_r  = (csrrwi_w | csrrsi_w | csrrci_w) ?
					  {27'b0, opcode_ra_idx_i} : // Select CSR input data: immediate for *I forms, register otherwise
					  opcode_ra_operand_i;
	
	// Detect access fault on CSR access
	// - write to read-only CSR
	// - insufficient privilege level
	csr_fault_r     = SUPPORT_SUPER ? (opcode_valid_i && (set_r | clr_r) && ((csr_write_r && csr_readonly_r) || (current_priv_w < csr_priv_r))) : 1'b0;
end

// Detect write to SATP CSR (requires MMU / TLB flush)
wire satp_update_w = (opcode_valid_i && (set_r || clr_r) && csr_write_r && (opcode_opcode_i[31:20] == `CSR_SATP));

//-----------------------------------------------------------------
// CSR register file
//-----------------------------------------------------------------
wire timer_irq_w = 1'b0; // Timer interrupt signal (stubbed to 0 → no timer IRQ implemented yet)

wire [XLEN-1:0] misa_w = SUPPORT_MULDIV ? (`MISA_RV32 | `MISA_RVI | `MISA_RVM): (`MISA_RV32 | `MISA_RVI); // Value of MISA CSR: declares supported ISA extensions (RV32I, optional M)

wire [XLEN-1:0] csr_rdata_w; // Data read from CSR (result of CSR read instruction)

wire            csr_branch_w; // Indicates CSR caused a control-flow change (trap, interrupt, eret)
wire [XLEN-1:0] csr_target_w; // Target PC for CSR-related branch (e.g., mtvec or mepc)

wire [XLEN-1:0] interrupt_w; // Encoded interrupt cause vector
wire [XLEN-1:0] status_reg_w; // Combined status register output (e.g., mstatus)
wire [XLEN-1:0] satp_reg_w; // SATP register output (MMU configuration / page table base)

riscv_csr_regfile
#(
   .SUPPORT_MTIMECMP(1)              // Enable machine timer compare (mtime/mtimecmp)
  ,.SUPPORT_SUPER(SUPPORT_SUPER)     // Enable supervisor mode support (S-mode)
  ,.XLEN(XLEN)
)
u_csrfile
(
	// Clock / Reset
	 .clk_i(clk_i)                   // CPU clock
	,.rst_i(rst_i)                   // Global reset

	// Interrupt sources
	,.ext_intr_i(intr_i)             // External interrupt request
	,.timer_intr_i(timer_irq_w)      // Timer interrupt request
	,.cpu_id_i(cpu_id_i)             // Hart ID (for MHARTID CSR)
	,.misa_i(misa_w)                 // ISA feature bits (MISA CSR value)

	// CSR read (from decode / issue stage)
	,.csr_ren_i(opcode_valid_i)      // CSR read enable (valid instruction)
	,.csr_raddr_i(opcode_opcode_i[31:20]) // CSR address field from instruction
	,.csr_rdata_o(csr_rdata_w)       // CSR read data returned to pipeline

	// Exception reporting (from writeback stage)
	,.exception_i(csr_writeback_exception_i) // Exception cause code
	,.exception_pc_i(csr_writeback_exception_pc_i) // PC where exception occurred
	,.exception_addr_i(csr_writeback_exception_addr_i) // Faulting address (if any)

	// CSR writeback (from WB stage)
	,.csr_waddr_i(
		csr_writeback_write_i ? csr_writeback_waddr_i : 12'b0
	 )                               // CSR write address (0 disables write)
	,.csr_wdata_i(csr_writeback_wdata_i) // Data written to CSR

	// CSR-induced control flow
	,.csr_branch_o(csr_branch_w)     // CSR requests PC redirection
	,.csr_target_o(csr_target_w)     // Target PC (mtvec, mepc, etc.)

	// CSR state outputs
	,.priv_o(current_priv_w)         // Current privilege level (M/S/U)
	,.status_o(status_reg_w)         // Status register (mstatus view)
	,.satp_o(satp_reg_w)             // SATP register (MMU control)

	// Interrupt decision output
	,.interrupt_o(interrupt_w)       // Masked/qualified interrupt signal
);


//-----------------------------------------------------------------
// CSR Read Result (E1) / Early exceptions
//-----------------------------------------------------------------

reg                     rd_valid_e1_q;        // CSR writeback valid (E1 stage)
reg [XLEN-1:0]          rd_result_e1_q;       // Value returned to rd (CSR read result)
reg [XLEN-1:0]          csr_wdata_e1_q;       // Final data written into CSR
reg [`EXCEPTION_W-1:0]  exception_e1_q;       // Exception detected in E1 stage

// Inappropriate xRET for the current exec priv level
wire eret_fault_w = eret_w && (current_priv_w < eret_priv_w);
// True if executing MRET/SRET/URET from insufficient privilege

//-----------------------------------------------------------------
// Pipeline register (E1 stage) / Early exceptions
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
	rd_valid_e1_q   <= 1'b0;                  // Clear CSR write enable
	rd_result_e1_q  <= 32'b0;                 // Clear CSR read result
	csr_wdata_e1_q  <= 32'b0;                 // Clear CSR write data
	exception_e1_q  <= `EXCEPTION_W'b0;       // No exception
end
else if (opcode_valid_i)
begin
	// CSR instruction is valid and allowed
	rd_valid_e1_q <= (set_r || clr_r) && ~csr_fault_r;

	// If illegal instruction or CSR fault → save opcode into xtval
	if (opcode_invalid_i || csr_fault_r || eret_fault_w)
		rd_result_e1_q <= opcode_opcode_i;    // Used later as mtval
	else    
		rd_result_e1_q <= csr_rdata_w;        // Normal CSR read result

	//-----------------------------------------------------------------
	// Exception detection (priority order)
	//-----------------------------------------------------------------

	// ECALL → trap (cause depends on current privilege)
	if (ecall_w)
		exception_e1_q <= `EXCEPTION_ECALL + {4'b0, current_priv_w};

	// xRET from higher privilege than current → illegal
	else if (eret_fault_w)
		exception_e1_q <= `EXCEPTION_ILLEGAL_INSTRUCTION;

	// Valid xRET (MRET/SRET/URET)
	else if ((opcode_opcode_i & `INST_ERET_MASK) == `INST_ERET)
		exception_e1_q <= `EXCEPTION_ERET_U + {4'b0, eret_priv_w};

	// EBREAK instruction
	else if (ebreak_w)
		exception_e1_q <= `EXCEPTION_BREAKPOINT;

	// Invalid opcode or illegal CSR access
	else if (opcode_invalid_i || csr_fault_r)
		exception_e1_q <= `EXCEPTION_ILLEGAL_INSTRUCTION;

	// Fence or MMU changes → pipeline flush
	else if (satp_update_w || ifence_w || sfence_w)
		exception_e1_q <= `EXCEPTION_FENCE;

	// No exception
	else
		exception_e1_q <= `EXCEPTION_W'b0;

	//-----------------------------------------------------------------
	// CSR write data generation
	//-----------------------------------------------------------------

	if (set_r && clr_r)
		csr_wdata_e1_q <= data_r;              // CSRRW / CSRRWI
	else if (set_r)
		csr_wdata_e1_q <= csr_rdata_w | data_r;// CSRRS / CSRRSI
	else if (clr_r)
		csr_wdata_e1_q <= csr_rdata_w & ~data_r;// CSRRC / CSRRCI
end
else
begin
	// No valid instruction → clear E1 stage
	rd_valid_e1_q   <= 1'b0;
	rd_result_e1_q  <= 32'b0;
	csr_wdata_e1_q  <= 32'b0;
	exception_e1_q  <= `EXCEPTION_W'b0;
end

//-----------------------------------------------------------------
// Outputs to later pipeline stages
//-----------------------------------------------------------------
assign csr_result_e1_value_o     = rd_result_e1_q;   // Value written to rd
assign csr_result_e1_write_o     = rd_valid_e1_q;    // Enable CSR writeback
assign csr_result_e1_wdata_o     = csr_wdata_e1_q;   // Data written to CSR
assign csr_result_e1_exception_o = exception_e1_q;   // Exception cause

//-----------------------------------------------------------------
// Interrupt launch enable
//-----------------------------------------------------------------
reg take_interrupt_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    take_interrupt_q    <= 1'b0;
else
    take_interrupt_q    <= (|interrupt_w) & ~interrupt_inhibit_i;

assign take_interrupt_o = take_interrupt_q;

//-----------------------------------------------------------------
// TLB flush
//-----------------------------------------------------------------
reg tlb_flush_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    tlb_flush_q <= 1'b0;
else
    tlb_flush_q <= satp_update_w || sfence_w;

//-----------------------------------------------------------------
// ifence
//-----------------------------------------------------------------
reg ifence_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    ifence_q    <= 1'b0;
else
    ifence_q    <= ifence_w;

assign ifence_o = ifence_q;

//-----------------------------------------------------------------
// Execute - Branch operations
//-----------------------------------------------------------------
reg        branch_q; // Should we redirect the PC this cycle?
reg [XLEN-1:0] branch_target_q; // What PC should we jump to?
reg        reset_q; // One-cycle flag used to handle reset redirection cleanly

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    branch_target_q <= 32'b0;
    branch_q        <= 1'b0;
    reset_q         <= 1'b1;
end
else if (reset_q)
begin
    branch_target_q <= reset_vector_i;
    branch_q        <= 1'b1;
    reset_q         <= 1'b0;
end
else
begin
    branch_q        <= csr_branch_w;
    branch_target_q <= csr_target_w;
end

assign branch_csr_request_o = branch_q;
assign branch_csr_pc_o      = branch_target_q;
assign branch_csr_priv_o    = satp_reg_w[`SATP_MODE_R] ? current_priv_w : `PRIV_MACHINE;

//-----------------------------------------------------------------
// MMU
//-----------------------------------------------------------------
assign mmu_priv_d_o     = status_reg_w[`SR_MPRV_R] ? status_reg_w[`SR_MPP_R] : current_priv_w;
assign mmu_satp_o       = satp_reg_w;
assign mmu_flush_o      = tlb_flush_q;
assign mmu_sum_o        = status_reg_w[`SR_SUM_R];
assign mmu_mxr_o        = status_reg_w[`SR_MXR_R];

endmodule
