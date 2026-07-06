
`timescale 1ns/1ps
module riscv_divider
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

	// Outputs
	output logic         writeback_valid_o,
	output logic [31:0]  writeback_value_o
);



// -------------------------------------------------------------
// Internal registers / signals
// -------------------------------------------------------------
logic        valid_q;
logic [31:0] wb_result_q;

// Divider instruction decode
logic inst_div_w;
logic inst_divu_w;
logic inst_rem_w;
logic inst_remu_w;

logic div_rem_inst_w;
logic signed_operation_w;
logic div_operation_w;

assign inst_div_w  = (opcode_opcode_i & `INST_DIV_MASK)  == `INST_DIV;
assign inst_divu_w = (opcode_opcode_i & `INST_DIVU_MASK) == `INST_DIVU;
assign inst_rem_w  = (opcode_opcode_i & `INST_REM_MASK)  == `INST_REM;
assign inst_remu_w = (opcode_opcode_i & `INST_REMU_MASK) == `INST_REMU;

assign div_rem_inst_w =
	   ((opcode_opcode_i & `INST_DIV_MASK)  == `INST_DIV)
	|| ((opcode_opcode_i & `INST_DIVU_MASK) == `INST_DIVU)
	|| ((opcode_opcode_i & `INST_REM_MASK)  == `INST_REM)
	|| ((opcode_opcode_i & `INST_REMU_MASK) == `INST_REMU);

assign signed_operation_w =
	   ((opcode_opcode_i & `INST_DIV_MASK) == `INST_DIV)
	|| ((opcode_opcode_i & `INST_REM_MASK) == `INST_REM);

assign div_operation_w =
	   ((opcode_opcode_i & `INST_DIV_MASK)  == `INST_DIV)
	|| ((opcode_opcode_i & `INST_DIVU_MASK) == `INST_DIVU);

// Main division state
logic [31:0] dividend_q;
logic [62:0] divisor_q;
logic [31:0] quotient_q;
logic [31:0] q_mask_q;
logic        div_inst_q;
logic        div_busy_q;
logic        invert_res_q;

// Cache previous inputs/operation to preserve original behavior
logic [31:0] last_a_q;
logic [31:0] last_b_q;
logic        last_div_q;
logic        last_divu_q;
logic        last_rem_q;
logic        last_remu_q;

logic div_start_w;
logic div_complete_w;

assign div_start_w    = opcode_valid_i & div_rem_inst_w;
assign div_complete_w = !(|q_mask_q) & div_busy_q;

// -------------------------------------------------------------
// Divider state machine / datapath
// Original iterative shift-subtract divider
// -------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
		div_busy_q   <= 1'b0;
		dividend_q   <= '0;
		divisor_q    <= '0;
		invert_res_q <= 1'b0;
		quotient_q   <= '0;
		q_mask_q     <= '0;
		div_inst_q   <= 1'b0;

		last_a_q     <= '0;
		last_b_q     <= '0;
		last_div_q   <= 1'b0;
		last_divu_q  <= 1'b0;
		last_rem_q   <= 1'b0;
		last_remu_q  <= 1'b0;
	end
	else if (div_start_w) begin
		// Repeating the exact same operation with the same operands
		// keeps the original optimization behavior.
		if ((last_a_q    == opcode_ra_operand_i) &&
			(last_b_q    == opcode_rb_operand_i) &&
			(last_div_q  == inst_div_w) &&
			(last_divu_q == inst_divu_w) &&
			(last_rem_q  == inst_rem_w) &&
			(last_remu_q == inst_remu_w)) begin
			div_busy_q <= 1'b1;
		end
		else begin
			last_a_q    <= opcode_ra_operand_i;
			last_b_q    <= opcode_rb_operand_i;
			last_div_q  <= inst_div_w;
			last_divu_q <= inst_divu_w;
			last_rem_q  <= inst_rem_w;
			last_remu_q <= inst_remu_w;

			div_busy_q <= 1'b1;
			div_inst_q <= div_operation_w;

			// Convert dividend to absolute value for signed ops
			if (signed_operation_w && opcode_ra_operand_i[31])
				dividend_q <= -opcode_ra_operand_i;
			else
				dividend_q <= opcode_ra_operand_i;

			// Load divisor into upper-aligned 63-bit register
			if (signed_operation_w && opcode_rb_operand_i[31])
				divisor_q <= {-opcode_rb_operand_i, 31'b0};
			else
				divisor_q <= {opcode_rb_operand_i, 31'b0};

			// For DIV: result sign depends on operand signs
			// For REM: remainder sign follows dividend sign
			invert_res_q <= (((opcode_opcode_i & `INST_DIV_MASK) == `INST_DIV) &&
							 (opcode_ra_operand_i[31] != opcode_rb_operand_i[31]) &&
							 (|opcode_rb_operand_i))
						  || (((opcode_opcode_i & `INST_REM_MASK) == `INST_REM) &&
							  opcode_ra_operand_i[31]);

			quotient_q <= '0;
			q_mask_q   <= 32'h80000000;
		end
	end
	else if (div_complete_w) begin
		div_busy_q <= 1'b0;
	end
	else if (div_busy_q) begin
		// Iterative restoring-style division step
		if (divisor_q <= {31'b0, dividend_q}) begin
			dividend_q <= dividend_q - divisor_q[31:0];
			quotient_q <= quotient_q | q_mask_q;
		end

		divisor_q <= {1'b0, divisor_q[62:1]};
		q_mask_q  <= {1'b0, q_mask_q[31:1]};
	end
end

// -------------------------------------------------------------
// Final result selection
// -------------------------------------------------------------
logic [31:0] div_result_r;

always_comb begin
	div_result_r = 32'b0;

	if (div_inst_q)
		div_result_r = invert_res_q ? -quotient_q : quotient_q;
	else
		div_result_r = invert_res_q ? -dividend_q : dividend_q;
end

// -------------------------------------------------------------
// Writeback valid generation
// -------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		valid_q <= 1'b0;
	else
		valid_q <= div_complete_w;
end

// -------------------------------------------------------------
// Writeback result register
// -------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		wb_result_q <= '0;
	else if (div_complete_w)
		wb_result_q <= div_result_r;
end

assign writeback_valid_o = valid_q;
assign writeback_value_o = wb_result_q;

endmodule