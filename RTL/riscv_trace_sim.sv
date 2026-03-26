`timescale 1ns/1ps


module riscv_trace_sim
(
	input  logic         valid_i,
	input  logic [31:0]  pc_i,
	input  logic [31:0]  opcode_i,

	output logic [127:0] dbg_inst_str_o,
	output logic [127:0] dbg_inst_ra_o,
	output logic [127:0] dbg_inst_rb_o,
	output logic [127:0] dbg_inst_rd_o,
	output logic [31:0]  dbg_inst_imm_o,
	output logic [31:0]  dbg_inst_pc_o
);

	logic [4:0] ra_idx_w;
	logic [4:0] rb_idx_w;
	logic [4:0] rd_idx_w;

	assign ra_idx_w = opcode_i[19:15];
	assign rb_idx_w = opcode_i[24:20];
	assign rd_idx_w = opcode_i[11:7];

	function automatic logic [127:0] get_regname_str(input logic [4:0] regnum);
		begin
			case (regnum)
				5'd0:  get_regname_str = "zero";
				5'd1:  get_regname_str = "ra";
				5'd2:  get_regname_str = "sp";
				5'd3:  get_regname_str = "gp";
				5'd4:  get_regname_str = "tp";
				5'd5:  get_regname_str = "t0";
				5'd6:  get_regname_str = "t1";
				5'd7:  get_regname_str = "t2";
				5'd8:  get_regname_str = "s0";
				5'd9:  get_regname_str = "s1";
				5'd10: get_regname_str = "a0";
				5'd11: get_regname_str = "a1";
				5'd12: get_regname_str = "a2";
				5'd13: get_regname_str = "a3";
				5'd14: get_regname_str = "a4";
				5'd15: get_regname_str = "a5";
				5'd16: get_regname_str = "a6";
				5'd17: get_regname_str = "a7";
				5'd18: get_regname_str = "s2";
				5'd19: get_regname_str = "s3";
				5'd20: get_regname_str = "s4";
				5'd21: get_regname_str = "s5";
				5'd22: get_regname_str = "s6";
				5'd23: get_regname_str = "s7";
				5'd24: get_regname_str = "s8";
				5'd25: get_regname_str = "s9";
				5'd26: get_regname_str = "s10";
				5'd27: get_regname_str = "s11";
				5'd28: get_regname_str = "t3";
				5'd29: get_regname_str = "t4";
				5'd30: get_regname_str = "t5";
				5'd31: get_regname_str = "t6";
				default: get_regname_str = "unk";
			endcase
		end
	endfunction

	function automatic logic [31:0] imm_imm20(input logic [31:0] op);
		imm_imm20 = {op[31:12], 12'b0};
	endfunction

	function automatic logic [31:0] imm_imm12(input logic [31:0] op);
		imm_imm12 = {{20{op[31]}}, op[31:20]};
	endfunction

	function automatic logic [31:0] imm_bimm(input logic [31:0] op);
		imm_bimm = {{19{op[31]}}, op[31], op[7], op[30:25], op[11:8], 1'b0};
	endfunction

	function automatic logic [31:0] imm_jimm20(input logic [31:0] op);
		imm_jimm20 = {{11{op[31]}}, op[31], op[19:12], op[20], op[30:21], 1'b0};
	endfunction

	function automatic logic [31:0] imm_store(input logic [31:0] op);
		imm_store = {{20{op[31]}}, op[31:25], op[11:7]};
	endfunction

	function automatic logic [31:0] imm_shamt(input logic [31:0] op);
		imm_shamt = {27'b0, op[24:20]};
	endfunction

	always_comb begin
		dbg_inst_str_o = "-";
		dbg_inst_ra_o  = "-";
		dbg_inst_rb_o  = "-";
		dbg_inst_rd_o  = "-";
		dbg_inst_imm_o = 32'h0;
		dbg_inst_pc_o  = 32'h0;

		if (valid_i) begin
			dbg_inst_pc_o = pc_i;
			dbg_inst_ra_o = get_regname_str(ra_idx_w);
			dbg_inst_rb_o = get_regname_str(rb_idx_w);
			dbg_inst_rd_o = get_regname_str(rd_idx_w);

			unique case (1'b1)
				((opcode_i & `INST_ANDI_MASK)   == `INST_ANDI)   : dbg_inst_str_o = "andi";
				((opcode_i & `INST_ADDI_MASK)   == `INST_ADDI)   : dbg_inst_str_o = "addi";
				((opcode_i & `INST_SLTI_MASK)   == `INST_SLTI)   : dbg_inst_str_o = "slti";
				((opcode_i & `INST_SLTIU_MASK)  == `INST_SLTIU)  : dbg_inst_str_o = "sltiu";
				((opcode_i & `INST_ORI_MASK)    == `INST_ORI)    : dbg_inst_str_o = "ori";
				((opcode_i & `INST_XORI_MASK)   == `INST_XORI)   : dbg_inst_str_o = "xori";
				((opcode_i & `INST_SLLI_MASK)   == `INST_SLLI)   : dbg_inst_str_o = "slli";
				((opcode_i & `INST_SRLI_MASK)   == `INST_SRLI)   : dbg_inst_str_o = "srli";
				((opcode_i & `INST_SRAI_MASK)   == `INST_SRAI)   : dbg_inst_str_o = "srai";
				((opcode_i & `INST_LUI_MASK)    == `INST_LUI)    : dbg_inst_str_o = "lui";
				((opcode_i & `INST_AUIPC_MASK)  == `INST_AUIPC)  : dbg_inst_str_o = "auipc";
				((opcode_i & `INST_ADD_MASK)    == `INST_ADD)    : dbg_inst_str_o = "add";
				((opcode_i & `INST_SUB_MASK)    == `INST_SUB)    : dbg_inst_str_o = "sub";
				((opcode_i & `INST_SLT_MASK)    == `INST_SLT)    : dbg_inst_str_o = "slt";
				((opcode_i & `INST_SLTU_MASK)   == `INST_SLTU)   : dbg_inst_str_o = "sltu";
				((opcode_i & `INST_XOR_MASK)    == `INST_XOR)    : dbg_inst_str_o = "xor";
				((opcode_i & `INST_OR_MASK)     == `INST_OR)     : dbg_inst_str_o = "or";
				((opcode_i & `INST_AND_MASK)    == `INST_AND)    : dbg_inst_str_o = "and";
				((opcode_i & `INST_SLL_MASK)    == `INST_SLL)    : dbg_inst_str_o = "sll";
				((opcode_i & `INST_SRL_MASK)    == `INST_SRL)    : dbg_inst_str_o = "srl";
				((opcode_i & `INST_SRA_MASK)    == `INST_SRA)    : dbg_inst_str_o = "sra";
				((opcode_i & `INST_JAL_MASK)    == `INST_JAL)    : dbg_inst_str_o = "jal";
				((opcode_i & `INST_JALR_MASK)   == `INST_JALR)   : dbg_inst_str_o = "jalr";
				((opcode_i & `INST_BEQ_MASK)    == `INST_BEQ)    : dbg_inst_str_o = "beq";
				((opcode_i & `INST_BNE_MASK)    == `INST_BNE)    : dbg_inst_str_o = "bne";
				((opcode_i & `INST_BLT_MASK)    == `INST_BLT)    : dbg_inst_str_o = "blt";
				((opcode_i & `INST_BGE_MASK)    == `INST_BGE)    : dbg_inst_str_o = "bge";
				((opcode_i & `INST_BLTU_MASK)   == `INST_BLTU)   : dbg_inst_str_o = "bltu";
				((opcode_i & `INST_BGEU_MASK)   == `INST_BGEU)   : dbg_inst_str_o = "bgeu";
				((opcode_i & `INST_LB_MASK)     == `INST_LB)     : dbg_inst_str_o = "lb";
				((opcode_i & `INST_LH_MASK)     == `INST_LH)     : dbg_inst_str_o = "lh";
				((opcode_i & `INST_LW_MASK)     == `INST_LW)     : dbg_inst_str_o = "lw";
				((opcode_i & `INST_LBU_MASK)    == `INST_LBU)    : dbg_inst_str_o = "lbu";
				((opcode_i & `INST_LHU_MASK)    == `INST_LHU)    : dbg_inst_str_o = "lhu";
				((opcode_i & `INST_LWU_MASK)    == `INST_LWU)    : dbg_inst_str_o = "lwu";
				((opcode_i & `INST_SB_MASK)     == `INST_SB)     : dbg_inst_str_o = "sb";
				((opcode_i & `INST_SH_MASK)     == `INST_SH)     : dbg_inst_str_o = "sh";
				((opcode_i & `INST_SW_MASK)     == `INST_SW)     : dbg_inst_str_o = "sw";
				((opcode_i & `INST_ECALL_MASK)  == `INST_ECALL)  : dbg_inst_str_o = "ecall";
				((opcode_i & `INST_EBREAK_MASK) == `INST_EBREAK) : dbg_inst_str_o = "ebreak";
				((opcode_i & `INST_ERET_MASK)   == `INST_ERET)   : dbg_inst_str_o = "eret";
				((opcode_i & `INST_CSRRW_MASK)  == `INST_CSRRW)  : dbg_inst_str_o = "csrrw";
				((opcode_i & `INST_CSRRS_MASK)  == `INST_CSRRS)  : dbg_inst_str_o = "csrrs";
				((opcode_i & `INST_CSRRC_MASK)  == `INST_CSRRC)  : dbg_inst_str_o = "csrrc";
				((opcode_i & `INST_CSRRWI_MASK) == `INST_CSRRWI) : dbg_inst_str_o = "csrrwi";
				((opcode_i & `INST_CSRRSI_MASK) == `INST_CSRRSI) : dbg_inst_str_o = "csrrsi";
				((opcode_i & `INST_CSRRCI_MASK) == `INST_CSRRCI) : dbg_inst_str_o = "csrrci";
				((opcode_i & `INST_MUL_MASK)    == `INST_MUL)    : dbg_inst_str_o = "mul";
				((opcode_i & `INST_MULH_MASK)   == `INST_MULH)   : dbg_inst_str_o = "mulh";
				((opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU) : dbg_inst_str_o = "mulhsu";
				((opcode_i & `INST_MULHU_MASK)  == `INST_MULHU)  : dbg_inst_str_o = "mulhu";
				((opcode_i & `INST_DIV_MASK)    == `INST_DIV)    : dbg_inst_str_o = "div";
				((opcode_i & `INST_DIVU_MASK)   == `INST_DIVU)   : dbg_inst_str_o = "divu";
				((opcode_i & `INST_REM_MASK)    == `INST_REM)    : dbg_inst_str_o = "rem";
				((opcode_i & `INST_REMU_MASK)   == `INST_REMU)   : dbg_inst_str_o = "remu";
				((opcode_i & `INST_IFENCE_MASK) == `INST_IFENCE) : dbg_inst_str_o = "fence.i";
				default: dbg_inst_str_o = "unknown";
			endcase

			unique case (1'b1)
				((opcode_i & `INST_ADDI_MASK)   == `INST_ADDI),
				((opcode_i & `INST_ANDI_MASK)   == `INST_ANDI),
				((opcode_i & `INST_SLTI_MASK)   == `INST_SLTI),
				((opcode_i & `INST_SLTIU_MASK)  == `INST_SLTIU),
				((opcode_i & `INST_ORI_MASK)    == `INST_ORI),
				((opcode_i & `INST_XORI_MASK)   == `INST_XORI),
				((opcode_i & `INST_CSRRW_MASK)  == `INST_CSRRW),
				((opcode_i & `INST_CSRRS_MASK)  == `INST_CSRRS),
				((opcode_i & `INST_CSRRC_MASK)  == `INST_CSRRC),
				((opcode_i & `INST_CSRRWI_MASK) == `INST_CSRRWI),
				((opcode_i & `INST_CSRRSI_MASK) == `INST_CSRRSI),
				((opcode_i & `INST_CSRRCI_MASK) == `INST_CSRRCI): begin
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = imm_imm12(opcode_i);
				end

				((opcode_i & `INST_SLLI_MASK) == `INST_SLLI),
				((opcode_i & `INST_SRLI_MASK) == `INST_SRLI),
				((opcode_i & `INST_SRAI_MASK) == `INST_SRAI): begin
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = imm_shamt(opcode_i);
				end

				((opcode_i & `INST_LUI_MASK) == `INST_LUI): begin
					dbg_inst_ra_o  = "-";
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = imm_imm20(opcode_i);
				end

				((opcode_i & `INST_AUIPC_MASK) == `INST_AUIPC): begin
					dbg_inst_ra_o  = "pc";
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = imm_imm20(opcode_i);
				end

				((opcode_i & `INST_JAL_MASK) == `INST_JAL): begin
					dbg_inst_ra_o  = "-";
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = pc_i + imm_jimm20(opcode_i);

					if (rd_idx_w == 5'd1)
						dbg_inst_str_o = "call";
				end

				((opcode_i & `INST_JALR_MASK) == `INST_JALR): begin
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = imm_imm12(opcode_i);

					if ((ra_idx_w == 5'd1) && (imm_imm12(opcode_i) == 32'b0))
						dbg_inst_str_o = "ret";
					else if (rd_idx_w == 5'd1)
						dbg_inst_str_o = "call (R)";
				end

				((opcode_i & `INST_LB_MASK)  == `INST_LB),
				((opcode_i & `INST_LH_MASK)  == `INST_LH),
				((opcode_i & `INST_LW_MASK)  == `INST_LW),
				((opcode_i & `INST_LBU_MASK) == `INST_LBU),
				((opcode_i & `INST_LHU_MASK) == `INST_LHU),
				((opcode_i & `INST_LWU_MASK) == `INST_LWU): begin
					dbg_inst_rb_o  = "-";
					dbg_inst_imm_o = imm_imm12(opcode_i);
				end

				((opcode_i & `INST_SB_MASK) == `INST_SB),
				((opcode_i & `INST_SH_MASK) == `INST_SH),
				((opcode_i & `INST_SW_MASK) == `INST_SW): begin
					dbg_inst_rd_o  = "-";
					dbg_inst_imm_o = imm_store(opcode_i);
				end

				((opcode_i & `INST_BEQ_MASK)  == `INST_BEQ),
				((opcode_i & `INST_BNE_MASK)  == `INST_BNE),
				((opcode_i & `INST_BLT_MASK)  == `INST_BLT),
				((opcode_i & `INST_BGE_MASK)  == `INST_BGE),
				((opcode_i & `INST_BLTU_MASK) == `INST_BLTU),
				((opcode_i & `INST_BGEU_MASK) == `INST_BGEU): begin
					dbg_inst_rd_o  = "-";
					dbg_inst_imm_o = pc_i + imm_bimm(opcode_i);
				end

				default: begin
					dbg_inst_imm_o = 32'h0;
				end
			endcase
		end
	end

endmodule