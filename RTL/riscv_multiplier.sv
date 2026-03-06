
`timescale 1ns/1ps

module riscv_multiplier
(
	// Inputs
	input  logic         clk_i,
	input  logic         rst_i,
	input  logic         opcode_valid_i,
	input  logic [31:0]  opcode_opcode_i,
	input  logic [31:0]  opcode_pc_i,
	input  logic         opcode_invalid_i,
	input  logic [4:0]   opcode_rd_idx_i,
	input  logic [4:0]   opcode_ra_idx_i,
	input  logic [4:0]   opcode_rb_idx_i,
	input  logic [31:0]  opcode_ra_operand_i,
	input  logic [31:0]  opcode_rb_operand_i,
	input  logic         hold_i,

	// Outputs
	output logic [31:0]  writeback_value_o
);



// Number of pipeline stages used for the multiplier result path.
// Original code supports either 2 or 3 stages.
localparam int MULT_STAGES = 2;

// -------------------------------------------------------------
// Internal registers / signals
// -------------------------------------------------------------
logic [31:0] result_e2_q;
logic [31:0] result_e3_q;

logic [32:0] operand_a_e1_q;
logic [32:0] operand_b_e1_q;
logic        mulhi_sel_e1_q;

logic [64:0] mult_result_w;
logic [32:0] operand_a_r;
logic [32:0] operand_b_r;
logic [31:0] result_r;

// Detect any multiply-family instruction
logic mult_inst_w;
assign mult_inst_w =
	   ((opcode_opcode_i & `INST_MUL_MASK)    == `INST_MUL)
	|| ((opcode_opcode_i & `INST_MULH_MASK)   == `INST_MULH)
	|| ((opcode_opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU)
	|| ((opcode_opcode_i & `INST_MULHU_MASK)  == `INST_MULHU);

// -------------------------------------------------------------
// Operand A extension logic
// -------------------------------------------------------------
// MULHSU : signed A
// MULH   : signed A
// MULHU  : unsigned A
// MUL    : unsigned low-part multiply path in original implementation
always_comb begin
	if ((opcode_opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU)
		operand_a_r = {opcode_ra_operand_i[31], opcode_ra_operand_i};
	else if ((opcode_opcode_i & `INST_MULH_MASK) == `INST_MULH)
		operand_a_r = {opcode_ra_operand_i[31], opcode_ra_operand_i};
	else
		operand_a_r = {1'b0, opcode_ra_operand_i};
end

// -------------------------------------------------------------
// Operand B extension logic
// -------------------------------------------------------------
// MULHSU : unsigned B
// MULH   : signed B
// MULHU  : unsigned B
// MUL    : unsigned low-part multiply path in original implementation
always_comb begin
	if ((opcode_opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU)
		operand_b_r = {1'b0, opcode_rb_operand_i};
	else if ((opcode_opcode_i & `INST_MULH_MASK) == `INST_MULH)
		operand_b_r = {opcode_rb_operand_i[31], opcode_rb_operand_i};
	else
		operand_b_r = {1'b0, opcode_rb_operand_i};
end

// -------------------------------------------------------------
// Pipeline stage E1
// Latch operands when a multiply instruction is accepted
// -------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
		operand_a_e1_q <= '0;
		operand_b_e1_q <= '0;
		mulhi_sel_e1_q <= 1'b0;
	end
	else if (hold_i) begin
		// Hold pipeline state
	end
	else if (opcode_valid_i && mult_inst_w) begin
		operand_a_e1_q <= operand_a_r;
		operand_b_e1_q <= operand_b_r;

		// Select upper 32 bits for MULH / MULHSU / MULHU
		// Select lower 32 bits for MUL
		mulhi_sel_e1_q <= ~((opcode_opcode_i & `INST_MUL_MASK) == `INST_MUL);
	end
	else begin
		operand_a_e1_q <= '0;
		operand_b_e1_q <= '0;
		mulhi_sel_e1_q <= 1'b0;
	end
end

// -------------------------------------------------------------
// Multiply operation
// Sign-extend 33-bit operands to 65-bit before multiplying
// -------------------------------------------------------------
assign mult_result_w =
	{{32{operand_a_e1_q[32]}}, operand_a_e1_q} *
	{{32{operand_b_e1_q[32]}}, operand_b_e1_q};

// -------------------------------------------------------------
// Result selection
// -------------------------------------------------------------
always_comb begin
	result_r = mulhi_sel_e1_q ? mult_result_w[63:32] : mult_result_w[31:0];
end

// -------------------------------------------------------------
// Pipeline stage E2
// -------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		result_e2_q <= '0;
	else if (!hold_i)
		result_e2_q <= result_r;
end

// -------------------------------------------------------------
// Optional pipeline stage E3
// -------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		result_e3_q <= '0;
	else if (!hold_i)
		result_e3_q <= result_e2_q;
end

// -------------------------------------------------------------
// Final writeback result
// -------------------------------------------------------------
assign writeback_value_o = (MULT_STAGES == 3) ? result_e3_q : result_e2_q;

endmodule