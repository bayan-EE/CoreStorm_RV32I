//=============================================================
// tb_riscv_alu.sv - Testbench for riscv_alu
// - Random tests + Directed corner tests
// - Self-checking reference model
// - Functional coverage (opcodes, shift amounts, sign bits, corners)
// - Waves: VCD by default, optional FSDB
//=============================================================



module tb_riscv_alu;


	//-----------------------------------------------------------------
	// DUT signals
	//-----------------------------------------------------------------
	logic [3:0]  alu_op_i;
	logic [31:0] alu_a_i;
	logic [31:0] alu_b_i;
	logic [31:0] alu_p_o;

	//-----------------------------------------------------------------
	// Instantiate DUT
	//-----------------------------------------------------------------
	riscv_alu dut (
		.alu_op_i(alu_op_i),
		.alu_a_i (alu_a_i ),
		.alu_b_i (alu_b_i ),
		.alu_p_o (alu_p_o )
	);
	
	logic [31:0] exp_result;

	always @* begin
		exp_result = ref_alu(alu_op_i, alu_a_i, alu_b_i);
	end
	
	logic match;

	always @* begin
		match = (alu_p_o === exp_result);
	end

	//-----------------------------------------------------------------
	// Reference model
	//-----------------------------------------------------------------
	function automatic logic [31:0] ref_alu(input logic [3:0] op,
											input logic [31:0] a,
											input logic [31:0] b);
		logic [31:0] sub_res;
		sub_res = a - b;

		case (op)
			`ALU_SHIFTL:           ref_alu = a << b[4:0];
			`ALU_SHIFTR:           ref_alu = a >> b[4:0];
			`ALU_SHIFTR_ARITH:     ref_alu = $signed(a) >>> b[4:0];

			`ALU_ADD:              ref_alu = a + b;
			`ALU_SUB:              ref_alu = sub_res;

			`ALU_AND:              ref_alu = a & b;
			`ALU_OR:               ref_alu = a | b;
			`ALU_XOR:              ref_alu = a ^ b;

			`ALU_LESS_THAN:        ref_alu = (a < b) ? 32'h1 : 32'h0; // unsigned
			`ALU_LESS_THAN_SIGNED: ref_alu = ($signed(a) < $signed(b)) ? 32'h1 : 32'h0;

			default:               ref_alu = a;
		endcase
	endfunction

	//-----------------------------------------------------------------
	// Simple checker
	//-----------------------------------------------------------------
	task automatic apply_and_check(input logic [3:0]  op,
								   input logic [31:0] a,
								   input logic [31:0] b);
		logic [31:0] exp;
		begin
			alu_op_i = op;
			alu_a_i  = a;
			alu_b_i  = b;

			// allow combinational settle
			#1;

			exp = ref_alu(op, a, b);

			if (alu_p_o !== exp) begin
				$display("ERROR: mismatch!");
				$display("  time=%0t op=0x%0h a=0x%08h b=0x%08h", $time, op, a, b);
				$display("  got =0x%08h exp=0x%08h", alu_p_o, exp);
				$fatal(1);
			end
		end
	endtask

	//------------------------------------------------------------
	// Event for coverage sampling
	//------------------------------------------------------------
	event sample_ev;

	//-----------------------------------------------------------------
	// Functional coverage
	//-----------------------------------------------------------------
	// Sample coverage after applying vectors (stable values)
	covergroup cg_alu @(sample_ev);
		// Which opcode hit
		cp_op : coverpoint alu_op_i {
			bins shl  = {`ALU_SHIFTL};
			bins srl  = {`ALU_SHIFTR};
			bins sra  = {`ALU_SHIFTR_ARITH};
			bins add  = {`ALU_ADD};
			bins sub  = {`ALU_SUB};
			bins aand = {`ALU_AND};
			bins oor  = {`ALU_OR};
			bins xxor = {`ALU_XOR};
			bins sltu = {`ALU_LESS_THAN};
			bins slt  = {`ALU_LESS_THAN_SIGNED};
			bins other = default;
		}

		// Shift amount (only meaningful for shifts but fine to track globally)
		cp_shamt : coverpoint alu_b_i[4:0] {
			bins zero = {5'd0};
			bins one  = {5'd1};
			bins two  = {5'd2};
			bins three= {5'd3};
			bins four = {5'd4};
			bins mid1 = {5'd5,5'd6,5'd7,5'd8,5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15};
			bins big1 = {5'd16,5'd17,5'd18,5'd19,5'd20,5'd21,5'd22,5'd23,5'd24,5'd25,5'd26,5'd27,5'd28,5'd29,5'd30};
			bins max  = {5'd31};
		}

		// Sign bits (important for signed compare and arithmetic shift)
		cp_a_sign : coverpoint alu_a_i[31] { bins pos = {0}; bins neg = {1}; }
		cp_b_sign : coverpoint alu_b_i[31] { bins pos = {0}; bins neg = {1}; }

		// Some corner-ish patterns
		cp_a_corner : coverpoint alu_a_i {
			bins zero     = {32'h0000_0000};
			bins ones     = {32'hFFFF_FFFF};
			bins msb_only = {32'h8000_0000};
			bins lsb_only = {32'h0000_0001};
		}

		cp_b_corner : coverpoint alu_b_i {
			bins zero     = {32'h0000_0000};
			bins ones     = {32'hFFFF_FFFF};
			bins msb_only = {32'h8000_0000};
			bins lsb_only = {32'h0000_0001};
		}

		// Useful crosses
		x_op_shamt  : cross cp_op, cp_shamt;
		x_sra_sign  : cross cp_op, cp_a_sign;
		x_cmp_signs : cross cp_op, cp_a_sign, cp_b_sign;

	endgroup


	cg_alu cov = new();

	//-----------------------------------------------------------------
	// Random stimulus class
	//-----------------------------------------------------------------
	class alu_rand_t;
		rand logic [3:0]  op;
		rand logic [31:0] a;
		rand logic [31:0] b;

		// Weighting: focus on legal ops more often
		constraint c_op {
			op dist {
				`ALU_ADD              := 10,
				`ALU_SUB              := 10,
				`ALU_AND              := 8,
				`ALU_OR               := 8,
				`ALU_XOR              := 8,
				`ALU_SHIFTL           := 10,
				`ALU_SHIFTR           := 10,
				`ALU_SHIFTR_ARITH     := 10,
				`ALU_LESS_THAN        := 8,
				`ALU_LESS_THAN_SIGNED := 8,
				[0:15]                := 10 // allow "default" bins too
			};
		}

		// Make shift amount interesting (keep b[4:0] varied)
		constraint c_shamt_bias {
			b[4:0] dist {
				5'd0  := 3,
				5'd1  := 3,
				5'd31 := 3,
				[5'd2:5'd30] := 20
			};
		}
	endclass

	//-----------------------------------------------------------------
	// Waves
	//-----------------------------------------------------------------
	initial begin
		// VCD (usually supported everywhere)
		$dumpfile("tb_riscv_alu.vcd");
		$dumpvars(0, tb_riscv_alu);

		// Optional FSDB if your simulator supports it (e.g., VCS)
		`ifdef FSDB
			$fsdbDumpfile("tb_riscv_alu.fsdb");
			$fsdbDumpvars(0, tb_riscv_alu);
		`endif
	end

	//-----------------------------------------------------------------
	// Test sequence
	//-----------------------------------------------------------------
	int unsigned i;
	int unsigned N_RANDOM = 20000;
	
	alu_rand_t r;

	initial begin
		// Init
		alu_op_i = '0;
		alu_a_i  = '0;
		alu_b_i  = '0;
		#5;

		// ------------------------------------------------------------
		// Directed corner tests
		// ------------------------------------------------------------
		apply_and_check(`ALU_ADD, 32'h0000_0000, 32'h0000_0000); -> sample_ev;
		apply_and_check(`ALU_ADD, 32'hFFFF_FFFF, 32'h0000_0001); -> sample_ev;
		apply_and_check(`ALU_SUB, 32'h0000_0000, 32'h0000_0001); -> sample_ev;

		apply_and_check(`ALU_AND, 32'hAAAA_AAAA, 32'h5555_5555); -> sample_ev;
		apply_and_check(`ALU_OR,  32'hAAAA_AAAA, 32'h5555_5555); -> sample_ev;
		apply_and_check(`ALU_XOR, 32'hAAAA_AAAA, 32'h5555_5555); -> sample_ev;

		// Shifts: check boundary shamt values
		apply_and_check(`ALU_SHIFTL,       32'h0000_0001, 32'h0000_0000); -> sample_ev; // <<0
		apply_and_check(`ALU_SHIFTL,       32'h0000_0001, 32'h0000_001F); -> sample_ev; // <<31
		apply_and_check(`ALU_SHIFTR,       32'h8000_0000, 32'h0000_001F); -> sample_ev; // >>31
		apply_and_check(`ALU_SHIFTR_ARITH, 32'h8000_0000, 32'h0000_001F); -> sample_ev; // >>>31 sign extend

		// Comparisons
		apply_and_check(`ALU_LESS_THAN,        32'h0000_0001, 32'h0000_0002); -> sample_ev;
		apply_and_check(`ALU_LESS_THAN,        32'hFFFF_FFFF, 32'h0000_0000); -> sample_ev; // unsigned: false
		apply_and_check(`ALU_LESS_THAN_SIGNED, 32'hFFFF_FFFF, 32'h0000_0000); -> sample_ev; // signed: -1 < 0 true
		apply_and_check(`ALU_LESS_THAN_SIGNED, 32'h8000_0000, 32'h7FFF_FFFF); -> sample_ev; // negative < positive true

		// ------------------------------------------------------------
		// Random tests
		// ------------------------------------------------------------
		r = new();

		for (i = 0; i < N_RANDOM; i++) begin
			assert(r.randomize())
			else begin
				$display("ERROR: randomize failed at i=%0d", i);
				$fatal(1);
			end

			apply_and_check(r.op, r.a, r.b);
			-> sample_ev;

			// Optional progress
			if ((i % 2000) == 0) begin
				$display("Progress: %0d / %0d (coverage=%0.2f%%)",
						 i, N_RANDOM, cov.get_coverage());
			end
		end

		$display("DONE: All tests passed.");
		$display("Final coverage: %0.2f%%", cov.get_coverage());
		$finish;
	end

endmodule