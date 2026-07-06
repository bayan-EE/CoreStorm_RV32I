//=============================================================
// riscv_alu - RV32 ALU 
//=============================================================
// Features:
// 1) Arithmetic: ADD, SUB
// 2) Logical: AND, OR, XOR
// 3) Shifts: SLL, SRL, SRA (shift amount = alu_b_i[4:0])
// 4) Comparisons: SLT (signed), SLTU (unsigned) -> returns 0/1
//
// Notes:
// - This module is purely combinational (no clock).
// - Operation encoding is taken from biriscv_defs.v (ALU_* macros).
//=============================================================
module riscv_alu
(
	// ---------------------------------------------------------
	// Inputs
	// ---------------------------------------------------------
	input  logic [3:0]  alu_op_i,
	input  logic [31:0] alu_a_i,
	input  logic [31:0] alu_b_i,

	// ---------------------------------------------------------
	// Outputs
	// ---------------------------------------------------------
	output logic [31:0] alu_p_o
);


	
	//-----------------------------------------------------------------
	// Internal signals / regs
	//-----------------------------------------------------------------
	logic [31:0] result_r;
	logic [31:0] sub_res_w;

	// Precompute subtraction (also used for signed compare in some styles)
	assign sub_res_w = alu_a_i - alu_b_i;

	//-----------------------------------------------------------------
	// ALU (combinational)
	//-----------------------------------------------------------------
	always @* begin
		// Default (avoid latches)
		result_r = 32'b0;

		case (alu_op_i)

			//----------------------------------------------------------
			// Shifts
			//----------------------------------------------------------
			`ALU_SHIFTL: begin
				// Logical shift left (SLL)
				result_r = alu_a_i << alu_b_i[4:0];
			end

			`ALU_SHIFTR: begin
				// Logical shift right (SRL)
				result_r = alu_a_i >> alu_b_i[4:0];
			end

			`ALU_SHIFTR_ARITH: begin
				// Arithmetic shift right (SRA): keeps the sign bit
				result_r = $signed(alu_a_i) >>> alu_b_i[4:0];
			end

			//----------------------------------------------------------
			// Arithmetic
			//----------------------------------------------------------
			`ALU_ADD: begin
				result_r = alu_a_i + alu_b_i;
			end

			`ALU_SUB: begin
				result_r = sub_res_w;
			end

			//----------------------------------------------------------
			// Logical
			//----------------------------------------------------------
			`ALU_AND: begin
				result_r = alu_a_i & alu_b_i;
			end

			`ALU_OR: begin
				result_r = alu_a_i | alu_b_i;
			end

			`ALU_XOR: begin
				result_r = alu_a_i ^ alu_b_i;
			end

			//----------------------------------------------------------
			// Comparisons
			//----------------------------------------------------------
			`ALU_LESS_THAN: begin
				// Unsigned compare (SLTU): return 1 if A < B else 0
				result_r = (alu_a_i < alu_b_i) ? 32'h1 : 32'h0;
			end

			`ALU_LESS_THAN_SIGNED: begin
				// Signed compare (SLT): return 1 if A < B else 0
				result_r = ($signed(alu_a_i) < $signed(alu_b_i)) ? 32'h1 : 32'h0;
			end

			//----------------------------------------------------------
			// Default
			//----------------------------------------------------------
			default: begin
				result_r = alu_a_i;
			end

		endcase
	end

	//-----------------------------------------------------------------
	// Output
	//-----------------------------------------------------------------
	assign alu_p_o = result_r;

endmodule