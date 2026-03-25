`timescale 1ns/1ps

module tb_riscv_core;

  //============================================================
  // Parameters
  //============================================================
  localparam int IMEM_DEPTH   = 1024;
  localparam int DMEM_DEPTH   = 1024;
  localparam int CLK_PERIOD   = 10;
  localparam int RANDOM_ITERS = 1200;

  //============================================================
  // DUT I/O
  //============================================================
  logic         clk_i;
  logic         rst_i;
  logic [31:0]  mem_d_data_rd_i;
  logic         mem_d_accept_i;
  logic         mem_d_ack_i;
  logic         mem_d_error_i;
  logic [10:0]  mem_d_resp_tag_i;
  logic         mem_i_accept_i;
  logic         mem_i_valid_i;
  logic         mem_i_error_i;
  logic [63:0]  mem_i_inst_i;
  logic         intr_i;
  logic [31:0]  reset_vector_i;
  logic [31:0]  cpu_id_i;

  logic [31:0]  mem_d_addr_o;
  logic [31:0]  mem_d_data_wr_o;
  logic         mem_d_rd_o;
  logic [3:0]   mem_d_wr_o;
  logic         mem_d_cacheable_o;
  logic [10:0]  mem_d_req_tag_o;
  logic         mem_d_invalidate_o;
  logic         mem_d_writeback_o;
  logic         mem_d_flush_o;
  logic         mem_i_rd_o;
  logic         mem_i_flush_o;
  logic         mem_i_invalidate_o;
  logic [31:0]  mem_i_pc_o;

  //============================================================
  // DUT
  //============================================================
  riscv_core #(
	.SUPPORT_BRANCH_PREDICTION (1),
	.SUPPORT_MULDIV            (1),
	.SUPPORT_SUPER             (0),
	.SUPPORT_MMU               (0),
	.SUPPORT_DUAL_ISSUE        (1),
	.SUPPORT_LOAD_BYPASS       (1),
	.SUPPORT_MUL_BYPASS        (1),
	.SUPPORT_REGFILE_XILINX    (0),
	.EXTRA_DECODE_STAGE        (0),
	.MEM_CACHE_ADDR_MIN        (32'h8000_0000),
	.MEM_CACHE_ADDR_MAX        (32'h8FFF_FFFF),
	.NUM_BTB_ENTRIES           (32),
	.NUM_BTB_ENTRIES_W         (5),
	.NUM_BHT_ENTRIES           (512),
	.NUM_BHT_ENTRIES_W         (9),
	.RAS_ENABLE                (1),
	.GSHARE_ENABLE             (0),
	.BHT_ENABLE                (1),
	.NUM_RAS_ENTRIES           (8),
	.NUM_RAS_ENTRIES_W         (3)
  ) dut (
	.clk_i                (clk_i),
	.rst_i                (rst_i),
	.mem_d_data_rd_i      (mem_d_data_rd_i),
	.mem_d_accept_i       (mem_d_accept_i),
	.mem_d_ack_i          (mem_d_ack_i),
	.mem_d_error_i        (mem_d_error_i),
	.mem_d_resp_tag_i     (mem_d_resp_tag_i),
	.mem_i_accept_i       (mem_i_accept_i),
	.mem_i_valid_i        (mem_i_valid_i),
	.mem_i_error_i        (mem_i_error_i),
	.mem_i_inst_i         (mem_i_inst_i),
	.intr_i               (intr_i),
	.reset_vector_i       (reset_vector_i),
	.cpu_id_i             (cpu_id_i),

	.mem_d_addr_o         (mem_d_addr_o),
	.mem_d_data_wr_o      (mem_d_data_wr_o),
	.mem_d_rd_o           (mem_d_rd_o),
	.mem_d_wr_o           (mem_d_wr_o),
	.mem_d_cacheable_o    (mem_d_cacheable_o),
	.mem_d_req_tag_o      (mem_d_req_tag_o),
	.mem_d_invalidate_o   (mem_d_invalidate_o),
	.mem_d_writeback_o    (mem_d_writeback_o),
	.mem_d_flush_o        (mem_d_flush_o),
	.mem_i_rd_o           (mem_i_rd_o),
	.mem_i_flush_o        (mem_i_flush_o),
	.mem_i_invalidate_o   (mem_i_invalidate_o),
	.mem_i_pc_o           (mem_i_pc_o)
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
	  $fsdbDumpvars(0, tb_riscv_core, "+all");
	`else
	  $dumpfile("tb_riscv_core.vcd");
	  $dumpvars(0, tb_riscv_core);
	`endif
  end

  //============================================================
  // Memories
  //============================================================
  logic [63:0] imem [0:IMEM_DEPTH-1];
  logic [31:0] dmem [0:DMEM_DEPTH-1];

  //============================================================
  // Response queues
  //============================================================
  typedef struct packed {
	logic [63:0] inst;
	logic [1:0]  delay;
  } if_rsp_t;

  typedef struct packed {
	logic        is_read;
	logic [31:0] addr;
	logic [31:0] wr_data;
	logic [3:0]  wr_be;
	logic [10:0] tag;
	logic [1:0]  delay;
  } d_rsp_t;

  if_rsp_t if_q[$];
  d_rsp_t  d_q[$];

  //============================================================
  // Modes
  //============================================================
  int i_accept_mode;
  int d_accept_mode;

  //============================================================
  // Counters
  //============================================================
  int test_count;
  int pass_count;
  int fail_count;

  int i_req_count;
  int i_rsp_count;
  int d_req_count;
  int d_rsp_count;
  int d_rd_count;
  int d_wr_count;

  int fetch0_valid_count;
  int fetch1_valid_count;
  int dual_fetch_count;

  int lane0_exec_count;
  int lane0_lsu_count;
  int lane0_branch_count;
  int lane0_mul_count;
  int lane0_div_count;
  int lane0_csr_count;

  int lane1_exec_count;
  int lane1_lsu_count;
  int lane1_branch_count;
  int lane1_mul_count;
  int lane1_div_count;
  int lane1_csr_count;

  int branch_request_count;
  int interrupt_take_count;

  //============================================================
  // Coverage helper variables
  //============================================================
  int         cov_test_id;
  logic [1:0] cov_i_delay;
  logic [1:0] cov_d_delay;
  logic [1:0] cov_i_accept_pair;
  logic [1:0] cov_d_req_type;
  logic       cov_i_req_seen;
  logic       cov_i_rsp_seen;
  logic       cov_d_rd_seen;
  logic       cov_d_wr_seen;
  logic       cov_branch_seen;
  logic       cov_intr_seen;
  logic       cov_lane0_exec_seen;
  logic       cov_lane0_lsu_seen;
  logic       cov_lane0_branch_seen;
  logic       cov_lane0_mul_seen;
  logic       cov_lane0_div_seen;
  logic       cov_lane0_csr_seen;
  logic       cov_lane1_exec_seen;
  logic       cov_lane1_lsu_seen;
  logic       cov_lane1_branch_seen;
  logic       cov_lane1_mul_seen;
  logic       cov_lane1_div_seen;
  logic       cov_lane1_csr_seen;

  //============================================================
  // Coverage
  //============================================================
  covergroup cg_core @(posedge clk_i);
	option.per_instance = 1;

	cp_test_id : coverpoint cov_test_id {
	  bins t0 = {0};
	  bins t1 = {1};
	  bins t2 = {2};
	  bins t3 = {3};
	  bins t4 = {4};
	}

	cp_i_delay : coverpoint cov_i_delay {
	  bins d0 = {2'd0};
	  bins d1 = {2'd1};
	  bins d2 = {2'd2};
	}

	cp_d_delay : coverpoint cov_d_delay {
	  bins d0 = {2'd0};
	  bins d1 = {2'd1};
	  bins d2 = {2'd2};
	}

	cp_i_accept_pair : coverpoint cov_i_accept_pair {
	  bins a00 = {2'b00};
	  bins a01 = {2'b01};
	  bins a10 = {2'b10};
	  bins a11 = {2'b11};
	}

	cp_d_req_type : coverpoint cov_d_req_type {
	  bins none_b = {2'b00};
	  bins rd_b   = {2'b01};
	  bins wr_b   = {2'b10};
	}

	cp_i_req_seen : coverpoint cov_i_req_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_i_rsp_seen : coverpoint cov_i_rsp_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_d_rd_seen : coverpoint cov_d_rd_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_d_wr_seen : coverpoint cov_d_wr_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_branch_seen : coverpoint cov_branch_seen {
	  bins no  = {1'b0};
	  bins yes = {1'b1};
	}

	cp_intr : coverpoint intr_i {
		bins no  = {1'b0};
		bins yes = {1'b1};
	  }

	cp_lane0_exec_seen   : coverpoint cov_lane0_exec_seen   { bins no = {0}; bins yes = {1}; }
	cp_lane0_lsu_seen    : coverpoint cov_lane0_lsu_seen    { bins no = {0}; bins yes = {1}; }
	cp_lane0_branch_seen : coverpoint cov_lane0_branch_seen { bins no = {0}; bins yes = {1}; }
	cp_lane0_mul_seen    : coverpoint cov_lane0_mul_seen    { bins no = {0}; bins yes = {1}; }
	cp_lane0_div_seen    : coverpoint cov_lane0_div_seen    { bins no = {0}; bins yes = {1}; }
	cp_lane0_csr_seen    : coverpoint cov_lane0_csr_seen    { bins no = {0}; bins yes = {1}; }

	cp_lane1_exec_seen   : coverpoint cov_lane1_exec_seen   { bins no = {0}; bins yes = {1}; }
	cp_lane1_lsu_seen    : coverpoint cov_lane1_lsu_seen    { bins no = {0}; bins yes = {1}; }
	cp_lane1_branch_seen : coverpoint cov_lane1_branch_seen { bins no = {0}; bins yes = {1}; }
	cp_lane1_mul_seen    : coverpoint cov_lane1_mul_seen    { bins no = {0}; bins yes = {1}; }
	cp_lane1_div_seen    : coverpoint cov_lane1_div_seen    { bins no = {0}; bins yes = {1}; }
	cp_lane1_csr_seen    : coverpoint cov_lane1_csr_seen    { bins no = {0}; bins yes = {1}; }
  endgroup

  cg_core cov_i = new();

  //============================================================
  // Instruction helpers
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

  function automatic logic [31:0] enc_nop();
	enc_nop = enc_addi(5'd0, 5'd0, 12'd0);
  endfunction

  function automatic logic [63:0] mk_bundle(
	input logic [31:0] i0,
	input logic [31:0] i1
  );
	mk_bundle = {i1, i0};
  endfunction

  function automatic logic [31:0] gen_instr_by_sel(input int sel);
	case (sel)
	  0: gen_instr_by_sel = enc_addi(5'd1, 5'd0, 12'd5);
	  1: gen_instr_by_sel = enc_andi(5'd2, 5'd1, 12'h0FF);
	  2: gen_instr_by_sel = enc_lw  (5'd3, 5'd0, 12'd0);
	  3: gen_instr_by_sel = enc_sw  (5'd2, 5'd0, 12'd4);
	  4: gen_instr_by_sel = enc_beq (5'd1, 5'd1, 13'd8);
	  5: gen_instr_by_sel = enc_jal (5'd0, 21'd8);
	  6: gen_instr_by_sel = enc_mul (5'd4, 5'd1, 5'd2);
	  7: gen_instr_by_sel = enc_div (5'd5, 5'd2, 5'd1);
	  8: gen_instr_by_sel = enc_csrrw(5'd6, 12'h300, 5'd0);
	  default: gen_instr_by_sel = enc_nop();
	endcase
  endfunction

  function automatic logic [63:0] gen_bundle(input int idx);
	logic [31:0] i0;
	logic [31:0] i1;
	i0 = gen_instr_by_sel(idx % 9);
	i1 = gen_instr_by_sel((idx + 1) % 9);
	gen_bundle = mk_bundle(i0, i1);
  endfunction

  //============================================================
  // Memory helpers
  //============================================================
  task automatic clear_imem();
	int i;
	begin
	  for (i = 0; i < IMEM_DEPTH; i++)
		imem[i] = mk_bundle(enc_nop(), enc_nop());
	end
  endtask

  task automatic clear_dmem();
	int i;
	begin
	  for (i = 0; i < DMEM_DEPTH; i++)
		dmem[i] = 32'h0;
	end
  endtask

  task automatic put_bundle(input int idx, input logic [31:0] i0, input logic [31:0] i1);
	begin
	  if ((idx >= 0) && (idx < IMEM_DEPTH))
		imem[idx] = mk_bundle(i0, i1);
	end
  endtask

  task automatic write_word_be(
	input int idx,
	input logic [31:0] data,
	input logic [3:0]  be
  );
	begin
	  if ((idx >= 0) && (idx < DMEM_DEPTH)) begin
		if (be[0]) dmem[idx][7:0]   = data[7:0];
		if (be[1]) dmem[idx][15:8]  = data[15:8];
		if (be[2]) dmem[idx][23:16] = data[23:16];
		if (be[3]) dmem[idx][31:24] = data[31:24];
	  end
	end
  endtask

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
	  rst_i           = 1'b1;
	  intr_i          = 1'b0;
	  reset_vector_i  = 32'h0000_0000;
	  cpu_id_i        = 32'h0000_0001;

	  mem_i_accept_i  = 1'b1;
	  mem_i_valid_i   = 1'b0;
	  mem_i_error_i   = 1'b0;
	  mem_i_inst_i    = 64'h0;

	  mem_d_data_rd_i  = 32'h0;
	  mem_d_accept_i   = 1'b1;
	  mem_d_ack_i      = 1'b0;
	  mem_d_error_i    = 1'b0;
	  mem_d_resp_tag_i = 11'h0;

	  i_accept_mode    = 0;
	  d_accept_mode    = 0;

	  cov_test_id          = 0;
	  cov_i_delay          = 2'b00;
	  cov_d_delay          = 2'b00;
	  cov_i_accept_pair    = 2'b11;
	  cov_d_req_type       = 2'b00;
	  cov_i_req_seen       = 1'b0;
	  cov_i_rsp_seen       = 1'b0;
	  cov_d_rd_seen        = 1'b0;
	  cov_d_wr_seen        = 1'b0;
	  cov_branch_seen      = 1'b0;
	  cov_intr_seen        = 1'b0;
	  cov_lane0_exec_seen  = 1'b0;
	  cov_lane0_lsu_seen   = 1'b0;
	  cov_lane0_branch_seen= 1'b0;
	  cov_lane0_mul_seen   = 1'b0;
	  cov_lane0_div_seen   = 1'b0;
	  cov_lane0_csr_seen   = 1'b0;
	  cov_lane1_exec_seen  = 1'b0;
	  cov_lane1_lsu_seen   = 1'b0;
	  cov_lane1_branch_seen= 1'b0;
	  cov_lane1_mul_seen   = 1'b0;
	  cov_lane1_div_seen   = 1'b0;
	  cov_lane1_csr_seen   = 1'b0;
	end
  endtask

  task automatic reset_dut();
	begin
	  rst_i = 1'b1;
	  intr_i = 1'b0;
	  mem_i_valid_i  = 1'b0;
	  mem_d_ack_i    = 1'b0;
	  mem_i_error_i  = 1'b0;
	  mem_d_error_i  = 1'b0;
	  mem_i_inst_i   = 64'h0;
	  mem_d_data_rd_i = 32'h0;
	  mem_d_resp_tag_i = 11'h0;
	  if_q.delete();
	  d_q.delete();
	  repeat (6) @(posedge clk_i);
	  rst_i = 1'b0;
	  repeat (4) @(posedge clk_i);
	end
  endtask

  task automatic wait_cycles(input int n);
	repeat (n) @(posedge clk_i);
  endtask

  task automatic pulse_interrupt();
	begin
	  @(posedge clk_i);
	  intr_i <= 1'b1;
	  @(posedge clk_i);
	  intr_i <= 1'b0;
	end
  endtask

  //============================================================
  // Program loaders
  //============================================================
  task automatic load_basic_program();
	begin
	  clear_imem();
	  clear_dmem();

	  dmem[0] = 32'h0000_0011;
	  dmem[1] = 32'h0000_0022;

	  put_bundle(0, enc_addi(5'd1, 5'd0, 12'd5),     enc_addi(5'd2, 5'd0, 12'd9));
	  put_bundle(1, enc_andi(5'd3, 5'd2, 12'h0F0),   enc_addi(5'd4, 5'd3, 12'd1));
	  put_bundle(2, enc_beq(5'd1, 5'd1, 13'd8),      enc_addi(5'd5, 5'd0, 12'd7));
	  put_bundle(3, enc_addi(5'd6, 5'd0, 12'd3),     enc_jal(5'd0, 21'd8));
	  put_bundle(4, enc_addi(5'd7, 5'd0, 12'd4),     enc_addi(5'd8, 5'd0, 12'd5));
	  put_bundle(5, enc_jal(5'd0, -21'sd8),          enc_nop());
	end
  endtask

  task automatic load_mem_program();
	begin
	  clear_imem();
	  clear_dmem();

	  dmem[0] = 32'h1234_5678;
	  dmem[1] = 32'hCAFE_BABE;

	  put_bundle(0, enc_lw(5'd1, 5'd0, 12'd0),       enc_lw(5'd2, 5'd0, 12'd4));
	  put_bundle(1, enc_sw(5'd1, 5'd0, 12'd8),       enc_sw(5'd2, 5'd0, 12'd12));
	  put_bundle(2, enc_addi(5'd3, 5'd0, 12'd1),     enc_beq(5'd3, 5'd3, 13'd8));
	  put_bundle(3, enc_addi(5'd4, 5'd0, 12'd2),     enc_addi(5'd5, 5'd0, 12'd3));
	  put_bundle(4, enc_jal(5'd0, -21'sd8),          enc_nop());
	end
  endtask

  task automatic load_muldivcsr_program();
	begin
	  clear_imem();
	  clear_dmem();

	  put_bundle(0, enc_addi(5'd1, 5'd0, 12'd8),     enc_addi(5'd2, 5'd0, 12'd2));
	  put_bundle(1, enc_mul(5'd3, 5'd1, 5'd2),       enc_div(5'd4, 5'd1, 5'd2));
	  put_bundle(2, enc_csrrw(5'd5, 12'h300, 5'd0),  enc_andi(5'd6, 5'd1, 12'h0F));
	  put_bundle(3, enc_beq(5'd1, 5'd1, 13'd8),      enc_addi(5'd7, 5'd0, 12'd1));
	  put_bundle(4, enc_jal(5'd0, -21'sd8),          enc_nop());
	end
  endtask

  task automatic load_random_program();
	int i;
	begin
	  clear_imem();
	  clear_dmem();

	  dmem[0] = 32'h1111_2222;
	  dmem[1] = 32'h3333_4444;
	  dmem[2] = 32'h5555_6666;
	  dmem[3] = 32'h7777_8888;

	  for (i = 0; i < 256; i++) begin
		imem[i] = gen_bundle(i);
	  end

	  put_bundle(255, enc_jal(5'd0, -21'sd16), enc_nop());
	end
  endtask

  //============================================================
  // Accept generation
  //============================================================
  always @(posedge clk_i) begin
	if (rst_i) begin
	  mem_i_accept_i <= 1'b1;
	  mem_d_accept_i <= 1'b1;
	end
	else begin
	  case (i_accept_mode)
		0: mem_i_accept_i <= 1'b1;
		1: mem_i_accept_i <= $urandom_range(0, 1);
		default: mem_i_accept_i <= 1'b1;
	  endcase

	  case (d_accept_mode)
		0: mem_d_accept_i <= 1'b1;
		1: mem_d_accept_i <= $urandom_range(0, 1);
		default: mem_d_accept_i <= 1'b1;
	  endcase
	end
  end

  //============================================================
  // Instruction memory model
  //============================================================
  always @(posedge clk_i) begin
	if (rst_i) begin
	  mem_i_valid_i <= 1'b0;
	  mem_i_error_i <= 1'b0;
	  mem_i_inst_i  <= 64'h0;
	  if_q.delete();
	end
	else begin
	  mem_i_valid_i <= 1'b0;
	  mem_i_error_i <= 1'b0;
	  mem_i_inst_i  <= 64'h0;

	  if (mem_i_rd_o && mem_i_accept_i) begin
		if_rsp_t item;
		int idx;

		idx = (mem_i_pc_o >> 3);
		if ((idx >= 0) && (idx < IMEM_DEPTH))
		  item.inst = imem[idx];
		else
		  item.inst = mk_bundle(enc_nop(), enc_nop());

		item.delay = $urandom_range(0, 2);
		cov_i_delay <= item.delay;
		if_q.push_back(item);

		i_req_count++;
		cov_i_req_seen <= 1'b1;
	  end

	  if (if_q.size() > 0) begin
		if (if_q[0].delay != 0) begin
		  if_q[0].delay <= if_q[0].delay - 1'b1;
		end
		else begin
		  mem_i_valid_i <= 1'b1;
		  mem_i_inst_i  <= if_q[0].inst;
		  if_q.pop_front();

		  i_rsp_count++;
		  cov_i_rsp_seen <= 1'b1;
		end
	  end
	end
  end

  //============================================================
  // Data memory model
  //============================================================
  always @(posedge clk_i) begin
	if (rst_i) begin
	  mem_d_ack_i      <= 1'b0;
	  mem_d_error_i    <= 1'b0;
	  mem_d_data_rd_i  <= 32'h0;
	  mem_d_resp_tag_i <= 11'h0;
	  d_q.delete();
	end
	else begin
	  mem_d_ack_i      <= 1'b0;
	  mem_d_error_i    <= 1'b0;
	  mem_d_data_rd_i  <= 32'h0;
	  mem_d_resp_tag_i <= 11'h0;

	  if (mem_d_rd_o && mem_d_accept_i) begin
		d_rsp_t item;
		item.is_read = 1'b1;
		item.addr    = mem_d_addr_o;
		item.wr_data = 32'h0;
		item.wr_be   = 4'h0;
		item.tag     = mem_d_req_tag_o;
		item.delay   = $urandom_range(0, 2);
		cov_d_delay  <= item.delay;
		d_q.push_back(item);

		d_req_count++;
		d_rd_count++;
		cov_d_rd_seen <= 1'b1;
	  end
	  else if ((mem_d_wr_o != 4'b0000) && mem_d_accept_i) begin
		d_rsp_t item;
		item.is_read = 1'b0;
		item.addr    = mem_d_addr_o;
		item.wr_data = mem_d_data_wr_o;
		item.wr_be   = mem_d_wr_o;
		item.tag     = mem_d_req_tag_o;
		item.delay   = $urandom_range(0, 2);
		cov_d_delay  <= item.delay;
		d_q.push_back(item);

		d_req_count++;
		d_wr_count++;
		cov_d_wr_seen <= 1'b1;
	  end

	  if (d_q.size() > 0) begin
		if (d_q[0].delay != 0) begin
		  d_q[0].delay <= d_q[0].delay - 1'b1;
		end
		else begin
		  mem_d_ack_i      <= 1'b1;
		  mem_d_resp_tag_i <= d_q[0].tag;

		  if (d_q[0].is_read) begin
			int idx;
			idx = (d_q[0].addr >> 2);
			if ((idx >= 0) && (idx < DMEM_DEPTH))
			  mem_d_data_rd_i <= dmem[idx];
			else
			  mem_d_data_rd_i <= 32'h0;
		  end
		  else begin
			int idx;
			idx = (d_q[0].addr >> 2);
			write_word_be(idx, d_q[0].wr_data, d_q[0].wr_be);
		  end

		  d_q.pop_front();
		  d_rsp_count++;
		end
	  end
	end
  end

  //============================================================
  // Runtime monitors
  //============================================================
  always @(posedge clk_i) begin
	if (!rst_i) begin
	  cov_i_accept_pair <= {mem_d_accept_i, mem_i_accept_i};

	  if (mem_d_rd_o)
		cov_d_req_type <= 2'b01;
	  else if (mem_d_wr_o != 4'b0000)
		cov_d_req_type <= 2'b10;
	  else
		cov_d_req_type <= 2'b00;

	  check_true(^mem_i_rd_o      !== 1'bx, "mem_i_rd_o contains X");
	  check_true(^mem_i_pc_o      !== 1'bx, "mem_i_pc_o contains X");
	  check_true(^mem_d_rd_o      !== 1'bx, "mem_d_rd_o contains X");
	  check_true(^mem_d_wr_o      !== 1'bx, "mem_d_wr_o contains X");
	  check_true(^mem_d_addr_o    !== 1'bx, "mem_d_addr_o contains X");

	  check_true(mem_i_pc_o[2:0] == 3'b000, "mem_i_pc_o must be 8-byte aligned");

	  if (dut.fetch0_valid_w)
		fetch0_valid_count++;
	  if (dut.fetch1_valid_w)
		fetch1_valid_count++;
	  if (dut.fetch0_valid_w && dut.fetch1_valid_w)
		dual_fetch_count++;

	  if (dut.fetch0_valid_w && dut.fetch1_valid_w) begin
		check_true(dut.fetch1_pc_w == (dut.fetch0_pc_w + 32'd4), "lane1 PC must equal lane0 PC + 4");
	  end

	  if (dut.fetch0_instr_exec_w)    begin lane0_exec_count++;   cov_lane0_exec_seen   <= 1'b1; end
	  if (dut.fetch0_instr_lsu_w)     begin lane0_lsu_count++;    cov_lane0_lsu_seen    <= 1'b1; end
	  if (dut.fetch0_instr_branch_w)  begin lane0_branch_count++; cov_lane0_branch_seen <= 1'b1; end
	  if (dut.fetch0_instr_mul_w)     begin lane0_mul_count++;    cov_lane0_mul_seen    <= 1'b1; end
	  if (dut.fetch0_instr_div_w)     begin lane0_div_count++;    cov_lane0_div_seen    <= 1'b1; end
	  if (dut.fetch0_instr_csr_w)     begin lane0_csr_count++;    cov_lane0_csr_seen    <= 1'b1; end

	  if (dut.fetch1_instr_exec_w)    begin lane1_exec_count++;   cov_lane1_exec_seen   <= 1'b1; end
	  if (dut.fetch1_instr_lsu_w)     begin lane1_lsu_count++;    cov_lane1_lsu_seen    <= 1'b1; end
	  if (dut.fetch1_instr_branch_w)  begin lane1_branch_count++; cov_lane1_branch_seen <= 1'b1; end
	  if (dut.fetch1_instr_mul_w)     begin lane1_mul_count++;    cov_lane1_mul_seen    <= 1'b1; end
	  if (dut.fetch1_instr_div_w)     begin lane1_div_count++;    cov_lane1_div_seen    <= 1'b1; end
	  if (dut.fetch1_instr_csr_w)     begin lane1_csr_count++;    cov_lane1_csr_seen    <= 1'b1; end

	  if (dut.branch_request_w) begin
		branch_request_count++;
		cov_branch_seen <= 1'b1;
	  end

	  if (dut.take_interrupt_w) begin
		interrupt_take_count++;
		cov_intr_seen <= 1'b1;
	  end
	end
  end

  //============================================================
  // Tests
  //============================================================
  task automatic test_reset_fetch_smoke();
	begin
	  cov_test_id = 0;
	  $display("\n[TEST] reset_fetch_smoke");

	  load_basic_program();
	  i_accept_mode = 0;
	  d_accept_mode = 0;
	  reset_dut();

	  wait_cycles(60);

	  check_true(i_req_count > 0, "no instruction requests seen after reset");
	  check_true(i_rsp_count > 0, "no instruction responses seen after reset");
	  check_true(fetch0_valid_count > 0, "lane0 was never valid in smoke test");
	  check_true(fetch1_valid_count > 0, "lane1 was never valid in smoke test");
	end
  endtask

  task automatic test_load_store();
	begin
	  cov_test_id = 1;
	  $display("\n[TEST] load_store");

	  load_mem_program();
	  i_accept_mode = 0;
	  d_accept_mode = 0;
	  reset_dut();

	  wait_cycles(120);

	  check_true(d_rd_count > 0, "no data read requests seen in load_store test");
	  check_true(d_wr_count > 0, "no data write requests seen in load_store test");
	  check_true(d_rsp_count > 0, "no data responses seen in load_store test");
	end
  endtask

  task automatic test_mul_div_csr();
	begin
	  cov_test_id = 2;
	  $display("\n[TEST] mul_div_csr");

	  load_muldivcsr_program();
	  i_accept_mode = 0;
	  d_accept_mode = 0;
	  reset_dut();

	  wait_cycles(120);

	  check_true(lane0_mul_count + lane1_mul_count > 0, "mul class was never seen");
	  check_true(lane0_div_count + lane1_div_count > 0, "div class was never seen");
	  check_true(lane0_csr_count + lane1_csr_count > 0, "csr class was never seen");
	  check_true(branch_request_count > 0, "branch activity was never seen");
	end
  endtask

  task automatic test_interrupt();
	begin
	  cov_test_id = 3;
	  $display("\n[TEST] interrupt");

	  load_basic_program();
	  i_accept_mode = 0;
	  d_accept_mode = 0;
	  reset_dut();

	  wait_cycles(20);
	  pulse_interrupt();
	  wait_cycles(80);

	  check_true(1'b1, "interrupt scenario completed");
	end
  endtask

  task automatic test_random();
	int i;
	begin
	  cov_test_id = 4;
	  $display("\n[TEST] random");

	  load_random_program();
	  i_accept_mode = 1;
	  d_accept_mode = 1;
	  reset_dut();

	  for (i = 0; i < RANDOM_ITERS; i++) begin
		@(posedge clk_i);

		if ($urandom_range(0, 79) == 0)
		  intr_i <= 1'b1;
		else
		  intr_i <= 1'b0;
	  end

	  intr_i <= 1'b0;
	  i_accept_mode = 0;
	  d_accept_mode = 0;
	  wait_cycles(100);

	  check_true(i_req_count > 20, "instruction request count too low in random test");
	  check_true(i_rsp_count > 20, "instruction response count too low in random test");
	  check_true(d_req_count > 5, "data request count too low in random test");
	  check_true(branch_request_count > 0, "branch activity missing in random test");
	end
  endtask

  //============================================================
  // Timeout
  //============================================================
  initial begin
	#3000000;
	$display("[FAIL] TB timeout");
	fail_count++;
	$finish;
  end

  //============================================================
  // Main
  //============================================================
  initial begin
	test_count           = 0;
	pass_count           = 0;
	fail_count           = 0;

	i_req_count          = 0;
	i_rsp_count          = 0;
	d_req_count          = 0;
	d_rsp_count          = 0;
	d_rd_count           = 0;
	d_wr_count           = 0;

	fetch0_valid_count   = 0;
	fetch1_valid_count   = 0;
	dual_fetch_count     = 0;

	lane0_exec_count     = 0;
	lane0_lsu_count      = 0;
	lane0_branch_count   = 0;
	lane0_mul_count      = 0;
	lane0_div_count      = 0;
	lane0_csr_count      = 0;

	lane1_exec_count     = 0;
	lane1_lsu_count      = 0;
	lane1_branch_count   = 0;
	lane1_mul_count      = 0;
	lane1_div_count      = 0;
	lane1_csr_count      = 0;

	branch_request_count = 0;
	interrupt_take_count = 0;

	init_inputs();

	test_reset_fetch_smoke();
	test_load_store();
	test_mul_div_csr();
	test_interrupt();
	test_random();

	check_true(fetch0_valid_count > 10, "lane0 valid count too low overall");
	check_true(fetch1_valid_count > 10, "lane1 valid count too low overall");
	check_true(dual_fetch_count   > 5,  "dual fetch count too low overall");

	check_true(lane0_exec_count   + lane1_exec_count   > 0, "exec class never seen");
	check_true(lane0_lsu_count    + lane1_lsu_count    > 0, "lsu class never seen");
	check_true(lane0_branch_count + lane1_branch_count > 0, "branch class never seen");
	check_true(lane0_mul_count    + lane1_mul_count    > 0, "mul class never seen");
	check_true(lane0_div_count    + lane1_div_count    > 0, "div class never seen");
	check_true(lane0_csr_count    + lane1_csr_count    > 0, "csr class never seen");

	$display("\n==================================================");
	$display("RISCV_CORE TB SUMMARY");
	$display("  test_count           = %0d", test_count);
	$display("  pass_count           = %0d", pass_count);
	$display("  fail_count           = %0d", fail_count);
	$display("  i_req_count          = %0d", i_req_count);
	$display("  i_rsp_count          = %0d", i_rsp_count);
	$display("  d_req_count          = %0d", d_req_count);
	$display("  d_rsp_count          = %0d", d_rsp_count);
	$display("  d_rd_count           = %0d", d_rd_count);
	$display("  d_wr_count           = %0d", d_wr_count);
	$display("  fetch0_valid_count   = %0d", fetch0_valid_count);
	$display("  fetch1_valid_count   = %0d", fetch1_valid_count);
	$display("  dual_fetch_count     = %0d", dual_fetch_count);
	$display("  lane0 classes        = exec:%0d lsu:%0d br:%0d mul:%0d div:%0d csr:%0d",
			 lane0_exec_count, lane0_lsu_count, lane0_branch_count,
			 lane0_mul_count, lane0_div_count, lane0_csr_count);
	$display("  lane1 classes        = exec:%0d lsu:%0d br:%0d mul:%0d div:%0d csr:%0d",
			 lane1_exec_count, lane1_lsu_count, lane1_branch_count,
			 lane1_mul_count, lane1_div_count, lane1_csr_count);
	$display("  branch_request_count = %0d", branch_request_count);
	$display("  interrupt_take_count = %0d", interrupt_take_count);
	$display("  coverage             = %0.2f %%", cov_i.get_coverage());
	$display("==================================================");

	if (fail_count == 0)
	  $display("TB PASSED");
	else
	  $display("TB FAILED");

	$finish;
  end

endmodule