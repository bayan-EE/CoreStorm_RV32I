

`timescale 1ns/1ps
module riscv_decoder (
	input  logic        valid_i,
	input  logic        fetch_fault_i,
	input  logic        enable_muldiv_i,
	input  logic [31:0] opcode_i,

	output logic        invalid_o,
	output logic        exec_o,
	output logic        lsu_o,
	output logic        branch_o,
	output logic        mul_o,
	output logic        div_o,
	output logic        csr_o,
	output logic        rd_valid_o
);

	// ------------------------------------------------------------------------
	// Internal signal
	// ------------------------------------------------------------------------
	// invalid_w is asserted when the instruction is valid but does not match
	// any supported opcode pattern.
	logic invalid_w;

	// ------------------------------------------------------------------------
	// Invalid instruction detection
	// ------------------------------------------------------------------------
	// If valid_i is high, then opcode_i must match one of the supported
	// instructions. Otherwise the instruction is marked as invalid.
	assign invalid_w =
		valid_i &&
		~(
			((opcode_i & `INST_ANDI_MASK)   == `INST_ANDI)   ||
			((opcode_i & `INST_ADDI_MASK)   == `INST_ADDI)   ||
			((opcode_i & `INST_SLTI_MASK)   == `INST_SLTI)   ||
			((opcode_i & `INST_SLTIU_MASK)  == `INST_SLTIU)  ||
			((opcode_i & `INST_ORI_MASK)    == `INST_ORI)    ||
			((opcode_i & `INST_XORI_MASK)   == `INST_XORI)   ||
			((opcode_i & `INST_SLLI_MASK)   == `INST_SLLI)   ||
			((opcode_i & `INST_SRLI_MASK)   == `INST_SRLI)   ||
			((opcode_i & `INST_SRAI_MASK)   == `INST_SRAI)   ||
			((opcode_i & `INST_LUI_MASK)    == `INST_LUI)    ||
			((opcode_i & `INST_AUIPC_MASK)  == `INST_AUIPC)  ||
			((opcode_i & `INST_ADD_MASK)    == `INST_ADD)    ||
			((opcode_i & `INST_SUB_MASK)    == `INST_SUB)    ||
			((opcode_i & `INST_SLT_MASK)    == `INST_SLT)    ||
			((opcode_i & `INST_SLTU_MASK)   == `INST_SLTU)   ||
			((opcode_i & `INST_XOR_MASK)    == `INST_XOR)    ||
			((opcode_i & `INST_OR_MASK)     == `INST_OR)     ||
			((opcode_i & `INST_AND_MASK)    == `INST_AND)    ||
			((opcode_i & `INST_SLL_MASK)    == `INST_SLL)    ||
			((opcode_i & `INST_SRL_MASK)    == `INST_SRL)    ||
			((opcode_i & `INST_SRA_MASK)    == `INST_SRA)    ||
			((opcode_i & `INST_JAL_MASK)    == `INST_JAL)    ||
			((opcode_i & `INST_JALR_MASK)   == `INST_JALR)   ||
			((opcode_i & `INST_BEQ_MASK)    == `INST_BEQ)    ||
			((opcode_i & `INST_BNE_MASK)    == `INST_BNE)    ||
			((opcode_i & `INST_BLT_MASK)    == `INST_BLT)    ||
			((opcode_i & `INST_BGE_MASK)    == `INST_BGE)    ||
			((opcode_i & `INST_BLTU_MASK)   == `INST_BLTU)   ||
			((opcode_i & `INST_BGEU_MASK)   == `INST_BGEU)   ||
			((opcode_i & `INST_LB_MASK)     == `INST_LB)     ||
			((opcode_i & `INST_LH_MASK)     == `INST_LH)     ||
			((opcode_i & `INST_LW_MASK)     == `INST_LW)     ||
			((opcode_i & `INST_LBU_MASK)    == `INST_LBU)    ||
			((opcode_i & `INST_LHU_MASK)    == `INST_LHU)    ||
			((opcode_i & `INST_LWU_MASK)    == `INST_LWU)    ||
			((opcode_i & `INST_SB_MASK)     == `INST_SB)     ||
			((opcode_i & `INST_SH_MASK)     == `INST_SH)     ||
			((opcode_i & `INST_SW_MASK)     == `INST_SW)     ||
			((opcode_i & `INST_ECALL_MASK)  == `INST_ECALL)  ||
			((opcode_i & `INST_EBREAK_MASK) == `INST_EBREAK) ||
			((opcode_i & `INST_ERET_MASK)   == `INST_ERET)   ||
			((opcode_i & `INST_CSRRW_MASK)  == `INST_CSRRW)  ||
			((opcode_i & `INST_CSRRS_MASK)  == `INST_CSRRS)  ||
			((opcode_i & `INST_CSRRC_MASK)  == `INST_CSRRC)  ||
			((opcode_i & `INST_CSRRWI_MASK) == `INST_CSRRWI) ||
			((opcode_i & `INST_CSRRSI_MASK) == `INST_CSRRSI) ||
			((opcode_i & `INST_CSRRCI_MASK) == `INST_CSRRCI) ||
			((opcode_i & `INST_WFI_MASK)    == `INST_WFI)    ||
			((opcode_i & `INST_FENCE_MASK)  == `INST_FENCE)  ||
			((opcode_i & `INST_IFENCE_MASK) == `INST_IFENCE) ||
			((opcode_i & `INST_SFENCE_MASK) == `INST_SFENCE) ||

			// M-extension instructions are only valid when enable_muldiv_i=1
			(enable_muldiv_i && ((opcode_i & `INST_MUL_MASK)    == `INST_MUL))    ||
			(enable_muldiv_i && ((opcode_i & `INST_MULH_MASK)   == `INST_MULH))   ||
			(enable_muldiv_i && ((opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU)) ||
			(enable_muldiv_i && ((opcode_i & `INST_MULHU_MASK)  == `INST_MULHU))  ||
			(enable_muldiv_i && ((opcode_i & `INST_DIV_MASK)    == `INST_DIV))    ||
			(enable_muldiv_i && ((opcode_i & `INST_DIVU_MASK)   == `INST_DIVU))   ||
			(enable_muldiv_i && ((opcode_i & `INST_REM_MASK)    == `INST_REM))    ||
			(enable_muldiv_i && ((opcode_i & `INST_REMU_MASK)   == `INST_REMU))
		);

	assign invalid_o = invalid_w;

	// ------------------------------------------------------------------------
	// Destination register write enable
	// ------------------------------------------------------------------------
	// rd_valid_o is asserted for instructions that write back to rd.
	assign rd_valid_o =
		((opcode_i & `INST_JALR_MASK)   == `INST_JALR)   ||
		((opcode_i & `INST_JAL_MASK)    == `INST_JAL)    ||
		((opcode_i & `INST_LUI_MASK)    == `INST_LUI)    ||
		((opcode_i & `INST_AUIPC_MASK)  == `INST_AUIPC)  ||
		((opcode_i & `INST_ADDI_MASK)   == `INST_ADDI)   ||
		((opcode_i & `INST_SLLI_MASK)   == `INST_SLLI)   ||
		((opcode_i & `INST_SLTI_MASK)   == `INST_SLTI)   ||
		((opcode_i & `INST_SLTIU_MASK)  == `INST_SLTIU)  ||
		((opcode_i & `INST_XORI_MASK)   == `INST_XORI)   ||
		((opcode_i & `INST_SRLI_MASK)   == `INST_SRLI)   ||
		((opcode_i & `INST_SRAI_MASK)   == `INST_SRAI)   ||
		((opcode_i & `INST_ORI_MASK)    == `INST_ORI)    ||
		((opcode_i & `INST_ANDI_MASK)   == `INST_ANDI)   ||
		((opcode_i & `INST_ADD_MASK)    == `INST_ADD)    ||
		((opcode_i & `INST_SUB_MASK)    == `INST_SUB)    ||
		((opcode_i & `INST_SLL_MASK)    == `INST_SLL)    ||
		((opcode_i & `INST_SLT_MASK)    == `INST_SLT)    ||
		((opcode_i & `INST_SLTU_MASK)   == `INST_SLTU)   ||
		((opcode_i & `INST_XOR_MASK)    == `INST_XOR)    ||
		((opcode_i & `INST_SRL_MASK)    == `INST_SRL)    ||
		((opcode_i & `INST_SRA_MASK)    == `INST_SRA)    ||
		((opcode_i & `INST_OR_MASK)     == `INST_OR)     ||
		((opcode_i & `INST_AND_MASK)    == `INST_AND)    ||
		((opcode_i & `INST_LB_MASK)     == `INST_LB)     ||
		((opcode_i & `INST_LH_MASK)     == `INST_LH)     ||
		((opcode_i & `INST_LW_MASK)     == `INST_LW)     ||
		((opcode_i & `INST_LBU_MASK)    == `INST_LBU)    ||
		((opcode_i & `INST_LHU_MASK)    == `INST_LHU)    ||
		((opcode_i & `INST_LWU_MASK)    == `INST_LWU)    ||
		((opcode_i & `INST_MUL_MASK)    == `INST_MUL)    ||
		((opcode_i & `INST_MULH_MASK)   == `INST_MULH)   ||
		((opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU) ||
		((opcode_i & `INST_MULHU_MASK)  == `INST_MULHU)  ||
		((opcode_i & `INST_DIV_MASK)    == `INST_DIV)    ||
		((opcode_i & `INST_DIVU_MASK)   == `INST_DIVU)   ||
		((opcode_i & `INST_REM_MASK)    == `INST_REM)    ||
		((opcode_i & `INST_REMU_MASK)   == `INST_REMU)   ||
		((opcode_i & `INST_CSRRW_MASK)  == `INST_CSRRW)  ||
		((opcode_i & `INST_CSRRS_MASK)  == `INST_CSRRS)  ||
		((opcode_i & `INST_CSRRC_MASK)  == `INST_CSRRC)  ||
		((opcode_i & `INST_CSRRWI_MASK) == `INST_CSRRWI) ||
		((opcode_i & `INST_CSRRSI_MASK) == `INST_CSRRSI) ||
		((opcode_i & `INST_CSRRCI_MASK) == `INST_CSRRCI);

	// ------------------------------------------------------------------------
	// Execution unit classification
	// ------------------------------------------------------------------------
	// exec_o: ALU / execute-type instructions
	assign exec_o =
		((opcode_i & `INST_ANDI_MASK)  == `INST_ANDI)  ||
		((opcode_i & `INST_ADDI_MASK)  == `INST_ADDI)  ||
		((opcode_i & `INST_SLTI_MASK)  == `INST_SLTI)  ||
		((opcode_i & `INST_SLTIU_MASK) == `INST_SLTIU) ||
		((opcode_i & `INST_ORI_MASK)   == `INST_ORI)   ||
		((opcode_i & `INST_XORI_MASK)  == `INST_XORI)  ||
		((opcode_i & `INST_SLLI_MASK)  == `INST_SLLI)  ||
		((opcode_i & `INST_SRLI_MASK)  == `INST_SRLI)  ||
		((opcode_i & `INST_SRAI_MASK)  == `INST_SRAI)  ||
		((opcode_i & `INST_LUI_MASK)   == `INST_LUI)   ||
		((opcode_i & `INST_AUIPC_MASK) == `INST_AUIPC) ||
		((opcode_i & `INST_ADD_MASK)   == `INST_ADD)   ||
		((opcode_i & `INST_SUB_MASK)   == `INST_SUB)   ||
		((opcode_i & `INST_SLT_MASK)   == `INST_SLT)   ||
		((opcode_i & `INST_SLTU_MASK)  == `INST_SLTU)  ||
		((opcode_i & `INST_XOR_MASK)   == `INST_XOR)   ||
		((opcode_i & `INST_OR_MASK)    == `INST_OR)    ||
		((opcode_i & `INST_AND_MASK)   == `INST_AND)   ||
		((opcode_i & `INST_SLL_MASK)   == `INST_SLL)   ||
		((opcode_i & `INST_SRL_MASK)   == `INST_SRL)   ||
		((opcode_i & `INST_SRA_MASK)   == `INST_SRA);

	// lsu_o: load/store instructions
	assign lsu_o =
		((opcode_i & `INST_LB_MASK)  == `INST_LB)  ||
		((opcode_i & `INST_LH_MASK)  == `INST_LH)  ||
		((opcode_i & `INST_LW_MASK)  == `INST_LW)  ||
		((opcode_i & `INST_LBU_MASK) == `INST_LBU) ||
		((opcode_i & `INST_LHU_MASK) == `INST_LHU) ||
		((opcode_i & `INST_LWU_MASK) == `INST_LWU) ||
		((opcode_i & `INST_SB_MASK)  == `INST_SB)  ||
		((opcode_i & `INST_SH_MASK)  == `INST_SH)  ||
		((opcode_i & `INST_SW_MASK)  == `INST_SW);

	// branch_o: control-flow instructions
	assign branch_o =
		((opcode_i & `INST_JAL_MASK)   == `INST_JAL)   ||
		((opcode_i & `INST_JALR_MASK)  == `INST_JALR)  ||
		((opcode_i & `INST_BEQ_MASK)   == `INST_BEQ)   ||
		((opcode_i & `INST_BNE_MASK)   == `INST_BNE)   ||
		((opcode_i & `INST_BLT_MASK)   == `INST_BLT)   ||
		((opcode_i & `INST_BGE_MASK)   == `INST_BGE)   ||
		((opcode_i & `INST_BLTU_MASK)  == `INST_BLTU)  ||
		((opcode_i & `INST_BGEU_MASK)  == `INST_BGEU);

	// mul_o: multiply operations from M-extension
	assign mul_o =
		enable_muldiv_i &&
		(
			((opcode_i & `INST_MUL_MASK)    == `INST_MUL)    ||
			((opcode_i & `INST_MULH_MASK)   == `INST_MULH)   ||
			((opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU) ||
			((opcode_i & `INST_MULHU_MASK)  == `INST_MULHU)
		);

	// div_o: divide/remainder operations from M-extension
	assign div_o =
		enable_muldiv_i &&
		(
			((opcode_i & `INST_DIV_MASK)  == `INST_DIV)  ||
			((opcode_i & `INST_DIVU_MASK) == `INST_DIVU) ||
			((opcode_i & `INST_REM_MASK)  == `INST_REM)  ||
			((opcode_i & `INST_REMU_MASK) == `INST_REMU)
		);

	// csr_o: CSR/system/fence class instructions
	// Also asserted on invalid instruction or fetch fault.
	assign csr_o =
		((opcode_i & `INST_ECALL_MASK)  == `INST_ECALL)  ||
		((opcode_i & `INST_EBREAK_MASK) == `INST_EBREAK) ||
		((opcode_i & `INST_ERET_MASK)   == `INST_ERET)   ||
		((opcode_i & `INST_CSRRW_MASK)  == `INST_CSRRW)  ||
		((opcode_i & `INST_CSRRS_MASK)  == `INST_CSRRS)  ||
		((opcode_i & `INST_CSRRC_MASK)  == `INST_CSRRC)  ||
		((opcode_i & `INST_CSRRWI_MASK) == `INST_CSRRWI) ||
		((opcode_i & `INST_CSRRSI_MASK) == `INST_CSRRSI) ||
		((opcode_i & `INST_CSRRCI_MASK) == `INST_CSRRCI) ||
		((opcode_i & `INST_WFI_MASK)    == `INST_WFI)    ||
		((opcode_i & `INST_FENCE_MASK)  == `INST_FENCE)  ||
		((opcode_i & `INST_IFENCE_MASK) == `INST_IFENCE) ||
		((opcode_i & `INST_SFENCE_MASK) == `INST_SFENCE) ||
		invalid_w ||
		fetch_fault_i;

endmodule