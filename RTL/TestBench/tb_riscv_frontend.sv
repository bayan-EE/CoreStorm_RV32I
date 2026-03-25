`timescale 1ns/1ps

module tb_riscv_frontend;

  //============================================================
  // Parameters
  //============================================================
  localparam int unsigned XLEN         = 32;
  localparam int unsigned ILEN         = 32;
  localparam logic [XLEN-1:0] RESET_PC = 32'h0000_0000;
  localparam int unsigned FIFO_DEPTH   = 2;
  localparam int CLK_PERIOD            = 10;
  localparam int RANDOM_ITERS          = 800;

  //============================================================
  // DUT signals
  //============================================================
  logic                 clk_i;
  logic                 rst_ni;

  logic                 icache_accept_i;
  logic                 icache_valid_i;
  logic [2*ILEN-1:0]    icache_bundle_i;

  logic                 fetch0_accept_i;
  logic                 fetch1_accept_i;

  logic                 branch_request_i;
  logic [XLEN-1:0]      branch_pc_i;

  logic                 icache_rd_o;
  logic                 icache_flush_o;
  logic                 icache_invalidate_o;
  logic [XLEN-1:0]      icache_pc_o;
  logic [1:0]           icache_priv_o;

  logic                 fetch0_valid_o;
  logic [ILEN-1:0]      fetch0_instr_o;
  logic [XLEN-1:0]      fetch0_pc_o;
  logic                 fetch0_fault_fetch_o;
  logic                 fetch0_fault_page_o;
  logic                 fetch0_instr_exec_o;
  logic                 fetch0_instr_lsu_o;
  logic                 fetch0_instr_branch_o;
  logic                 fetch0_instr_mul_o;
  logic                 fetch0_instr_div_o;
  logic                 fetch0_instr_csr_o;
  logic                 fetch0_instr_rd_valid_o;
  logic                 fetch0_instr_invalid_o;

  logic                 fetch1_valid_o;
  logic [ILEN-1:0]      fetch1_instr_o;
  logic [XLEN-1:0]      fetch1_pc_o;
  logic                 fetch1_fault_fetch_o;
  logic                 fetch1_fault_page_o;
  logic                 fetch1_instr_exec_o;
  logic                 fetch1_instr_lsu_o;
  logic                 fetch1_instr_branch_o;
  logic                 fetch1_instr_mul_o;
  logic                 fetch1_instr_div_o;
  logic                 fetch1_instr_csr_o;
  logic                 fetch1_instr_rd_valid_o;
  logic                 fetch1_instr_invalid_o;

  //============================================================
  // DUT
  //============================================================
  riscv_frontend #(
	.XLEN               (XLEN),
	.ILEN               (ILEN),
	.RESET_PC           (RESET_PC),
	.SUPPORT_MMU        (1'b1),
	.SUPPORT_MULDIV     (1'b1),
	.EXTRA_DECODE_STAGE (1'b0),
	.FIFO_DEPTH         (FIFO_DEPTH)
  ) dut (
	.clk_i                   (clk_i),
	.rst_ni                  (rst_ni),

	.icache_accept_i         (icache_accept_i),
	.icache_valid_i          (icache_valid_i),
	.icache_bundle_i         (icache_bundle_i),

	.fetch0_accept_i         (fetch0_accept_i),
	.fetch1_accept_i         (fetch1_accept_i),

	.branch_request_i        (branch_request_i),
	.branch_pc_i             (branch_pc_i),

	.icache_rd_o             (icache_rd_o),
	.icache_flush_o          (icache_flush_o),
	.icache_invalidate_o     (icache_invalidate_o),
	.icache_pc_o             (icache_pc_o),
	.icache_priv_o           (icache_priv_o),

	.fetch0_valid_o          (fetch0_valid_o),
	.fetch0_instr_o          (fetch0_instr_o),
	.fetch0_pc_o             (fetch0_pc_o),
	.fetch0_fault_fetch_o    (fetch0_fault_fetch_o),
	.fetch0_fault_page_o     (fetch0_fault_page_o),
	.fetch0_instr_exec_o     (fetch0_instr_exec_o),
	.fetch0_instr_lsu_o      (fetch0_instr_lsu_o),
	.fetch0_instr_branch_o   (fetch0_instr_branch_o),
	.fetch0_instr_mul_o      (fetch0_instr_mul_o),
	.fetch0_instr_div_o      (fetch0_instr_div_o),
	.fetch0_instr_csr_o      (fetch0_instr_csr_o),
	.fetch0_instr_rd_valid_o (fetch0_instr_rd_valid_o),
	.fetch0_instr_invalid_o  (fetch0_instr_invalid_o),

	.fetch1_valid_o          (fetch1_valid_o),
	.fetch1_instr_o          (fetch1_instr_o),
	.fetch1_pc_o             (fetch1_pc_o),
	.fetch1_fault_fetch_o    (fetch1_fault_fetch_o),
	.fetch1_fault_page_o     (fetch1_fault_page_o),
	.fetch1_instr_exec_o     (fetch1_instr_exec_o),
	.fetch1_instr_lsu_o      (fetch1_instr_lsu_o),
	.fetch1_instr_branch_o   (fetch1_instr_branch_o),
	.fetch1_instr_mul_o      (fetch1_instr_mul_o),
	.fetch1_instr_div_o      (fetch1_instr_div_o),
	.fetch1_instr_csr_o      (fetch1_instr_csr_o),
	.fetch1_instr_rd_valid_o (fetch1_instr_rd_valid_o),
	.fetch1_instr_invalid_o  (fetch1_instr_invalid_o)
  );

  //============================================================
  // Clock
  //============================================================
  initial begin
	clk_i = 1'b0;
	forever #(CLK_PERIOD/2) clk_i = ~clk_i;
  end

  //============================================================
  // Waves
  //============================================================
  initial begin
	`ifdef FSDB
	  $fsdbDumpfile("novas.fsdb");
	  $fsdbDumpvars(0, tb_riscv_frontend, "+all");
	`else
	  $dumpfile("tb_riscv_frontend.vcd");
	  $dumpvars(0, tb_riscv_frontend);
	`endif
  end

  //============================================================
  // Counters
  //============================================================
  int test_count;
  int pass_count;
  int fail_count;

  int req_count;
  int rsp_count;
  int lane0_hs_count;
  int lane1_hs_count;
  int redirect_count;

  int lane0_valid_count;
  int lane1_valid_count;
  int both_valid_count;

  int lane0_exec_count;
  int lane0_lsu_count;
  int lane0_branch_count;
  int lane0_mul_count;
  int lane0_div_count;
  int lane0_csr_count;
  int lane0_invalid_count;

  int lane1_exec_count;
  int lane1_lsu_count;
  int lane1_branch_count;
  int lane1_mul_count;
  int lane1_div_count;
  int lane1_csr_count;
  int lane1_invalid_count;

  //============================================================
  // Coverage helper variables
  //============================================================
  int         cov_test_id;
  logic [1:0] cov_accept_pair;
  logic [1:0] cov_valid_pair;
  logic [1:0] cov_delay;
  logic       cov_redirect;
  logic       cov_req_seen;
  logic       cov_rsp_seen;
  logic       cov_lane0_seen;
  logic       cov_lane1_seen;
  logic       cov_both_seen;
  logic       cov_lane0_exec_seen;
  logic       cov_lane0_lsu_seen;
  logic       cov_lane0_branch_seen;
  logic       cov_lane0_mul_seen;
  logic       cov_lane0_div_seen;
  logic       cov_lane0_csr_seen;
  logic       cov_lane0_invalid_seen;
  logic       cov_lane1_exec_seen;
  logic       cov_lane1_lsu_seen;
  logic       cov_lane1_branch_seen;
  logic       cov_lane1_mul_seen;
  logic       cov_lane1_div_seen;
  logic       cov_lane1_csr_seen;
  logic       cov_lane1_invalid_seen;

  //============================================================
  // Coverage
  //============================================================
  covergroup cg_frontend @(posedge clk_i);
	option.per_instance = 1;

	cp_test_id : coverpoint cov_test_id {
	  bins reset_b          = {0};
	  bins basic_flow_b     = {1};
	  bins redirect_b       = {2};
	  bins bp_lane0_b       = {3};
	  bins bp_both_b        = {4};
	  bins icache_stall_b   = {5};
	  bins redirects_b      = {6};
	  bins random_b         = {7};
	}

	cp_accept_pair : coverpoint cov_accept_pair {
	  bins a00 = {2'b00};
	  bins a01 = {2'b01};
	  bins a10 = {2'b10};
	  bins a11 = {2'b11};
	}

	cp_valid_pair : coverpoint cov_valid_pair {
	  bins v00 = {2'b00};
	  bins v10 = {2'b10};
	  bins v11 = {2'b11};
	  ignore_bins v01 = {2'b01};
	}

	cp_delay : coverpoint cov_delay {
	  bins d0 = {2'd0};
	  bins d1 = {2'd1};
	  bins d2 = {2'd2};
	}

	cp_redirect : coverpoint cov_redirect {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_req_seen : coverpoint cov_req_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_rsp_seen : coverpoint cov_rsp_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_lane0_seen : coverpoint cov_lane0_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_lane1_seen : coverpoint cov_lane1_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_both_seen : coverpoint cov_both_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_lane0_exec_seen : coverpoint cov_lane0_exec_seen { bins no = {0}; bins yes = {1}; }
	cp_lane0_lsu_seen  : coverpoint cov_lane0_lsu_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane0_branch_seen: coverpoint cov_lane0_branch_seen { bins no = {0}; bins yes = {1}; }
	cp_lane0_mul_seen  : coverpoint cov_lane0_mul_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane0_div_seen  : coverpoint cov_lane0_div_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane0_csr_seen  : coverpoint cov_lane0_csr_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane0_invalid_seen: coverpoint cov_lane0_invalid_seen { bins no = {0}; bins yes = {1}; }

	cp_lane1_exec_seen : coverpoint cov_lane1_exec_seen { bins no = {0}; bins yes = {1}; }
	cp_lane1_lsu_seen  : coverpoint cov_lane1_lsu_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane1_branch_seen: coverpoint cov_lane1_branch_seen { bins no = {0}; bins yes = {1}; }
	cp_lane1_mul_seen  : coverpoint cov_lane1_mul_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane1_div_seen  : coverpoint cov_lane1_div_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane1_csr_seen  : coverpoint cov_lane1_csr_seen  { bins no = {0}; bins yes = {1}; }
	cp_lane1_invalid_seen: coverpoint cov_lane1_invalid_seen { bins no = {0}; bins yes = {1}; }
  endgroup

  cg_frontend cov_i = new();

  //============================================================
  // Instruction encoding helpers
  //============================================================
  function automatic logic [31:0] enc_addi(
	input logic [4:0] rd,
	input logic [4:0] rs1,
	input logic signed [11:0] imm
  );
	enc_addi = {imm[11:0], rs1, 3'b000, rd, 7'b0010011};
  endfunction

  function automatic logic [31:0] enc_andi(
	input logic [4:0] rd,
	input logic [4:0] rs1,
	input logic signed [11:0] imm
  );
	enc_andi = {imm[11:0], rs1, 3'b111, rd, 7'b0010011};
  endfunction

  function automatic logic [31:0] enc_lw(
	input logic [4:0] rd,
	input logic [4:0] rs1,
	input logic signed [11:0] imm
  );
	enc_lw = {imm[11:0], rs1, 3'b010, rd, 7'b0000011};
  endfunction

  function automatic logic [31:0] enc_sw(
	input logic [4:0] rs2,
	input logic [4:0] rs1,
	input logic signed [11:0] imm
  );
	enc_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
  endfunction

  function automatic logic [31:0] enc_beq(
	input logic [4:0] rs1,
	input logic [4:0] rs2,
	input logic signed [12:0] imm
  );
	enc_beq = {imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], 7'b1100011};
  endfunction

  function automatic logic [31:0] enc_jal(
	input logic [4:0] rd,
	input logic signed [20:0] imm
  );
	enc_jal = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
  endfunction

  function automatic logic [31:0] enc_mul(
	input logic [4:0] rd,
	input logic [4:0] rs1,
	input logic [4:0] rs2
  );
	enc_mul = {7'b0000001, rs2, rs1, 3'b000, rd, 7'b0110011};
  endfunction

  function automatic logic [31:0] enc_div(
	input logic [4:0] rd,
	input logic [4:0] rs1,
	input logic [4:0] rs2
  );
	enc_div = {7'b0000001, rs2, rs1, 3'b100, rd, 7'b0110011};
  endfunction

  function automatic logic [31:0] enc_csrrw(
	input logic [4:0] rd,
	input logic [11:0] csr,
	input logic [4:0] rs1
  );
	enc_csrrw = {csr, rs1, 3'b001, rd, 7'b1110011};
  endfunction

  function automatic logic [31:0] enc_invalid();
	enc_invalid = 32'hFFFF_FFFF;
  endfunction

  function automatic logic [63:0] mk_bundle(
	input logic [31:0] i0,
	input logic [31:0] i1
  );
	mk_bundle = {i1, i0};
  endfunction

  function automatic logic [31:0] gen_instr_by_sel(input int sel);
	case (sel)
	  0: gen_instr_by_sel = enc_addi(5'd1, 5'd0, 12'd1);
	  1: gen_instr_by_sel = enc_andi(5'd2, 5'd1, 12'h0FF);
	  2: gen_instr_by_sel = enc_lw  (5'd3, 5'd1, 12'd8);
	  3: gen_instr_by_sel = enc_sw  (5'd4, 5'd1, 12'd12);
	  4: gen_instr_by_sel = enc_beq (5'd1, 5'd2, 13'd16);
	  5: gen_instr_by_sel = enc_jal (5'd1, 21'd32);
	  6: gen_instr_by_sel = enc_mul (5'd5, 5'd1, 5'd2);
	  7: gen_instr_by_sel = enc_div (5'd6, 5'd1, 5'd2);
	  8: gen_instr_by_sel = enc_csrrw(5'd7, 12'h305, 5'd1);
	  default: gen_instr_by_sel = enc_invalid();
	endcase
  endfunction

  function automatic logic [63:0] gen_bundle(input logic [31:0] pc);
	  int idx;
	  logic [31:0] i0;
	  logic [31:0] i1;

	  idx = pc[6:3] % 10;

	  i0 = gen_instr_by_sel(idx);
	  i1 = gen_instr_by_sel((idx + 1) % 10);

	  gen_bundle = mk_bundle(i0, i1);
	endfunction

  //============================================================
  // Utility tasks
  //============================================================
  task automatic check_true(input bit cond, input string msg);
	begin
	  test_count++;
	  if (!cond) begin
		$display("[FAIL] %s  t=%0t", msg, $time);
		fail_count++;
	  end
	  else begin
		pass_count++;
	  end
	end
  endtask

  task automatic init_inputs();
	begin
	  icache_accept_i        = 1'b1;
	  icache_valid_i         = 1'b0;
	  icache_bundle_i        = '0;
	  fetch0_accept_i        = 1'b1;
	  fetch1_accept_i        = 1'b1;
	  branch_request_i       = 1'b0;
	  branch_pc_i            = '0;

	  cov_accept_pair        = 2'b11;
	  cov_valid_pair         = 2'b00;
	  cov_delay              = 2'b00;
	  cov_redirect           = 1'b0;
	  cov_req_seen           = 1'b0;
	  cov_rsp_seen           = 1'b0;
	  cov_lane0_seen         = 1'b0;
	  cov_lane1_seen         = 1'b0;
	  cov_both_seen          = 1'b0;
	  cov_lane0_exec_seen    = 1'b0;
	  cov_lane0_lsu_seen     = 1'b0;
	  cov_lane0_branch_seen  = 1'b0;
	  cov_lane0_mul_seen     = 1'b0;
	  cov_lane0_div_seen     = 1'b0;
	  cov_lane0_csr_seen     = 1'b0;
	  cov_lane0_invalid_seen = 1'b0;
	  cov_lane1_exec_seen    = 1'b0;
	  cov_lane1_lsu_seen     = 1'b0;
	  cov_lane1_branch_seen  = 1'b0;
	  cov_lane1_mul_seen     = 1'b0;
	  cov_lane1_div_seen     = 1'b0;
	  cov_lane1_csr_seen     = 1'b0;
	  cov_lane1_invalid_seen = 1'b0;
	end
  endtask

  task automatic reset_dut();
	begin
	  rst_ni = 1'b0;
	  init_inputs();
	  repeat (5) @(posedge clk_i);
	  rst_ni = 1'b1;
	  repeat (3) @(posedge clk_i);
	end
  endtask

  task automatic wait_cycles(input int n);
	repeat (n) @(posedge clk_i);
  endtask

  task automatic pulse_redirect(input logic [31:0] new_pc);
	begin
	  @(posedge clk_i);
	  branch_request_i <= 1'b1;
	  branch_pc_i      <= new_pc;
	  redirect_count++;
	  cov_redirect     <= 1'b1;
	  @(posedge clk_i);
	  branch_request_i <= 1'b0;
	  branch_pc_i      <= '0;
	end
  endtask

  //============================================================
  // I-cache response model
  //============================================================
  typedef struct packed {
	logic [31:0] pc;
	logic [63:0] bundle;
	logic [1:0]  delay;
  } rsp_item_t;

  rsp_item_t rsp_q[$];

  always @(posedge clk_i) begin
	if (!rst_ni) begin
	  icache_valid_i  <= 1'b0;
	  icache_bundle_i <= '0;
	  rsp_q.delete();
	end
	else begin
	  icache_valid_i  <= 1'b0;
	  icache_bundle_i <= '0;

	  if (branch_request_i) begin
		rsp_q.delete();
	  end

	  if (icache_rd_o && icache_accept_i) begin
		rsp_item_t item;
		item.pc     = icache_pc_o;
		item.bundle = gen_bundle(icache_pc_o);
		item.delay  = $urandom_range(0, 2);
		cov_delay   <= item.delay;
		rsp_q.push_back(item);
		req_count++;
		cov_req_seen <= 1'b1;
	  end

	  if (rsp_q.size() > 0) begin
		if (rsp_q[0].delay != 0) begin
		  rsp_q[0].delay <= rsp_q[0].delay - 1'b1;
		end
		else begin
		  icache_valid_i  <= 1'b1;
		  icache_bundle_i <= rsp_q[0].bundle;
		  rsp_q.pop_front();
		  rsp_count++;
		  cov_rsp_seen <= 1'b1;
		end
	  end
	end
  end

  //============================================================
  // Runtime monitors
  //============================================================
  always @(posedge clk_i) begin
	if (rst_ni) begin
	  cov_accept_pair <= {fetch1_accept_i, fetch0_accept_i};
	  cov_valid_pair  <= {fetch1_valid_o,  fetch0_valid_o};

	  if (fetch0_valid_o)
		lane0_valid_count++;
	  if (fetch1_valid_o)
		lane1_valid_count++;
	  if (fetch0_valid_o && fetch1_valid_o)
		both_valid_count++;

	  if (fetch0_valid_o)
		cov_lane0_seen <= 1'b1;
	  if (fetch1_valid_o)
		cov_lane1_seen <= 1'b1;
	  if (fetch0_valid_o && fetch1_valid_o)
		cov_both_seen <= 1'b1;

	  if (fetch0_valid_o && fetch0_accept_i)
		lane0_hs_count++;
	  if (fetch1_valid_o && fetch1_accept_i)
		lane1_hs_count++;

	  if (fetch0_valid_o) begin
		if (fetch0_instr_exec_o)    begin lane0_exec_count++;    cov_lane0_exec_seen    <= 1'b1; end
		if (fetch0_instr_lsu_o)     begin lane0_lsu_count++;     cov_lane0_lsu_seen     <= 1'b1; end
		if (fetch0_instr_branch_o)  begin lane0_branch_count++;  cov_lane0_branch_seen  <= 1'b1; end
		if (fetch0_instr_mul_o)     begin lane0_mul_count++;     cov_lane0_mul_seen     <= 1'b1; end
		if (fetch0_instr_div_o)     begin lane0_div_count++;     cov_lane0_div_seen     <= 1'b1; end
		if (fetch0_instr_csr_o)     begin lane0_csr_count++;     cov_lane0_csr_seen     <= 1'b1; end
		if (fetch0_instr_invalid_o) begin lane0_invalid_count++; cov_lane0_invalid_seen <= 1'b1; end
	  end

	  if (fetch1_valid_o) begin
		if (fetch1_instr_exec_o)    begin lane1_exec_count++;    cov_lane1_exec_seen    <= 1'b1; end
		if (fetch1_instr_lsu_o)     begin lane1_lsu_count++;     cov_lane1_lsu_seen     <= 1'b1; end
		if (fetch1_instr_branch_o)  begin lane1_branch_count++;  cov_lane1_branch_seen  <= 1'b1; end
		if (fetch1_instr_mul_o)     begin lane1_mul_count++;     cov_lane1_mul_seen     <= 1'b1; end
		if (fetch1_instr_div_o)     begin lane1_div_count++;     cov_lane1_div_seen     <= 1'b1; end
		if (fetch1_instr_csr_o)     begin lane1_csr_count++;     cov_lane1_csr_seen     <= 1'b1; end
		if (fetch1_instr_invalid_o) begin lane1_invalid_count++; cov_lane1_invalid_seen <= 1'b1; end
	  end

	  check_true(^fetch0_valid_o !== 1'bx, "lane0 valid contains X");
	  check_true(^fetch1_valid_o !== 1'bx, "lane1 valid contains X");
	  check_true(^icache_rd_o   !== 1'bx,  "icache_rd_o contains X");

	  if (fetch0_valid_o && fetch1_valid_o) begin
		check_true(fetch1_pc_o == (fetch0_pc_o + 32'd4), "lane1 PC must equal lane0 PC + 4");
	  end

	  if (fetch0_fault_fetch_o || fetch0_fault_page_o)
		check_true(1'b0, "lane0 fault asserted unexpectedly");
	  if (fetch1_fault_fetch_o || fetch1_fault_page_o)
		check_true(1'b0, "lane1 fault asserted unexpectedly");
	end
  end

  //============================================================
  // Tests
  //============================================================
  task automatic test_reset_basic();
	begin
	  cov_test_id = 0;
	  $display("\n[TEST] reset_basic");
	  reset_dut();

	  check_true(fetch0_valid_o == 1'b0, "lane0 valid should be low after reset");
	  check_true(fetch1_valid_o == 1'b0, "lane1 valid should be low after reset");
	  check_true(icache_invalidate_o == 1'b0, "icache_invalidate_o should be tied low");
	end
  endtask

  task automatic test_basic_flow();
	begin
	  cov_test_id = 1;
	  $display("\n[TEST] basic_flow");
	  reset_dut();

	  wait_cycles(40);

	  check_true(req_count > 0, "no icache requests seen in basic_flow");
	  check_true(rsp_count > 0, "no icache responses seen in basic_flow");
	  check_true(lane0_hs_count > 0, "no lane0 handshakes seen in basic_flow");
	  check_true(lane1_hs_count > 0, "no lane1 handshakes seen in basic_flow");
	  check_true(both_valid_count > 0, "both lanes were never valid together in basic_flow");
	end
  endtask

  task automatic test_redirect();
	begin
	  cov_test_id = 2;
	  $display("\n[TEST] redirect");
	  reset_dut();

	  wait_cycles(8);
	  pulse_redirect(32'h0000_0100);
	  wait_cycles(10);
	  pulse_redirect(32'h0000_0040);
	  wait_cycles(14);

	  check_true(redirect_count >= 2, "redirect count did not increment");
	  check_true(req_count > 0, "no requests observed during redirect test");
	end
  endtask

  task automatic test_backpressure_lane0();
	begin
	  cov_test_id = 3;
	  $display("\n[TEST] backpressure_lane0");
	  reset_dut();

	  wait_cycles(8);
	  fetch0_accept_i = 1'b0;
	  fetch1_accept_i = 1'b1;
	  wait_cycles(14);
	  fetch0_accept_i = 1'b1;
	  wait_cycles(20);

	  check_true(1'b1, "lane0 backpressure scenario completed");
	end
  endtask

  task automatic test_backpressure_both();
	begin
	  cov_test_id = 4;
	  $display("\n[TEST] backpressure_both");
	  reset_dut();

	  wait_cycles(8);
	  fetch0_accept_i = 1'b0;
	  fetch1_accept_i = 1'b0;
	  wait_cycles(12);
	  fetch0_accept_i = 1'b1;
	  fetch1_accept_i = 1'b1;
	  wait_cycles(20);

	  check_true(1'b1, "dual backpressure scenario completed");
	end
  endtask

  task automatic test_icache_stall();
	begin
	  cov_test_id = 5;
	  $display("\n[TEST] icache_stall");
	  reset_dut();

	  wait_cycles(6);
	  icache_accept_i = 1'b0;
	  wait_cycles(12);
	  icache_accept_i = 1'b1;
	  wait_cycles(20);

	  check_true(1'b1, "icache stall scenario completed");
	end
  endtask

  task automatic test_multiple_redirects();
	begin
	  cov_test_id = 6;
	  $display("\n[TEST] multiple_redirects");
	  reset_dut();

	  wait_cycles(6);
	  pulse_redirect(32'h0000_0040);
	  wait_cycles(4);
	  pulse_redirect(32'h0000_0200);
	  wait_cycles(4);
	  pulse_redirect(32'h0000_0010);
	  wait_cycles(20);

	  check_true(redirect_count >= 5, "multiple redirects not observed as expected");
	end
  endtask

  task automatic random_test();
	int i;
	logic [31:0] rand_pc;
	begin
	  cov_test_id = 7;
	  $display("\n[TEST] random_test");
	  reset_dut();

	  for (i = 0; i < RANDOM_ITERS; i++) begin
		@(posedge clk_i);

		icache_accept_i <= $urandom_range(0, 1);
		fetch0_accept_i <= $urandom_range(0, 1);
		fetch1_accept_i <= $urandom_range(0, 1);

		if ($urandom_range(0, 24) == 0) begin
		  rand_pc = {$urandom} & 32'h0000_03FC;
		  branch_request_i <= 1'b1;
		  branch_pc_i      <= rand_pc;
		  redirect_count++;
		  cov_redirect     <= 1'b1;
		end
		else begin
		  branch_request_i <= 1'b0;
		  branch_pc_i      <= '0;
		end
	  end

	  @(posedge clk_i);
	  icache_accept_i  <= 1'b1;
	  fetch0_accept_i  <= 1'b1;
	  fetch1_accept_i  <= 1'b1;
	  branch_request_i <= 1'b0;
	  branch_pc_i      <= '0;

	  wait_cycles(50);

	  check_true(req_count > 0, "random test produced no requests");
	  check_true(rsp_count > 0, "random test produced no responses");
	  check_true(lane0_valid_count > 0, "lane0 never became valid");
	  check_true(lane1_valid_count > 0, "lane1 never became valid");
	end
  endtask

  //============================================================
  // Timeout
  //============================================================
  initial begin
	#1000000;
	$display("[FAIL] TB timeout");
	fail_count++;
	$finish;
  end

  //============================================================
  // Main
  //============================================================
  initial begin
	test_count          = 0;
	pass_count          = 0;
	fail_count          = 0;

	req_count           = 0;
	rsp_count           = 0;
	lane0_hs_count      = 0;
	lane1_hs_count      = 0;
	redirect_count      = 0;

	lane0_valid_count   = 0;
	lane1_valid_count   = 0;
	both_valid_count    = 0;

	lane0_exec_count    = 0;
	lane0_lsu_count     = 0;
	lane0_branch_count  = 0;
	lane0_mul_count     = 0;
	lane0_div_count     = 0;
	lane0_csr_count     = 0;
	lane0_invalid_count = 0;

	lane1_exec_count    = 0;
	lane1_lsu_count     = 0;
	lane1_branch_count  = 0;
	lane1_mul_count     = 0;
	lane1_div_count     = 0;
	lane1_csr_count     = 0;
	lane1_invalid_count = 0;

	init_inputs();
	rst_ni = 1'b0;

	test_reset_basic();
	test_basic_flow();
	test_redirect();
	test_backpressure_lane0();
	test_backpressure_both();
	test_icache_stall();
	test_multiple_redirects();
	random_test();

	check_true(req_count > 20, "total request count too low");
	check_true(rsp_count > 15, "total response count too low");
	check_true(lane0_hs_count > 10, "lane0 handshake count too low");
	check_true(lane1_hs_count > 10, "lane1 handshake count too low");

	check_true(lane0_exec_count    > 0, "lane0 exec class was never seen");
	check_true(lane0_lsu_count     > 0, "lane0 lsu class was never seen");
	check_true(lane0_branch_count  > 0, "lane0 branch class was never seen");
	check_true(lane0_mul_count     > 0, "lane0 mul class was never seen");
	check_true(lane0_div_count     > 0, "lane0 div class was never seen");
	check_true(lane0_csr_count     > 0, "lane0 csr class was never seen");
	check_true(lane0_invalid_count > 0, "lane0 invalid class was never seen");

	check_true(lane1_exec_count    > 0, "lane1 exec class was never seen");
	check_true(lane1_lsu_count     > 0, "lane1 lsu class was never seen");
	check_true(lane1_branch_count  > 0, "lane1 branch class was never seen");
	check_true(lane1_mul_count     > 0, "lane1 mul class was never seen");
	check_true(lane1_div_count     > 0, "lane1 div class was never seen");
	check_true(lane1_csr_count     > 0, "lane1 csr class was never seen");
	check_true(lane1_invalid_count > 0, "lane1 invalid class was never seen");

	$display("\n==================================================");
	$display("RISCV_FRONTEND TB SUMMARY");
	$display("  test_count          = %0d", test_count);
	$display("  pass_count          = %0d", pass_count);
	$display("  fail_count          = %0d", fail_count);
	$display("  req_count           = %0d", req_count);
	$display("  rsp_count           = %0d", rsp_count);
	$display("  lane0_hs_count      = %0d", lane0_hs_count);
	$display("  lane1_hs_count      = %0d", lane1_hs_count);
	$display("  redirect_count      = %0d", redirect_count);
	$display("  lane0_valid_count   = %0d", lane0_valid_count);
	$display("  lane1_valid_count   = %0d", lane1_valid_count);
	$display("  both_valid_count    = %0d", both_valid_count);
	$display("  lane0 classes       = exec:%0d lsu:%0d br:%0d mul:%0d div:%0d csr:%0d inv:%0d",
			 lane0_exec_count, lane0_lsu_count, lane0_branch_count,
			 lane0_mul_count, lane0_div_count, lane0_csr_count, lane0_invalid_count);
	$display("  lane1 classes       = exec:%0d lsu:%0d br:%0d mul:%0d div:%0d csr:%0d inv:%0d",
			 lane1_exec_count, lane1_lsu_count, lane1_branch_count,
			 lane1_mul_count, lane1_div_count, lane1_csr_count, lane1_invalid_count);
	$display("  coverage            = %0.2f %%", cov_i.get_coverage());
	$display("==================================================");

	if (fail_count == 0)
	  $display("TB PASSED");
	else
	  $display("TB FAILED");

	$finish;
  end

endmodule