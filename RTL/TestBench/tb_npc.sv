`timescale 1ns/1ps

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "/project/tsmc28mmwave/users/saidahmad/ws/CoreStorm_1/riscv_defs.sv"

module tb_npc;

localparam SUPPORT_BRANCH_PREDICTION = 1;
localparam NUM_BTB_ENTRIES           = 32;
localparam NUM_BTB_ENTRIES_W         = 5;
localparam NUM_BHT_ENTRIES           = 512;
localparam NUM_BHT_ENTRIES_W         = 9;
localparam RAS_ENABLE                = 1;
localparam GSHARE_ENABLE             = 0;
localparam BHT_ENABLE                = 1;
localparam NUM_RAS_ENTRIES           = 8;
localparam NUM_RAS_ENTRIES_W         = 3;

reg         clk_i;
reg         rst_i;
reg         invalidate_i;
reg         branch_request_i;
reg         branch_is_taken_i;
reg         branch_is_not_taken_i;
reg [31:0]  branch_source_i;
reg         branch_is_call_i;
reg         branch_is_ret_i;
reg         branch_is_jmp_i;
reg [31:0]  branch_pc_i;
reg [31:0]  pc_f_i;
reg         pc_accept_i;

wire [31:0] next_pc_f_o;
wire [1:0]  next_taken_f_o;

riscv_npc #(
	 .SUPPORT_BRANCH_PREDICTION(SUPPORT_BRANCH_PREDICTION)
	,.NUM_BTB_ENTRIES(NUM_BTB_ENTRIES)
	,.NUM_BTB_ENTRIES_W(NUM_BTB_ENTRIES_W)
	,.NUM_BHT_ENTRIES(NUM_BHT_ENTRIES)
	,.NUM_BHT_ENTRIES_W(NUM_BHT_ENTRIES_W)
	,.RAS_ENABLE(RAS_ENABLE)
	,.GSHARE_ENABLE(GSHARE_ENABLE)
	,.BHT_ENABLE(BHT_ENABLE)
	,.NUM_RAS_ENTRIES(NUM_RAS_ENTRIES)
	,.NUM_RAS_ENTRIES_W(NUM_RAS_ENTRIES_W)
) dut (
	 .clk_i(clk_i)
	,.rst_i(rst_i)
	,.invalidate_i(invalidate_i)
	,.branch_request_i(branch_request_i)
	,.branch_is_taken_i(branch_is_taken_i)
	,.branch_is_not_taken_i(branch_is_not_taken_i)
	,.branch_source_i(branch_source_i)
	,.branch_is_call_i(branch_is_call_i)
	,.branch_is_ret_i(branch_is_ret_i)
	,.branch_is_jmp_i(branch_is_jmp_i)
	,.branch_pc_i(branch_pc_i)
	,.pc_f_i(pc_f_i)
	,.pc_accept_i(pc_accept_i)
	,.next_pc_f_o(next_pc_f_o)
	,.next_taken_f_o(next_taken_f_o)
);

// ------------------------------------------------------------
// Clock
// ------------------------------------------------------------
initial clk_i = 1'b0;
always #5 clk_i = ~clk_i;

// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------
task automatic clear_inputs();
begin
	invalidate_i         = 1'b0;
	branch_request_i     = 1'b0;
	branch_is_taken_i    = 1'b0;
	branch_is_not_taken_i= 1'b0;
	branch_source_i      = 32'b0;
	branch_is_call_i     = 1'b0;
	branch_is_ret_i      = 1'b0;
	branch_is_jmp_i      = 1'b0;
	branch_pc_i          = 32'b0;
	pc_f_i               = 32'b0;
	pc_accept_i          = 1'b0;
end
endtask

task automatic apply_reset();
begin
	clear_inputs();
	rst_i = 1'b1;
	repeat (3) @(posedge clk_i);
	rst_i = 1'b0;
	@(posedge clk_i);
end
endtask

task automatic train_branch(
	input [31:0] src_pc,
	input [31:0] tgt_pc,
	input        taken,
	input        is_call,
	input        is_ret,
	input        is_jmp
);
begin
	@(negedge clk_i);
	branch_request_i      = 1'b1;
	branch_is_taken_i     = taken;
	branch_is_not_taken_i = ~taken;
	branch_source_i       = src_pc;
	branch_pc_i           = tgt_pc;
	branch_is_call_i      = is_call;
	branch_is_ret_i       = is_ret;
	branch_is_jmp_i       = is_jmp;

	@(posedge clk_i);
	@(negedge clk_i);
	branch_request_i      = 1'b0;
	branch_is_taken_i     = 1'b0;
	branch_is_not_taken_i = 1'b0;
	branch_source_i       = 32'b0;
	branch_pc_i           = 32'b0;
	branch_is_call_i      = 1'b0;
	branch_is_ret_i       = 1'b0;
	branch_is_jmp_i       = 1'b0;
end
endtask

function automatic [31:0] seq_pc(input [31:0] pc);
	begin
		seq_pc = (pc & 32'hFFFF_FFF8) + 32'd8;
	end
endfunction

task automatic predict_from_pc(input [31:0] fetch_pc);
begin
	@(negedge clk_i);
	pc_f_i      = fetch_pc;
	pc_accept_i = 1'b1;
	#1;
end
endtask

task automatic expect_pc(
		input string name,
		input [31:0] exp_pc
	);
	begin
		if (next_pc_f_o !== exp_pc) begin
			$display("[FAIL ❌] %s | expected next_pc=0x%08x, got next_pc=0x%08x @ t=%0t",
					 name, exp_pc, next_pc_f_o, $time);
			$fatal;
		end
		else begin
			$display("[PASS ✅] %s | expected next_pc=0x%08x, got next_pc=0x%08x @ t=%0t",
					 name, exp_pc, next_pc_f_o, $time);
		end
	end
	endtask

task automatic expect_taken_nonzero(input string name);
		begin
			if (next_taken_f_o == 2'b00) begin
				$display("[FAIL ❌] %s | expected next_taken_f_o!=00, got next_taken_f_o=%b @ t=%0t",
						 name, next_taken_f_o, $time);
				$fatal;
			end
			else begin
				$display("[PASS ✅] %s | expected next_taken_f_o!=00, got next_taken_f_o=%b @ t=%0t",
						 name, next_taken_f_o, $time);
			end
		end
endtask

task automatic expect_taken_zero(input string name);
	begin
		if (next_taken_f_o !== 2'b00) begin
			$display("[FAIL ❌] %s | expected next_taken_f_o=00, got next_taken_f_o=%b @ t=%0t",
					 name, next_taken_f_o, $time);
			$fatal;
		end
		else begin
			$display("[PASS ✅] %s | expected next_taken_f_o=00, got next_taken_f_o=%b @ t=%0t",
					 name, next_taken_f_o, $time);
		end
	end
endtask

// ------------------------------------------------------------
// Tests
// ------------------------------------------------------------

task automatic test_reset_default_sequential();
	reg [31:0] exp_pc;
begin
	$display("\n---- test_reset_default_sequential ----");
	apply_reset();

	// pc + 8 because fetch is dual-issue aligned in this design
	predict_from_pc(32'h0000_1000);
	exp_pc = seq_pc(32'h0000_1000);
	expect_pc("after reset, sequential fetch", exp_pc);
	expect_taken_zero("after reset, no predicted taken");
end
endtask

task automatic test_jmp_btb_prediction();
begin
	$display("\n---- test_jmp_btb_prediction ----");
	apply_reset();

	// Train an unconditional jump
	train_branch(
		 32'h0000_2000,   // source
		 32'h0000_3000,   // target
		 1'b1,            // taken
		 1'b0,            // call
		 1'b0,            // ret
		 1'b1             // jmp
	);

	// Predict from same PC
	predict_from_pc(32'h0000_2000);
	expect_pc("BTB predicts jump target", 32'h0000_3000);
	expect_taken_nonzero("jump predicts taken");
end
endtask

task automatic test_taken_branch_prediction();
begin
	$display("\n---- test_taken_branch_prediction ----");
	apply_reset();

	// Because BHT entries start at 2'b11 in this design,
	// once BTB knows the branch, prediction should be taken.
	train_branch(
		 32'h0000_4000,
		 32'h0000_5000,
		 1'b1,
		 1'b0,
		 1'b0,
		 1'b0
	);

	predict_from_pc(32'h0000_4000);
	expect_pc("taken branch predicted to target", 32'h0000_5000);
	expect_taken_nonzero("taken branch marked taken");
end
endtask

task automatic test_not_taken_after_training();
	reg [31:0] exp_pc;
	integer k;
begin
	$display("\n---- test_not_taken_after_training ----");
	apply_reset();

	// First install the BTB entry
	train_branch(
		 32'h0000_6000,
		 32'h0000_7000,
		 1'b1,
		 1'b0,
		 1'b0,
		 1'b0
	);

	// Now repeatedly resolve it as not-taken to drive BHT counter down
	for (k = 0; k < 4; k = k + 1) begin
		train_branch(
			 32'h0000_6000,
			 32'h0000_7000,
			 1'b0,
			 1'b0,
			 1'b0,
			 1'b0
		);
	end

	predict_from_pc(32'h0000_6000);
	exp_pc = seq_pc(32'h0000_6000);
	expect_pc("branch predicted not taken -> sequential PC", exp_pc);
	expect_taken_zero("not taken has zero next_taken");
end
endtask

task automatic test_call_and_return_ras();
begin
	$display("\n---- test_call_and_return_ras ----");
	apply_reset();

	// Train a CALL at 0x8000 -> 0x9000
	// This should push return addr = 0x8004 into RAS
	train_branch(
		 32'h0000_8000,
		 32'h0000_9000,
		 1'b1,
		 1'b1,
		 1'b0,
		 1'b0
	);

	// Fetching call site should predict target
	predict_from_pc(32'h0000_8000);
	expect_pc("call predicted to target", 32'h0000_9000);
	expect_taken_nonzero("call predicts taken");

	// Train a RET at 0x9008
	// BTB says it's a return, RAS should supply 0x8004
	train_branch(
		 32'h0000_9008,
		 32'h0000_8004,   // actual return target
		 1'b1,
		 1'b0,
		 1'b1,
		 1'b0
	);

	// Fetch the RET instruction and expect RAS-based return prediction
	predict_from_pc(32'h0000_9008);
	expect_pc("return predicted from RAS", 32'h0000_8004);
	expect_taken_nonzero("return predicts taken");
end
endtask

task automatic test_invalidate_behavior();
	reg [31:0] exp_pc;
begin
	$display("\n---- test_invalidate_behavior ----");
	apply_reset();

	train_branch(
		 32'h0000_A000,
		 32'h0000_B000,
		 1'b1,
		 1'b0,
		 1'b0,
		 1'b1
	);

	predict_from_pc(32'h0000_A000);
	expect_pc("before invalidate, branch predicted", 32'h0000_B000);

	// Only meaningful if you patched invalidate_i into the design
	@(negedge clk_i);
	invalidate_i = 1'b1;
	@(posedge clk_i);
	@(negedge clk_i);
	invalidate_i = 1'b0;

	predict_from_pc(32'h0000_A000);
	exp_pc = seq_pc(32'h0000_A000);
	expect_pc("after invalidate, predictor cleared", exp_pc);
	expect_taken_zero("after invalidate, no taken prediction");
end
endtask

task automatic test_btb_miss_sequential();
	reg [31:0] exp_pc;
begin
	$display("\n---- test_btb_miss_sequential ----");
	apply_reset();

	predict_from_pc(32'h0000_C000);
	exp_pc = seq_pc(32'h0000_C000);

	expect_pc("BTB miss -> sequential fetch", exp_pc);
	expect_taken_zero("BTB miss -> no taken prediction");
end
endtask

task automatic test_nested_call_return_ras();
	begin
		$display("\n---- test_nested_call_return_ras ----");
		apply_reset();

		// CALL A: 0x1000 -> 0x2000, pushes 0x1004
		train_branch(32'h0000_1000, 32'h0000_2000, 1'b1, 1'b1, 1'b0, 1'b0);

		// CALL B: 0x2008 -> 0x3000, pushes 0x200C
		train_branch(32'h0000_2008, 32'h0000_3000, 1'b1, 1'b1, 1'b0, 1'b0);

		// RET from B at 0x3008 -> should predict 0x200C
		train_branch(32'h0000_3008, 32'h0000_200C, 1'b1, 1'b0, 1'b1, 1'b0);
		predict_from_pc(32'h0000_3008);
		expect_pc("nested RET #1 after resolved pop -> older RAS entry", 32'h0000_1004);
		expect_taken_nonzero("nested RET #1 predicts taken");

		// RET from A at 0x2010 -> should predict 0x1004
		train_branch(32'h0000_2010, 32'h0000_1004, 1'b1, 1'b0, 1'b1, 1'b0);
		predict_from_pc(32'h0000_2010);
		expect_pc("nested RET #2 -> next RAS entry", 32'h0000_1004);
		expect_taken_nonzero("nested RET #2 predicts taken");
	end
endtask

task automatic test_upper_half_btb_hit();
	begin
		$display("\n---- test_upper_half_btb_hit ----");
		apply_reset();

		// Train jump at upper-half address
		train_branch(32'h0000_D004, 32'h0000_E000, 1'b1, 1'b0, 1'b0, 1'b1);

		predict_from_pc(32'h0000_D004);
		expect_pc("upper-half BTB hit -> correct target", 32'h0000_E000);
		expect_taken_nonzero("upper-half BTB hit predicts taken");
	end
endtask

task automatic test_lower_pc_sees_upper_half_branch();
	begin
		$display("\n---- test_lower_pc_sees_upper_half_branch ----");
		apply_reset();

		// Train branch at upper-half slot
		train_branch(32'h0000_F004, 32'h0001_0000, 1'b1, 1'b0, 1'b0, 1'b1);

		// Fetch lower half of same 8-byte bundle
		predict_from_pc(32'h0000_F000);
		expect_pc("lower PC detects upper-half branch target", 32'h0001_0000);
		expect_taken_nonzero("lower PC sees upper-half taken");
	end
endtask

task automatic test_pc_accept_blocks_speculative_progress();
	begin
		$display("\n---- test_pc_accept_blocks_speculative_progress ----");
		apply_reset();

		train_branch(32'h0000_4000, 32'h0000_5000, 1'b1, 1'b1, 1'b0, 1'b0);

		@(negedge clk_i);
		pc_f_i      = 32'h0000_4000;
		pc_accept_i = 1'b0;
		#1;
		expect_pc("prediction visible even when accept low", 32'h0000_5000);

		// Keep same fetch again; speculative call push should not have advanced
		@(negedge clk_i);
		pc_f_i      = 32'h0000_4000;
		pc_accept_i = 1'b1;
		#1;
		expect_pc("accept later still predicts same call target", 32'h0000_5000);
	end
endtask

task automatic test_invalidate_clears_ras();
	reg [31:0] exp_pc;
begin
	$display("\n---- test_invalidate_clears_ras ----");
	apply_reset();

	train_branch(32'h0001_8000, 32'h0001_9000, 1'b1, 1'b1, 1'b0, 1'b0); // CALL
	train_branch(32'h0001_9008, 32'h0001_8004, 1'b1, 1'b0, 1'b1, 1'b0); // RET

	predict_from_pc(32'h0001_9008);
	expect_pc("before invalidate RET uses RAS", 32'h0001_8004);

	@(negedge clk_i);
	invalidate_i = 1'b1;
	@(posedge clk_i);
	@(negedge clk_i);
	invalidate_i = 1'b0;

	predict_from_pc(32'h0001_9008);
	exp_pc = seq_pc(32'h0001_9008);
	expect_pc("after invalidate RET no longer uses old RAS", exp_pc);
	expect_taken_zero("after invalidate RET not predicted");
end
endtask

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------
initial begin
	clear_inputs();
	test_reset_default_sequential();
	clear_inputs();
	test_jmp_btb_prediction();
	clear_inputs();
	test_taken_branch_prediction();
	clear_inputs();
	test_not_taken_after_training();
	clear_inputs();
	test_call_and_return_ras();
	clear_inputs();
	test_invalidate_behavior(); //k
	clear_inputs();
	test_btb_miss_sequential();
	clear_inputs();
	test_nested_call_return_ras(); // problomatic
	clear_inputs();
	test_upper_half_btb_hit(); 
	clear_inputs();
	test_lower_pc_sees_upper_half_branch();
	clear_inputs();
	test_pc_accept_blocks_speculative_progress(); 
	clear_inputs();
	test_invalidate_clears_ras();
	$display("\nALL TESTS COMPLETED");
	$finish;
end
endmodule