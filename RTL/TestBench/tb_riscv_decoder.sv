`timescale 1ns/1ps

module tb_riscv_decoder;

	// --------------------------------------------------------------------
	// DUT inputs
	// --------------------------------------------------------------------
	logic        valid_i;
	logic        fetch_fault_i;
	logic        enable_muldiv_i;
	logic [31:0] opcode_i;

	// --------------------------------------------------------------------
	// DUT outputs
	// --------------------------------------------------------------------
	logic        invalid_o;
	logic        exec_o;
	logic        lsu_o;
	logic        branch_o;
	logic        mul_o;
	logic        div_o;
	logic        csr_o;
	logic        rd_valid_o;

	// --------------------------------------------------------------------
	// DUT
	// --------------------------------------------------------------------
	riscv_decoder dut (
		 .valid_i         (valid_i)
		,.fetch_fault_i   (fetch_fault_i)
		,.enable_muldiv_i (enable_muldiv_i)
		,.opcode_i        (opcode_i)
		,.invalid_o       (invalid_o)
		,.exec_o          (exec_o)
		,.lsu_o           (lsu_o)
		,.branch_o        (branch_o)
		,.mul_o           (mul_o)
		,.div_o           (div_o)
		,.csr_o           (csr_o)
		,.rd_valid_o      (rd_valid_o)
	);

	// --------------------------------------------------------------------
	// Scoreboard counters
	// --------------------------------------------------------------------
	integer pass_count;
	integer fail_count;
	integer random_count;
	integer directed_count;

	// --------------------------------------------------------------------
	// Coverage helper classification
	// --------------------------------------------------------------------
	typedef enum int {
		CAT_INVALID = 0,
		CAT_EXEC    = 1,
		CAT_LSU     = 2,
		CAT_BRANCH  = 3,
		CAT_MUL     = 4,
		CAT_DIV     = 5,
		CAT_CSR     = 6,
		CAT_OTHER   = 7
	} cat_e;

	cat_e sample_cat;

	// --------------------------------------------------------------------
	// Coverage
	// --------------------------------------------------------------------
	covergroup decoder_cg;
		option.per_instance = 1;

		cp_valid: coverpoint valid_i {
			bins zero = {0};
			bins one  = {1};
		}

		cp_fetch_fault: coverpoint fetch_fault_i {
			bins zero = {0};
			bins one  = {1};
		}

		cp_muldiv_en: coverpoint enable_muldiv_i {
			bins zero = {0};
			bins one  = {1};
		}

		cp_invalid: coverpoint invalid_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_exec: coverpoint exec_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_lsu: coverpoint lsu_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_branch: coverpoint branch_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_mul: coverpoint mul_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_div: coverpoint div_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_csr: coverpoint csr_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_rd_valid: coverpoint rd_valid_o {
			bins zero = {0};
			bins one  = {1};
		}

		cp_cat: coverpoint sample_cat {
			bins invalid_b = {CAT_INVALID};
			bins exec_b    = {CAT_EXEC};
			bins lsu_b     = {CAT_LSU};
			bins branch_b  = {CAT_BRANCH};
			bins mul_b     = {CAT_MUL};
			bins div_b     = {CAT_DIV};
			bins csr_b     = {CAT_CSR};
			bins other_b   = {CAT_OTHER};
		}

		x_invalid_fault : cross cp_invalid, cp_fetch_fault;
		x_muldiv_mul    : cross cp_muldiv_en, cp_mul;
		x_muldiv_div    : cross cp_muldiv_en, cp_div;
		x_valid_cat     : cross cp_valid, cp_cat;
	endgroup

	decoder_cg cg_inst = new();

	// --------------------------------------------------------------------
	// Reference model helper functions
	// --------------------------------------------------------------------
	function automatic logic is_supported_instr(input logic [31:0] op, input logic en_muldiv);
		begin
			is_supported_instr =
				((op & `INST_ANDI_MASK)   == `INST_ANDI)   ||
				((op & `INST_ADDI_MASK)   == `INST_ADDI)   ||
				((op & `INST_SLTI_MASK)   == `INST_SLTI)   ||
				((op & `INST_SLTIU_MASK)  == `INST_SLTIU)  ||
				((op & `INST_ORI_MASK)    == `INST_ORI)    ||
				((op & `INST_XORI_MASK)   == `INST_XORI)   ||
				((op & `INST_SLLI_MASK)   == `INST_SLLI)   ||
				((op & `INST_SRLI_MASK)   == `INST_SRLI)   ||
				((op & `INST_SRAI_MASK)   == `INST_SRAI)   ||
				((op & `INST_LUI_MASK)    == `INST_LUI)    ||
				((op & `INST_AUIPC_MASK)  == `INST_AUIPC)  ||
				((op & `INST_ADD_MASK)    == `INST_ADD)    ||
				((op & `INST_SUB_MASK)    == `INST_SUB)    ||
				((op & `INST_SLT_MASK)    == `INST_SLT)    ||
				((op & `INST_SLTU_MASK)   == `INST_SLTU)   ||
				((op & `INST_XOR_MASK)    == `INST_XOR)    ||
				((op & `INST_OR_MASK)     == `INST_OR)     ||
				((op & `INST_AND_MASK)    == `INST_AND)    ||
				((op & `INST_SLL_MASK)    == `INST_SLL)    ||
				((op & `INST_SRL_MASK)    == `INST_SRL)    ||
				((op & `INST_SRA_MASK)    == `INST_SRA)    ||
				((op & `INST_JAL_MASK)    == `INST_JAL)    ||
				((op & `INST_JALR_MASK)   == `INST_JALR)   ||
				((op & `INST_BEQ_MASK)    == `INST_BEQ)    ||
				((op & `INST_BNE_MASK)    == `INST_BNE)    ||
				((op & `INST_BLT_MASK)    == `INST_BLT)    ||
				((op & `INST_BGE_MASK)    == `INST_BGE)    ||
				((op & `INST_BLTU_MASK)   == `INST_BLTU)   ||
				((op & `INST_BGEU_MASK)   == `INST_BGEU)   ||
				((op & `INST_LB_MASK)     == `INST_LB)     ||
				((op & `INST_LH_MASK)     == `INST_LH)     ||
				((op & `INST_LW_MASK)     == `INST_LW)     ||
				((op & `INST_LBU_MASK)    == `INST_LBU)    ||
				((op & `INST_LHU_MASK)    == `INST_LHU)    ||
				((op & `INST_LWU_MASK)    == `INST_LWU)    ||
				((op & `INST_SB_MASK)     == `INST_SB)     ||
				((op & `INST_SH_MASK)     == `INST_SH)     ||
				((op & `INST_SW_MASK)     == `INST_SW)     ||
				((op & `INST_ECALL_MASK)  == `INST_ECALL)  ||
				((op & `INST_EBREAK_MASK) == `INST_EBREAK) ||
				((op & `INST_ERET_MASK)   == `INST_ERET)   ||
				((op & `INST_CSRRW_MASK)  == `INST_CSRRW)  ||
				((op & `INST_CSRRS_MASK)  == `INST_CSRRS)  ||
				((op & `INST_CSRRC_MASK)  == `INST_CSRRC)  ||
				((op & `INST_CSRRWI_MASK) == `INST_CSRRWI) ||
				((op & `INST_CSRRSI_MASK) == `INST_CSRRSI) ||
				((op & `INST_CSRRCI_MASK) == `INST_CSRRCI) ||
				((op & `INST_WFI_MASK)    == `INST_WFI)    ||
				((op & `INST_FENCE_MASK)  == `INST_FENCE)  ||
				((op & `INST_IFENCE_MASK) == `INST_IFENCE) ||
				((op & `INST_SFENCE_MASK) == `INST_SFENCE) ||
				(en_muldiv && ((op & `INST_MUL_MASK)    == `INST_MUL))    ||
				(en_muldiv && ((op & `INST_MULH_MASK)   == `INST_MULH))   ||
				(en_muldiv && ((op & `INST_MULHSU_MASK) == `INST_MULHSU)) ||
				(en_muldiv && ((op & `INST_MULHU_MASK)  == `INST_MULHU))  ||
				(en_muldiv && ((op & `INST_DIV_MASK)    == `INST_DIV))    ||
				(en_muldiv && ((op & `INST_DIVU_MASK)   == `INST_DIVU))   ||
				(en_muldiv && ((op & `INST_REM_MASK)    == `INST_REM))    ||
				(en_muldiv && ((op & `INST_REMU_MASK)   == `INST_REMU));
		end
	endfunction

	function automatic logic ref_invalid(input logic v, input logic [31:0] op, input logic en_muldiv);
		ref_invalid = v && !is_supported_instr(op, en_muldiv);
	endfunction

	function automatic logic ref_rd_valid(input logic [31:0] op);
		begin
			ref_rd_valid =
				((op & `INST_JALR_MASK)   == `INST_JALR)   ||
				((op & `INST_JAL_MASK)    == `INST_JAL)    ||
				((op & `INST_LUI_MASK)    == `INST_LUI)    ||
				((op & `INST_AUIPC_MASK)  == `INST_AUIPC)  ||
				((op & `INST_ADDI_MASK)   == `INST_ADDI)   ||
				((op & `INST_SLLI_MASK)   == `INST_SLLI)   ||
				((op & `INST_SLTI_MASK)   == `INST_SLTI)   ||
				((op & `INST_SLTIU_MASK)  == `INST_SLTIU)  ||
				((op & `INST_XORI_MASK)   == `INST_XORI)   ||
				((op & `INST_SRLI_MASK)   == `INST_SRLI)   ||
				((op & `INST_SRAI_MASK)   == `INST_SRAI)   ||
				((op & `INST_ORI_MASK)    == `INST_ORI)    ||
				((op & `INST_ANDI_MASK)   == `INST_ANDI)   ||
				((op & `INST_ADD_MASK)    == `INST_ADD)    ||
				((op & `INST_SUB_MASK)    == `INST_SUB)    ||
				((op & `INST_SLL_MASK)    == `INST_SLL)    ||
				((op & `INST_SLT_MASK)    == `INST_SLT)    ||
				((op & `INST_SLTU_MASK)   == `INST_SLTU)   ||
				((op & `INST_XOR_MASK)    == `INST_XOR)    ||
				((op & `INST_SRL_MASK)    == `INST_SRL)    ||
				((op & `INST_SRA_MASK)    == `INST_SRA)    ||
				((op & `INST_OR_MASK)     == `INST_OR)     ||
				((op & `INST_AND_MASK)    == `INST_AND)    ||
				((op & `INST_LB_MASK)     == `INST_LB)     ||
				((op & `INST_LH_MASK)     == `INST_LH)     ||
				((op & `INST_LW_MASK)     == `INST_LW)     ||
				((op & `INST_LBU_MASK)    == `INST_LBU)    ||
				((op & `INST_LHU_MASK)    == `INST_LHU)    ||
				((op & `INST_LWU_MASK)    == `INST_LWU)    ||
				((op & `INST_MUL_MASK)    == `INST_MUL)    ||
				((op & `INST_MULH_MASK)   == `INST_MULH)   ||
				((op & `INST_MULHSU_MASK) == `INST_MULHSU) ||
				((op & `INST_MULHU_MASK)  == `INST_MULHU)  ||
				((op & `INST_DIV_MASK)    == `INST_DIV)    ||
				((op & `INST_DIVU_MASK)   == `INST_DIVU)   ||
				((op & `INST_REM_MASK)    == `INST_REM)    ||
				((op & `INST_REMU_MASK)   == `INST_REMU)   ||
				((op & `INST_CSRRW_MASK)  == `INST_CSRRW)  ||
				((op & `INST_CSRRS_MASK)  == `INST_CSRRS)  ||
				((op & `INST_CSRRC_MASK)  == `INST_CSRRC)  ||
				((op & `INST_CSRRWI_MASK) == `INST_CSRRWI) ||
				((op & `INST_CSRRSI_MASK) == `INST_CSRRSI) ||
				((op & `INST_CSRRCI_MASK) == `INST_CSRRCI);
		end
	endfunction

	function automatic logic ref_exec(input logic [31:0] op);
		begin
			ref_exec =
				((op & `INST_ANDI_MASK)  == `INST_ANDI)  ||
				((op & `INST_ADDI_MASK)  == `INST_ADDI)  ||
				((op & `INST_SLTI_MASK)  == `INST_SLTI)  ||
				((op & `INST_SLTIU_MASK) == `INST_SLTIU) ||
				((op & `INST_ORI_MASK)   == `INST_ORI)   ||
				((op & `INST_XORI_MASK)  == `INST_XORI)  ||
				((op & `INST_SLLI_MASK)  == `INST_SLLI)  ||
				((op & `INST_SRLI_MASK)  == `INST_SRLI)  ||
				((op & `INST_SRAI_MASK)  == `INST_SRAI)  ||
				((op & `INST_LUI_MASK)   == `INST_LUI)   ||
				((op & `INST_AUIPC_MASK) == `INST_AUIPC) ||
				((op & `INST_ADD_MASK)   == `INST_ADD)   ||
				((op & `INST_SUB_MASK)   == `INST_SUB)   ||
				((op & `INST_SLT_MASK)   == `INST_SLT)   ||
				((op & `INST_SLTU_MASK)  == `INST_SLTU)  ||
				((op & `INST_XOR_MASK)   == `INST_XOR)   ||
				((op & `INST_OR_MASK)    == `INST_OR)    ||
				((op & `INST_AND_MASK)   == `INST_AND)   ||
				((op & `INST_SLL_MASK)   == `INST_SLL)   ||
				((op & `INST_SRL_MASK)   == `INST_SRL)   ||
				((op & `INST_SRA_MASK)   == `INST_SRA);
		end
	endfunction

	function automatic logic ref_lsu(input logic [31:0] op);
		begin
			ref_lsu =
				((op & `INST_LB_MASK)  == `INST_LB)  ||
				((op & `INST_LH_MASK)  == `INST_LH)  ||
				((op & `INST_LW_MASK)  == `INST_LW)  ||
				((op & `INST_LBU_MASK) == `INST_LBU) ||
				((op & `INST_LHU_MASK) == `INST_LHU) ||
				((op & `INST_LWU_MASK) == `INST_LWU) ||
				((op & `INST_SB_MASK)  == `INST_SB)  ||
				((op & `INST_SH_MASK)  == `INST_SH)  ||
				((op & `INST_SW_MASK)  == `INST_SW);
		end
	endfunction

	function automatic logic ref_branch(input logic [31:0] op);
		begin
			ref_branch =
				((op & `INST_JAL_MASK)  == `INST_JAL)  ||
				((op & `INST_JALR_MASK) == `INST_JALR) ||
				((op & `INST_BEQ_MASK)  == `INST_BEQ)  ||
				((op & `INST_BNE_MASK)  == `INST_BNE)  ||
				((op & `INST_BLT_MASK)  == `INST_BLT)  ||
				((op & `INST_BGE_MASK)  == `INST_BGE)  ||
				((op & `INST_BLTU_MASK) == `INST_BLTU) ||
				((op & `INST_BGEU_MASK) == `INST_BGEU);
		end
	endfunction

	function automatic logic ref_mul(input logic [31:0] op, input logic en_muldiv);
		begin
			ref_mul =
				en_muldiv &&
				(
					((op & `INST_MUL_MASK)    == `INST_MUL)    ||
					((op & `INST_MULH_MASK)   == `INST_MULH)   ||
					((op & `INST_MULHSU_MASK) == `INST_MULHSU) ||
					((op & `INST_MULHU_MASK)  == `INST_MULHU)
				);
		end
	endfunction

	function automatic logic ref_div(input logic [31:0] op, input logic en_muldiv);
		begin
			ref_div =
				en_muldiv &&
				(
					((op & `INST_DIV_MASK)  == `INST_DIV)  ||
					((op & `INST_DIVU_MASK) == `INST_DIVU) ||
					((op & `INST_REM_MASK)  == `INST_REM)  ||
					((op & `INST_REMU_MASK) == `INST_REMU)
				);
		end
	endfunction

	function automatic logic ref_csr(
		input logic [31:0] op,
		input logic        fetch_fault,
		input logic        inv
	);
		begin
			ref_csr =
				((op & `INST_ECALL_MASK)  == `INST_ECALL)  ||
				((op & `INST_EBREAK_MASK) == `INST_EBREAK) ||
				((op & `INST_ERET_MASK)   == `INST_ERET)   ||
				((op & `INST_CSRRW_MASK)  == `INST_CSRRW)  ||
				((op & `INST_CSRRS_MASK)  == `INST_CSRRS)  ||
				((op & `INST_CSRRC_MASK)  == `INST_CSRRC)  ||
				((op & `INST_CSRRWI_MASK) == `INST_CSRRWI) ||
				((op & `INST_CSRRSI_MASK) == `INST_CSRRSI) ||
				((op & `INST_CSRRCI_MASK) == `INST_CSRRCI) ||
				((op & `INST_WFI_MASK)    == `INST_WFI)    ||
				((op & `INST_FENCE_MASK)  == `INST_FENCE)  ||
				((op & `INST_IFENCE_MASK) == `INST_IFENCE) ||
				((op & `INST_SFENCE_MASK) == `INST_SFENCE) ||
				inv || fetch_fault;
		end
	endfunction

	function automatic cat_e classify_sample(
		input logic inv,
		input logic ex,
		input logic ls,
		input logic br,
		input logic ml,
		input logic dv,
		input logic cs
	);
		begin
			if (inv)      classify_sample = CAT_INVALID;
			else if (ml)  classify_sample = CAT_MUL;
			else if (dv)  classify_sample = CAT_DIV;
			else if (ex)  classify_sample = CAT_EXEC;
			else if (ls)  classify_sample = CAT_LSU;
			else if (br)  classify_sample = CAT_BRANCH;
			else if (cs)  classify_sample = CAT_CSR;
			else          classify_sample = CAT_OTHER;
		end
	endfunction

	// --------------------------------------------------------------------
	// Pick one legal opcode for random valid testing
	// --------------------------------------------------------------------
	function automatic logic [31:0] pick_valid_opcode(input int idx);
		case (idx)
			0  : pick_valid_opcode = `INST_ADDI;
			1  : pick_valid_opcode = `INST_ANDI;
			2  : pick_valid_opcode = `INST_ORI;
			3  : pick_valid_opcode = `INST_XORI;
			4  : pick_valid_opcode = `INST_SLLI;
			5  : pick_valid_opcode = `INST_SRLI;
			6  : pick_valid_opcode = `INST_SRAI;
			7  : pick_valid_opcode = `INST_ADD;
			8  : pick_valid_opcode = `INST_SUB;
			9  : pick_valid_opcode = `INST_AND;
			10 : pick_valid_opcode = `INST_OR;
			11 : pick_valid_opcode = `INST_XOR;
			12 : pick_valid_opcode = `INST_SLT;
			13 : pick_valid_opcode = `INST_SLTU;
			14 : pick_valid_opcode = `INST_SLL;
			15 : pick_valid_opcode = `INST_SRL;
			16 : pick_valid_opcode = `INST_SRA;
			17 : pick_valid_opcode = `INST_LUI;
			18 : pick_valid_opcode = `INST_AUIPC;
			19 : pick_valid_opcode = `INST_LB;
			20 : pick_valid_opcode = `INST_LH;
			21 : pick_valid_opcode = `INST_LW;
			22 : pick_valid_opcode = `INST_LBU;
			23 : pick_valid_opcode = `INST_LHU;
			24 : pick_valid_opcode = `INST_LWU;
			25 : pick_valid_opcode = `INST_SB;
			26 : pick_valid_opcode = `INST_SH;
			27 : pick_valid_opcode = `INST_SW;
			28 : pick_valid_opcode = `INST_JAL;
			29 : pick_valid_opcode = `INST_JALR;
			30 : pick_valid_opcode = `INST_BEQ;
			31 : pick_valid_opcode = `INST_BNE;
			32 : pick_valid_opcode = `INST_BLT;
			33 : pick_valid_opcode = `INST_BGE;
			34 : pick_valid_opcode = `INST_BLTU;
			35 : pick_valid_opcode = `INST_BGEU;
			36 : pick_valid_opcode = `INST_ECALL;
			37 : pick_valid_opcode = `INST_EBREAK;
			38 : pick_valid_opcode = `INST_ERET;
			39 : pick_valid_opcode = `INST_CSRRW;
			40 : pick_valid_opcode = `INST_CSRRS;
			41 : pick_valid_opcode = `INST_CSRRC;
			42 : pick_valid_opcode = `INST_CSRRWI;
			43 : pick_valid_opcode = `INST_CSRRSI;
			44 : pick_valid_opcode = `INST_CSRRCI;
			45 : pick_valid_opcode = `INST_WFI;
			46 : pick_valid_opcode = `INST_FENCE;
			47 : pick_valid_opcode = `INST_IFENCE;
			48 : pick_valid_opcode = `INST_SFENCE;
			49 : pick_valid_opcode = `INST_MUL;
			50 : pick_valid_opcode = `INST_MULH;
			51 : pick_valid_opcode = `INST_MULHSU;
			52 : pick_valid_opcode = `INST_MULHU;
			53 : pick_valid_opcode = `INST_DIV;
			54 : pick_valid_opcode = `INST_DIVU;
			55 : pick_valid_opcode = `INST_REM;
			default: pick_valid_opcode = `INST_REMU;
		endcase
	endfunction

	// --------------------------------------------------------------------
	// Generate an invalid opcode
	// --------------------------------------------------------------------
	function automatic logic [31:0] pick_invalid_opcode(input logic en_muldiv);
		logic [31:0] tmp;
		int tries;
		begin
			pick_invalid_opcode = 32'hFFFF_FFFF;

			for (tries = 0; tries < 10000; tries++) begin
				tmp = $urandom;

				if (!is_supported_instr(tmp, en_muldiv)) begin
					pick_invalid_opcode = tmp;
					break;
				end
			end
		end
	endfunction

	// --------------------------------------------------------------------
	// Check task
	// --------------------------------------------------------------------
	task automatic check_case(
		input string       test_name,
		input logic        v,
		input logic        ff,
		input logic        enm,
		input logic [31:0] op
	);
		logic exp_invalid;
		logic exp_exec;
		logic exp_lsu;
		logic exp_branch;
		logic exp_mul;
		logic exp_div;
		logic exp_csr;
		logic exp_rd_valid;
		begin
			valid_i         = v;
			fetch_fault_i   = ff;
			enable_muldiv_i = enm;
			opcode_i        = op;

			#1;

			exp_invalid  = ref_invalid(v, op, enm);
			exp_exec     = ref_exec(op);
			exp_lsu      = ref_lsu(op);
			exp_branch   = ref_branch(op);
			exp_mul      = ref_mul(op, enm);
			exp_div      = ref_div(op, enm);
			exp_rd_valid = ref_rd_valid(op);
			exp_csr      = ref_csr(op, ff, exp_invalid);

			sample_cat = classify_sample(
				exp_invalid,
				exp_exec,
				exp_lsu,
				exp_branch,
				exp_mul,
				exp_div,
				exp_csr
			);
			cg_inst.sample();

			if (invalid_o  !== exp_invalid  ||
				exec_o     !== exp_exec     ||
				lsu_o      !== exp_lsu      ||
				branch_o   !== exp_branch   ||
				mul_o      !== exp_mul      ||
				div_o      !== exp_div      ||
				csr_o      !== exp_csr      ||
				rd_valid_o !== exp_rd_valid) begin

				fail_count++;

				$display("--------------------------------------------------");
				$display("[FAIL] %s", test_name);
				$display("  valid_i         = %0b", v);
				$display("  fetch_fault_i   = %0b", ff);
				$display("  enable_muldiv_i = %0b", enm);
				$display("  opcode_i        = 0x%08h", op);
				$display("  EXPECTED: invalid=%0b exec=%0b lsu=%0b branch=%0b mul=%0b div=%0b csr=%0b rd_valid=%0b",
						 exp_invalid, exp_exec, exp_lsu, exp_branch, exp_mul, exp_div, exp_csr, exp_rd_valid);
				$display("  GOT     : invalid=%0b exec=%0b lsu=%0b branch=%0b mul=%0b div=%0b csr=%0b rd_valid=%0b",
						 invalid_o, exec_o, lsu_o, branch_o, mul_o, div_o, csr_o, rd_valid_o);
				$display("--------------------------------------------------");
			end
			else begin
				pass_count++;
				$display("[PASS] %s opcode=0x%08h", test_name, op);
			end
		end
	endtask

	// --------------------------------------------------------------------
	// Directed tests
	// --------------------------------------------------------------------
	task automatic run_directed_tests;
		begin
			$display("\n================ DIRECTED TESTS ================");

			directed_count = 0;

			directed_count++;
			check_case("valid=0 should not assert invalid", 1'b0, 1'b0, 1'b0, 32'hDEAD_BEEF);

			directed_count++;
			check_case("ADDI -> exec + rd_valid", 1'b1, 1'b0, 1'b0, `INST_ADDI);

			directed_count++;
			check_case("ADD -> exec + rd_valid", 1'b1, 1'b0, 1'b0, `INST_ADD);

			directed_count++;
			check_case("LW -> lsu + rd_valid", 1'b1, 1'b0, 1'b0, `INST_LW);

			directed_count++;
			check_case("SW -> lsu only", 1'b1, 1'b0, 1'b0, `INST_SW);

			directed_count++;
			check_case("JAL -> branch + rd_valid", 1'b1, 1'b0, 1'b0, `INST_JAL);

			directed_count++;
			check_case("BEQ -> branch only", 1'b1, 1'b0, 1'b0, `INST_BEQ);

			directed_count++;
			check_case("CSRRW -> csr + rd_valid", 1'b1, 1'b0, 1'b0, `INST_CSRRW);

			directed_count++;
			check_case("ECALL -> csr", 1'b1, 1'b0, 1'b0, `INST_ECALL);

			directed_count++;
			check_case("FENCE -> csr", 1'b1, 1'b0, 1'b0, `INST_FENCE);

			directed_count++;
			check_case("MUL disabled -> invalid", 1'b1, 1'b0, 1'b0, `INST_MUL);

			directed_count++;
			check_case("MUL enabled -> mul + rd_valid", 1'b1, 1'b0, 1'b1, `INST_MUL);

			directed_count++;
			check_case("DIV enabled -> div + rd_valid", 1'b1, 1'b0, 1'b1, `INST_DIV);

			directed_count++;
			check_case("DIV disabled -> invalid", 1'b1, 1'b0, 1'b0, `INST_DIV);

			directed_count++;
			check_case("fetch fault forces csr", 1'b1, 1'b1, 1'b0, `INST_ADD);

			directed_count++;
			check_case("invalid opcode -> invalid + csr", 1'b1, 1'b0, 1'b0, 32'hFFFF_FFFF);
		end
	endtask

	// --------------------------------------------------------------------
	// Random tests
	// --------------------------------------------------------------------
	task automatic run_random_tests(input int num_tests);
		int i;
		int sel;
		logic [31:0] op;
		logic        v;
		logic        ff;
		logic        enm;
		begin
			$display("\n================ RANDOM TESTS ==================");
			random_count = 0;

			for (i = 0; i < num_tests; i++) begin
				v   = $urandom_range(0, 1);
				ff  = $urandom_range(0, 1);
				enm = $urandom_range(0, 1);
				sel = $urandom_range(0, 99);

				// 70% valid opcode, 30% invalid opcode
				if (sel < 70) begin
					op = pick_valid_opcode($urandom_range(0, 56));
				end
				else begin
					op = pick_invalid_opcode(enm);
				end

				random_count++;
				check_case($sformatf("random_test_%0d", i), v, ff, enm, op);
			end
		end
	endtask

	// --------------------------------------------------------------------
	// Main
	// --------------------------------------------------------------------
	initial begin
		pass_count     = 0;
		fail_count     = 0;
		random_count   = 0;
		directed_count = 0;

		valid_i         = 1'b0;
		fetch_fault_i   = 1'b0;
		enable_muldiv_i = 1'b0;
		opcode_i        = 32'h0;

		#5;

		run_directed_tests();
		run_random_tests(500);

		$display("\n============================================================");
		$display("DECODER TB SUMMARY");
		$display("  directed_count = %0d", directed_count);
		$display("  random_count   = %0d", random_count);
		$display("  pass_count     = %0d", pass_count);
		$display("  fail_count     = %0d", fail_count);
		$display("  coverage       = %0.2f %%", cg_inst.get_inst_coverage());
		$display("============================================================");

		if (fail_count == 0) begin
			$display("TB PASSED");
		end
		else begin
			$display("TB FAILED");
		end

		$finish;
	end

endmodule