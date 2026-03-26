`timescale 1ns/1ps


module tb_riscv_trace_sim;

	logic         valid_i;
	logic [31:0]  pc_i;
	logic [31:0]  opcode_i;

	logic [127:0] dbg_inst_str_o;
	logic [127:0] dbg_inst_ra_o;
	logic [127:0] dbg_inst_rb_o;
	logic [127:0] dbg_inst_rd_o;
	logic [31:0]  dbg_inst_imm_o;
	logic [31:0]  dbg_inst_pc_o;

	int pass_count;
	int fail_count;

	riscv_trace_sim dut (
		.valid_i        (valid_i),
		.pc_i           (pc_i),
		.opcode_i       (opcode_i),
		.dbg_inst_str_o (dbg_inst_str_o),
		.dbg_inst_ra_o  (dbg_inst_ra_o),
		.dbg_inst_rb_o  (dbg_inst_rb_o),
		.dbg_inst_rd_o  (dbg_inst_rd_o),
		.dbg_inst_imm_o (dbg_inst_imm_o),
		.dbg_inst_pc_o  (dbg_inst_pc_o)
	);

	function automatic [31:0] enc_addi(input [4:0] rd, input [4:0] rs1, input integer imm);
		enc_addi = {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
	endfunction

	function automatic [31:0] enc_slli(input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
		enc_slli = {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011};
	endfunction

	function automatic [31:0] enc_lui(input [4:0] rd, input [19:0] imm20);
		enc_lui = {imm20, rd, 7'b0110111};
	endfunction

	function automatic [31:0] enc_auipc(input [4:0] rd, input [19:0] imm20);
		enc_auipc = {imm20, rd, 7'b0010111};
	endfunction

	function automatic [31:0] enc_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
		enc_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
	endfunction

	function automatic [31:0] enc_sub(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
		enc_sub = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
	endfunction

	function automatic [31:0] enc_lw(input [4:0] rd, input [4:0] rs1, input integer imm);
		enc_lw = {imm[11:0], rs1, 3'b010, rd, 7'b0000011};
	endfunction

	function automatic [31:0] enc_sw(input [4:0] rs2, input [4:0] rs1, input integer imm);
		enc_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
	endfunction

	function automatic [31:0] enc_jal(input [4:0] rd, input integer imm);
		logic [20:0] j;
		begin
			j = imm[20:0];
			enc_jal = {j[20], j[10:1], j[11], j[19:12], rd, 7'b1101111};
		end
	endfunction

	function automatic [31:0] enc_jalr(input [4:0] rd, input [4:0] rs1, input integer imm);
		enc_jalr = {imm[11:0], rs1, 3'b000, rd, 7'b1100111};
	endfunction

	function automatic [31:0] enc_beq(input [4:0] rs1, input [4:0] rs2, input integer imm);
		logic [12:0] b;
		begin
			b = imm[12:0];
			enc_beq = {b[12], b[10:5], rs2, rs1, 3'b000, b[4:1], b[11], 7'b1100011};
		end
	endfunction

	task automatic check_str(input [127:0] got, input [127:0] exp, input string field_name);
		if (got !== exp) begin
			$display("[FAIL] %s got='%0s' exp='%0s' t=%0t", field_name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic check_u32(input [31:0] got, input [31:0] exp, input string field_name);
		if (got !== exp) begin
			$display("[FAIL] %s got=%08x exp=%08x t=%0t", field_name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic drive_and_check(
		input [31:0] pc,
		input [31:0] op,
		input [127:0] exp_str,
		input [127:0] exp_ra,
		input [127:0] exp_rb,
		input [127:0] exp_rd,
		input [31:0] exp_imm,
		input [31:0] exp_pc
	);
		begin
			pc_i    = pc;
			opcode_i = op;
			valid_i = 1'b1;
			#1;

			check_str(dbg_inst_str_o, exp_str, "dbg_inst_str_o");
			check_str(dbg_inst_ra_o,  exp_ra,  "dbg_inst_ra_o");
			check_str(dbg_inst_rb_o,  exp_rb,  "dbg_inst_rb_o");
			check_str(dbg_inst_rd_o,  exp_rd,  "dbg_inst_rd_o");
			check_u32(dbg_inst_imm_o, exp_imm, "dbg_inst_imm_o");
			check_u32(dbg_inst_pc_o,  exp_pc,  "dbg_inst_pc_o");
		end
	endtask

	// Simple coverage
	covergroup cg;
		cp_valid : coverpoint valid_i;
		cp_opcode_6_0 : coverpoint opcode_i[6:0] {
			bins lui    = {7'b0110111};
			bins auipc  = {7'b0010111};
			bins jal    = {7'b1101111};
			bins jalr   = {7'b1100111};
			bins branch = {7'b1100011};
			bins load   = {7'b0000011};
			bins store  = {7'b0100011};
			bins opimm  = {7'b0010011};
			bins op     = {7'b0110011};
		}
		cp_rd  : coverpoint opcode_i[11:7]  { bins zero = {0}; bins nonzero[] = {[1:31]}; }
		cp_rs1 : coverpoint opcode_i[19:15] { bins regs[] = {[0:31]}; }
		cp_rs2 : coverpoint opcode_i[24:20] { bins regs[] = {[0:31]}; }
		x_type_valid : cross cp_valid, cp_opcode_6_0;
	endgroup

	cg cov = new();

	initial begin
		`ifdef FSDB
			$fsdbDumpfile("tb_riscv_trace_sim.fsdb");
			$fsdbDumpvars(0, tb_riscv_trace_sim);
		`elsif VCS
			$fsdbDumpfile("tb_riscv_trace_sim.fsdb");
			$fsdbDumpvars(0, tb_riscv_trace_sim);
		`endif

		pass_count = 0;
		fail_count = 0;
		valid_i    = 0;
		pc_i       = 32'h0;
		opcode_i   = 32'h0;

		$display("[TEST] invalid_idle");
		#1;
		check_str(dbg_inst_str_o, "-", "invalid dbg_inst_str_o");
		check_str(dbg_inst_ra_o,  "-", "invalid dbg_inst_ra_o");
		check_str(dbg_inst_rb_o,  "-", "invalid dbg_inst_rb_o");
		check_str(dbg_inst_rd_o,  "-", "invalid dbg_inst_rd_o");
		check_u32(dbg_inst_pc_o,  32'h0, "invalid dbg_inst_pc_o");

		$display("[TEST] addi");
		drive_and_check(
			32'h0000_0100,
			enc_addi(5'd10, 5'd2, 12),
			"addi", "sp", "-", "a0", 32'd12, 32'h0000_0100
		);
		cov.sample();

		$display("[TEST] slli");
		drive_and_check(
			32'h0000_0104,
			enc_slli(5'd11, 5'd10, 5'd3),
			"slli", "a0", "-", "a1", 32'd3, 32'h0000_0104
		);
		cov.sample();

		$display("[TEST] lui");
		drive_and_check(
			32'h0000_0108,
			enc_lui(5'd5, 20'h12345),
			"lui", "-", "-", "t0", 32'h12345_000, 32'h0000_0108
		);
		cov.sample();

		$display("[TEST] auipc");
		drive_and_check(
			32'h0000_010C,
			enc_auipc(5'd6, 20'h00010),
			"auipc", "pc", "-", "t1", 32'h00010_000, 32'h0000_010C
		);
		cov.sample();

		$display("[TEST] add");
		drive_and_check(
			32'h0000_0110,
			enc_add(5'd7, 5'd5, 5'd6),
			"add", "t0", "t1", "t2", 32'h0, 32'h0000_0110
		);
		cov.sample();

		$display("[TEST] sub");
		drive_and_check(
			32'h0000_0114,
			enc_sub(5'd8, 5'd7, 5'd6),
			"sub", "t2", "t1", "s0", 32'h0, 32'h0000_0114
		);
		cov.sample();

		$display("[TEST] lw");
		drive_and_check(
			32'h0000_0118,
			enc_lw(5'd9, 5'd2, 16),
			"lw", "sp", "-", "s1", 32'd16, 32'h0000_0118
		);
		cov.sample();

		$display("[TEST] sw");
		drive_and_check(
			32'h0000_011C,
			enc_sw(5'd9, 5'd2, 20),
			"sw", "sp", "s1", "-", 32'd20, 32'h0000_011C
		);
		cov.sample();

		$display("[TEST] jal -> call");
		drive_and_check(
			32'h0000_0120,
			enc_jal(5'd1, 32'd32),
			"call", "-", "-", "ra", 32'h0000_0140, 32'h0000_0120
		);
		cov.sample();

		$display("[TEST] jalr -> ret");
		drive_and_check(
			32'h0000_0124,
			enc_jalr(5'd0, 5'd1, 0),
			"ret", "ra", "-", "zero", 32'h0000_0000, 32'h0000_0124
		);
		cov.sample();

		$display("[TEST] jalr -> call (R)");
		drive_and_check(
			32'h0000_0128,
			enc_jalr(5'd1, 5'd5, 8),
			"call (R)", "t0", "-", "ra", 32'd8, 32'h0000_0128
		);
		cov.sample();

		$display("[TEST] beq");
		drive_and_check(
			32'h0000_0200,
			enc_beq(5'd10, 5'd11, 16),
			"beq", "a0", "a1", "-", 32'h0000_0210, 32'h0000_0200
		);
		cov.sample();

		$display("[TEST] random_smoke");
		repeat (100) begin
			valid_i  = $urandom_range(0, 1);
			pc_i     = {$urandom, 2'b00};
			opcode_i = $urandom;
			#1;
			cov.sample();
		end

		$display("==================================================");
		$display("RISCV_TRACE_SIM TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("==================================================");

		if (fail_count == 0) begin
			$display("TB PASSED");
		end
		else begin
			$display("TB FAILED");
		end

		$finish;
	end

endmodule