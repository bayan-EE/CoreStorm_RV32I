`timescale 1ns/1ps

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/data.cc/data/a/home/cc/students/enginer/yazanatamna/corestorm_ref/corestorm_ref_2/riscv_defs.sv"

module tb_exec;
// DUT inputs
reg         clk_i;
reg         rst_i;
reg         opcode_valid_i;
reg [31:0]  opcode_opcode_i;
reg [31:0]  opcode_pc_i;
reg         opcode_invalid_i;
reg [4:0]   opcode_rd_idx_i;
reg [4:0]   opcode_ra_idx_i;
reg [4:0]   opcode_rb_idx_i;
reg [31:0]  opcode_ra_operand_i;
reg [31:0]  opcode_rb_operand_i;
reg         hold_i;

// DUT outputs
wire        branch_request_o;
wire        branch_is_taken_o;
wire        branch_is_not_taken_o;
wire [31:0] branch_source_o;
wire        branch_is_call_o;
wire        branch_is_ret_o;
wire        branch_is_jmp_o;
wire [31:0] branch_pc_o;
wire        branch_d_request_o;
wire [31:0] branch_d_pc_o;
wire [1:0]  branch_d_priv_o;
wire [31:0] writeback_value_o;

typedef enum int {
	COV_ADD,
	COV_SUB,
	COV_ADDI,
	COV_BEQ,
	COV_BNE,
	COV_JAL,
	COV_JALR
} instr_cov_e;

instr_cov_e cov_instr_type;
logic       cov_branch_taken;
logic       cov_branch_not_taken;
logic       cov_branch_req;
logic       cov_call;
logic       cov_ret;
logic       cov_jmp;

// DUT
riscv_exec dut (
	 .clk_i(clk_i)
	,.rst_i(rst_i)
	,.opcode_valid_i(opcode_valid_i)
	,.opcode_opcode_i(opcode_opcode_i)
	,.opcode_pc_i(opcode_pc_i)
	,.opcode_invalid_i(opcode_invalid_i)
	,.opcode_rd_idx_i(opcode_rd_idx_i)
	,.opcode_ra_idx_i(opcode_ra_idx_i)
	,.opcode_rb_idx_i(opcode_rb_idx_i)
	,.opcode_ra_operand_i(opcode_ra_operand_i)
	,.opcode_rb_operand_i(opcode_rb_operand_i)
	,.hold_i(hold_i)
	,.branch_request_o(branch_request_o)
	,.branch_is_taken_o(branch_is_taken_o)
	,.branch_is_not_taken_o(branch_is_not_taken_o)
	,.branch_source_o(branch_source_o)
	,.branch_is_call_o(branch_is_call_o)
	,.branch_is_ret_o(branch_is_ret_o)
	,.branch_is_jmp_o(branch_is_jmp_o)
	,.branch_pc_o(branch_pc_o)
	,.branch_d_request_o(branch_d_request_o)
	,.branch_d_pc_o(branch_d_pc_o)
	,.branch_d_priv_o(branch_d_priv_o)
	,.writeback_value_o(writeback_value_o)
);

// Clock
always #5 clk_i = ~clk_i;

// -----------------------------------------
// Helpers
// -----------------------------------------
task reset_dut;
begin
	clk_i                = 0;
	rst_i                = 1;
	opcode_valid_i       = 0;
	opcode_opcode_i      = 32'b0;
	opcode_pc_i          = 32'b0;
	opcode_invalid_i     = 0;
	opcode_rd_idx_i      = 0;
	opcode_ra_idx_i      = 0;
	opcode_rb_idx_i      = 0;
	opcode_ra_operand_i  = 0;
	opcode_rb_operand_i  = 0;
	hold_i               = 0;

	repeat (2) @(posedge clk_i);
	rst_i = 0;
end
endtask

task apply_op;
	input [31:0] instr;
	input [31:0] pc;
	input [31:0] ra_val;
	input [31:0] rb_val;
	input [4:0]  rd_idx;
	input [4:0]  ra_idx;
	input [4:0]  rb_idx;
begin
	opcode_valid_i      = 1'b1;
	opcode_opcode_i     = instr;
	opcode_pc_i         = pc;
	opcode_ra_operand_i = ra_val;
	opcode_rb_operand_i = rb_val;
	opcode_rd_idx_i     = rd_idx;
	opcode_ra_idx_i     = ra_idx;
	opcode_rb_idx_i     = rb_idx;
	@(posedge clk_i);
	#1;
end
endtask

task clear_valid;
begin
	opcode_valid_i = 1'b0;
	opcode_opcode_i = 32'b0;
	@(posedge clk_i);
	#1;
end
endtask

task check32;
	input [255:0] name;
	input [31:0] actual;
	input [31:0] expected;
begin
	if (actual !== expected)
		$display("FAIL: %0s actual=0x%08h expected=0x%08h", name, actual, expected);
	else
		$display("PASS: %0s = 0x%08h", name, actual);
end
endtask

task check1;
	input [255:0] name;
	input actual;
	input expected;
begin
	if (actual !== expected)
		$display("FAIL: %0s actual=%0b expected=%0b", name, actual, expected);
	else
		$display("PASS: %0s = %0b", name, actual);
end
endtask

task automatic sample_exec_cov(input instr_cov_e instr_name);
	begin
		cov_instr_type      = instr_name;
		cov_branch_req      = branch_request_o;
		cov_branch_taken    = branch_is_taken_o;
		cov_branch_not_taken= branch_is_not_taken_o;
		cov_call            = branch_is_call_o;
		cov_ret             = branch_is_ret_o;
		cov_jmp             = branch_is_jmp_o;

		cg_inst.sample();

		$display("[COV] instr=%0d branch_req=%0d taken=%0d call=%0d ret=%0d jmp=%0d",
				 cov_instr_type, cov_branch_req, cov_branch_taken,
				 cov_call, cov_ret, cov_jmp);
	end
	endtask

// -----------------------------------------
// Simple RV32I encoders
// -----------------------------------------
function [31:0] enc_rtype;
	input [6:0] funct7;
	input [4:0] rs2;
	input [4:0] rs1;
	input [2:0] funct3;
	input [4:0] rd;
	input [6:0] opcode;
begin
	enc_rtype = {funct7, rs2, rs1, funct3, rd, opcode};
end
endfunction

function [31:0] enc_itype;
	input [11:0] imm;
	input [4:0]  rs1;
	input [2:0]  funct3;
	input [4:0]  rd;
	input [6:0]  opcode;
begin
	enc_itype = {imm, rs1, funct3, rd, opcode};
end
endfunction

function [31:0] enc_btype;
	input integer imm; // signed byte offset
	input [4:0] rs2;
	input [4:0] rs1;
	input [2:0] funct3;
	input [6:0] opcode;
	reg [12:0] simm;
begin
	simm = imm[12:0];
	enc_btype = {simm[12], simm[10:5], rs2, rs1, funct3, simm[4:1], simm[11], opcode};
end
endfunction

function [31:0] enc_jtype;
	input integer imm; // signed byte offset
	input [4:0] rd;
	input [6:0] opcode;
	reg [20:0] simm;
begin
	simm = imm[20:0];
	enc_jtype = {simm[20], simm[10:1], simm[11], simm[19:12], rd, opcode};
end
endfunction

// -----------------------------------------
// Coverage
// -----------------------------------------

covergroup exec_cg;
	option.per_instance = 1;

	instr_cp: coverpoint cov_instr_type
	{
		bins add  = {COV_ADD};
		bins sub  = {COV_SUB};
		bins addi = {COV_ADDI};
		bins beq  = {COV_BEQ};
		bins bne  = {COV_BNE};
		bins jal  = {COV_JAL};
		bins jalr = {COV_JALR};
	}

	branch_req_cp: coverpoint cov_branch_req
	{
		bins no_branch = {0};
		bins branch    = {1};
	}

	branch_taken_cp: coverpoint cov_branch_taken
	{
		bins not_taken = {0};
		bins taken     = {1};
	}

	call_cp: coverpoint cov_call
	{
		bins no  = {0};
		bins yes = {1};
	}

	ret_cp: coverpoint cov_ret
	{
		bins no  = {0};
		bins yes = {1};
	}

	jmp_cp: coverpoint cov_jmp
	{
		bins no  = {0};
		bins yes = {1};
	}

	instr_x_branch: cross instr_cp, branch_req_cp
	{
		ignore_bins alu_branch =
			binsof(instr_cp) intersect {COV_ADD, COV_SUB, COV_ADDI}
			&& binsof(branch_req_cp.branch);
		ignore_bins impossible =
				binsof(instr_cp) intersect {COV_BEQ, COV_BNE, COV_JAL, COV_JALR}
				&& binsof(branch_req_cp.no_branch);
	}
	
	instr_x_taken: cross instr_cp, branch_taken_cp
	{
		ignore_bins alu_taken =
			binsof(instr_cp) intersect {COV_ADD, COV_SUB, COV_ADDI}
			&& binsof(branch_taken_cp.taken);
		ignore_bins alu_taken_2 =
				binsof(instr_cp) intersect {COV_ADD, COV_SUB, COV_ADDI}
				&& binsof(branch_taken_cp.taken);
		ignore_bins jal_not_taken =
				binsof(instr_cp) intersect {COV_JAL, COV_JALR}
				&& binsof(branch_taken_cp.not_taken);
	}
endgroup
exec_cg cg_inst;
// -----------------------------------------
// Test sequence
// -----------------------------------------
initial begin
	reg [31:0] instr;
	cg_inst = new();
	reset_dut();

	// ==================================================
	// TEST 1: ADD
	// ==================================================
	$display("\n==================================================");
	$display("[TEST1] ADD -> writeback result");
	$display("==================================================");

	instr = enc_rtype(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
	apply_op(instr, 32'h00001000, 32'd10, 32'd20, 5'd3, 5'd1, 5'd2);

	$display("[DEBUG] ra=0x%08h rb=0x%08h wb=0x%08h",
			 32'd10, 32'd20, writeback_value_o);

	if (writeback_value_o == 32'd30)
		$display("PASS ✅ ADD writeback correct");
	else
		$display("FAIL ❌ ADD wrong (expect 30)");
	
	sample_exec_cov(COV_ADD);
	reset_dut();

	// ==================================================
	// TEST 2: SUB
	// ==================================================
	$display("\n==================================================");
	$display("[TEST2] SUB -> writeback result");
	$display("==================================================");

	instr = enc_rtype(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
	apply_op(instr, 32'h00001004, 32'd30, 32'd9, 5'd3, 5'd1, 5'd2);

	$display("[DEBUG] ra=0x%08h rb=0x%08h wb=0x%08h",
			 32'd30, 32'd9, writeback_value_o);

	if (writeback_value_o == 32'd21)
		$display("PASS ✅ SUB writeback correct");
	else
		$display("FAIL ❌ SUB wrong (expect 21)");
	
	sample_exec_cov(COV_SUB);
	reset_dut();

	// ==================================================
	// TEST 3: ADDI
	// ==================================================
	$display("\n==================================================");
	$display("[TEST3] ADDI -> writeback result");
	$display("==================================================");

	instr = enc_itype(12'd15, 5'd1, 3'b000, 5'd5, 7'b0010011);
	apply_op(instr, 32'h00001008, 32'd7, 32'd0, 5'd5, 5'd1, 5'd0);

	$display("[DEBUG] ra=0x%08h imm=0x%08h wb=0x%08h",
			 32'd7, 32'd15, writeback_value_o);

	if (writeback_value_o == 32'd22)
		$display("PASS ✅ ADDI writeback correct");
	else
		$display("FAIL ❌ ADDI wrong (expect 22)");
	
	sample_exec_cov(COV_ADDI);
	reset_dut();

	// ==================================================
	// TEST 4: BEQ taken
	// ==================================================
	$display("\n==================================================");
	$display("[TEST4] BEQ taken -> branch request");
	$display("==================================================");

	instr = enc_btype(16, 5'd2, 5'd1, 3'b000, 7'b1100011);
	apply_op(instr, 32'h00002000, 32'h00000055, 32'h00000055, 5'd0, 5'd1, 5'd2);

	$display("[DEBUG] req=%0d taken=%0d not_taken=%0d src=0x%08h target=0x%08h d_req=%0d d_target=0x%08h",
			 branch_request_o, branch_is_taken_o, branch_is_not_taken_o,
			 branch_source_o, branch_pc_o, branch_d_request_o, branch_d_pc_o);

	if (branch_request_o && branch_is_taken_o && !branch_is_not_taken_o &&
		branch_pc_o == 32'h00002010 && branch_source_o == 32'h00002000 &&
		branch_d_request_o && branch_d_pc_o == 32'h00002010)
		$display("PASS ✅ BEQ taken correctly");
	else
		$display("FAIL ❌ BEQ wrong");
	
	sample_exec_cov(COV_BEQ);
	reset_dut();

	// ==================================================
	// TEST 5: BNE not taken
	// ==================================================
	$display("\n==================================================");
	$display("[TEST5] BNE not taken -> fall-through");
	$display("==================================================");

	instr = enc_btype(8, 5'd2, 5'd1, 3'b001, 7'b1100011);
	apply_op(instr, 32'h00002020, 32'h000000AA, 32'h000000AA, 5'd0, 5'd1, 5'd2);

	$display("[DEBUG] req=%0d taken=%0d not_taken=%0d next_pc=0x%08h",
			 branch_request_o, branch_is_taken_o, branch_is_not_taken_o, branch_pc_o);

	if (branch_request_o && !branch_is_taken_o && branch_is_not_taken_o &&
		branch_pc_o == 32'h00002024)
		$display("PASS ✅ BNE not-taken correctly");
	else
		$display("FAIL ❌ BNE wrong");
	
	sample_exec_cov(COV_BNE);
	reset_dut();

	// ==================================================
	// TEST 6: JAL
	// ==================================================
	$display("\n==================================================");
	$display("[TEST6] JAL -> PC+4 writeback + jump");
	$display("==================================================");

	instr = enc_jtype(32, 5'd1, 7'b1101111);
	apply_op(instr, 32'h00003000, 32'd0, 32'd0, 5'd1, 5'd0, 5'd0);

	$display("[DEBUG] wb=0x%08h req=%0d taken=%0d target=0x%08h call=%0d ret=%0d jmp=%0d",
			 writeback_value_o, branch_request_o, branch_is_taken_o, branch_pc_o,
			 branch_is_call_o, branch_is_ret_o, branch_is_jmp_o);

	if (writeback_value_o == 32'h00003004 &&
		branch_request_o && branch_is_taken_o &&
		branch_pc_o == 32'h00003020 &&
		branch_is_call_o && !branch_is_ret_o && branch_is_jmp_o)
		$display("PASS ✅ JAL correct");
	else
		$display("FAIL ❌ JAL wrong");
	
	sample_exec_cov(COV_JAL);
	reset_dut();

	// ==================================================
	// TEST 7: JALR return
	// ==================================================
	$display("\n==================================================");
	$display("[TEST7] JALR return -> jump to ra");
	$display("==================================================");

	instr = enc_itype(12'd0, 5'd1, 3'b000, 5'd0, 7'b1100111);
	apply_op(instr, 32'h00004000, 32'h00005000, 32'd0, 5'd0, 5'd1, 5'd0);

	$display("[DEBUG] req=%0d taken=%0d target=0x%08h call=%0d ret=%0d jmp=%0d",
			 branch_request_o, branch_is_taken_o, branch_pc_o,
			 branch_is_call_o, branch_is_ret_o, branch_is_jmp_o);

	if (branch_request_o && branch_is_taken_o &&
		branch_pc_o == 32'h00005000 &&
		!branch_is_call_o && branch_is_ret_o && !branch_is_jmp_o)
		$display("PASS ✅ JALR return correct");
	else
		$display("FAIL ❌ JALR wrong");
	
	sample_exec_cov(COV_JALR);
	reset_dut();
	
	$display("\n==================================================");
	$display("[TEST8] BEQ not taken");
	$display("==================================================");

	instr = enc_btype(16, 5'd2, 5'd1, 3'b000, 7'b1100011);

	apply_op(instr, 32'h00002000,
			 32'h1,   // rs1
			 32'h2,   // rs2
			 5'd0, 5'd1, 5'd2);

	if (branch_is_not_taken_o)
		$display("PASS ✅ BEQ not taken correct");
	else
		$display("FAIL ❌ BEQ not taken wrong");
	
	sample_exec_cov(COV_BEQ);
	reset_dut();
	
	$display("\n==================================================");
	$display("[TEST9] BNE taken");
	$display("==================================================");

	instr = enc_btype(8, 5'd2, 5'd1, 3'b001, 7'b1100011);

	apply_op(instr, 32'h00002000,
			 32'h1,
			 32'h2,
			 5'd0, 5'd1, 5'd2);

	if (branch_is_taken_o)
		$display("PASS ✅ BNE taken correct");
	else
		$display("FAIL ❌ BNE taken wrong");
	
	sample_exec_cov(COV_BNE);
	reset_dut();
	clear_valid();

	$display("\n==================================================");
	$display("All tests finished.");
	$display("==================================================");
	$finish;
end
endmodule