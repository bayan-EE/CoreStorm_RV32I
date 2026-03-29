`timescale 1ns/1ps

module tb_dcache_core_l2;

  // ------------------------------------------------------------
  // DUT inputs
  // ------------------------------------------------------------
  logic         clk_i;
  logic         rst_i;
  logic [31:0]  mem_addr_i;
  logic [31:0]  mem_data_wr_i;
  logic         mem_rd_i;
  logic [3:0]   mem_wr_i;
  logic         mem_cacheable_i;
  logic [10:0]  mem_req_tag_i;
  logic         mem_invalidate_i;
  logic         mem_writeback_i;
  logic         mem_flush_i;

  logic         l2_req_ready_i;
  logic         l2_resp_valid_i;
  logic         l2_resp_hit_i;
  logic         l2_resp_error_i;
  logic [255:0] l2_resp_rdata_i;

  logic         snoop_valid_i;
  logic [1:0]   snoop_cmd_i;
  logic [31:0]  snoop_addr_i;

  logic         coh_req_ready_i;
  logic         coh_trans_done_i;
  logic         coh_trans_shared_i;
  logic         coh_trans_dirty_i;

  // ------------------------------------------------------------
  // DUT outputs
  // ------------------------------------------------------------
  wire [31:0]   mem_data_rd_o;
  wire          mem_accept_o;
  wire          mem_ack_o;
  wire          mem_error_o;
  wire [10:0]   mem_resp_tag_o;

  wire          l2_req_valid_o;
  wire          l2_req_we_o;
  wire [31:0]   l2_req_addr_o;
  wire [255:0]  l2_req_wdata_o;
  wire [31:0]   l2_req_wmask_o;

  wire          coh_req_valid_o;
  wire [1:0]    coh_req_cmd_o;
  wire [31:0]   coh_req_addr_o;

  wire          snoop_hit_o;
  wire          snoop_dirty_o;
  wire          snoop_ack_o;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  dcache_core dut
  (
	 .clk_i(clk_i)
	,.rst_i(rst_i)
	,.mem_addr_i(mem_addr_i)
	,.mem_data_wr_i(mem_data_wr_i)
	,.mem_rd_i(mem_rd_i)
	,.mem_wr_i(mem_wr_i)
	,.mem_cacheable_i(mem_cacheable_i)
	,.mem_req_tag_i(mem_req_tag_i)
	,.mem_invalidate_i(mem_invalidate_i)
	,.mem_writeback_i(mem_writeback_i)
	,.mem_flush_i(mem_flush_i)

	,.l2_req_ready_i(l2_req_ready_i)
	,.l2_resp_valid_i(l2_resp_valid_i)
	,.l2_resp_hit_i(l2_resp_hit_i)
	,.l2_resp_error_i(l2_resp_error_i)
	,.l2_resp_rdata_i(l2_resp_rdata_i)

	,.snoop_valid_i(snoop_valid_i)
	,.snoop_cmd_i(snoop_cmd_i)
	,.snoop_addr_i(snoop_addr_i)

	,.coh_req_ready_i(coh_req_ready_i)
	,.coh_trans_done_i(coh_trans_done_i)
	,.coh_trans_shared_i(coh_trans_shared_i)
	,.coh_trans_dirty_i(coh_trans_dirty_i)
	,.coh_req_valid_o(coh_req_valid_o)
	,.coh_req_cmd_o(coh_req_cmd_o)
	,.coh_req_addr_o(coh_req_addr_o)

	,.mem_data_rd_o(mem_data_rd_o)
	,.mem_accept_o(mem_accept_o)
	,.mem_ack_o(mem_ack_o)
	,.mem_error_o(mem_error_o)
	,.mem_resp_tag_o(mem_resp_tag_o)

	,.l2_req_valid_o(l2_req_valid_o)
	,.l2_req_we_o(l2_req_we_o)
	,.l2_req_addr_o(l2_req_addr_o)
	,.l2_req_wdata_o(l2_req_wdata_o)
	,.l2_req_wmask_o(l2_req_wmask_o)

	,.snoop_hit_o(snoop_hit_o)
	,.snoop_dirty_o(snoop_dirty_o)
	,.snoop_ack_o(snoop_ack_o)
  );

  // ------------------------------------------------------------
  // Local params
  // ------------------------------------------------------------
  localparam [1:0] MSI_I = 2'b00;
  localparam [1:0] MSI_S = 2'b01;
  localparam [1:0] MSI_M = 2'b10;

  localparam [1:0] SNOOP_BUSRD   = 2'd0;
  localparam [1:0] SNOOP_BUSRDX  = 2'd1;
  localparam [1:0] SNOOP_BUSUPGR = 2'd2;

  localparam int STATE_RESET       = 4'd0;
  localparam int STATE_FLUSH_ADDR  = 4'd1;
  localparam int STATE_FLUSH       = 4'd2;
  localparam int STATE_LOOKUP      = 4'd3;
  localparam int STATE_READ        = 4'd4;
  localparam int STATE_WRITE       = 4'd5;
  localparam int STATE_REFILL      = 4'd6;
  localparam int STATE_EVICT       = 4'd7;
  localparam int STATE_EVICT_WAIT  = 4'd8;
  localparam int STATE_INVALIDATE  = 4'd9;
  localparam int STATE_WRITEBACK   = 4'd10;
  localparam int STATE_SNOOP_REQ   = 4'd11;
  localparam int STATE_SNOOP_CHECK = 4'd12;
  localparam int STATE_REFILL_WAIT = 4'd13;
  localparam int STATE_READ_WAIT   = 4'd14;
  localparam int STATE_READ_RESP   = 4'd15;

  // ------------------------------------------------------------
  // Score / counters
  // ------------------------------------------------------------
  integer pass_count;
  integer fail_count;
  integer test_count;

  task automatic pass(input string msg);
	begin
	  pass_count = pass_count + 1;
	  $display("[PASS] %s t=%0t", msg, $time);
	end
  endtask

  task automatic fail(input string msg);
	begin
	  fail_count = fail_count + 1;
	  $display("[FAIL] %s t=%0t", msg, $time);
	end
  endtask

  task automatic check_eq32(input string name, input [31:0] got, input [31:0] exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%08x exp=%08x", name, got, exp));
	  else
		pass($sformatf("%s = %08x", name, got));
	end
  endtask

  task automatic check_eq1(input string name, input logic got, input logic exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%0b exp=%0b", name, got, exp));
	  else
		pass($sformatf("%s = %0b", name, got));
	end
  endtask

  task automatic check_true(input string name, input logic cond);
	begin
	  if (!cond)
		fail(name);
	  else
		pass(name);
	end
  endtask

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  initial begin
	clk_i = 1'b0;
	forever #5 clk_i = ~clk_i;
  end

  // ------------------------------------------------------------
  // Simple backing memory model (word-addressable)
  // ------------------------------------------------------------
  logic [31:0] model_mem [0:65535];

  function automatic [255:0] make_line(input [31:0] line_addr);
	integer i;
	reg [255:0] tmp;
	reg [31:0] base_word;
	begin
	  tmp = '0;
	  base_word = {line_addr[31:5], 5'b0} >> 2;
	  for (i = 0; i < 8; i = i + 1)
		tmp[(i*32) +: 32] = model_mem[base_word + i];
	  make_line = tmp;
	end
  endfunction

  task automatic apply_line_write(
	input [31:0]  line_addr,
	input [255:0] line_data,
	input [31:0]  line_mask
  );
	integer i, b;
	reg [31:0] base_word;
	reg [31:0] w;
	begin
	  base_word = {line_addr[31:5], 5'b0} >> 2;
	  for (i = 0; i < 8; i = i + 1) begin
		w = model_mem[base_word + i];
		for (b = 0; b < 4; b = b + 1) begin
		  if (line_mask[(i*4)+b])
			w[(b*8) +: 8] = line_data[(i*32)+(b*8) +: 8];
		end
		model_mem[base_word + i] = w;
	  end
	end
  endtask

  // ------------------------------------------------------------
  // L2 response model
  // ------------------------------------------------------------
  typedef struct packed {
	logic        pending;
	logic        we;
	logic [31:0] addr;
	logic [255:0] wdata;
	logic [31:0] wmask;
	integer      delay;
  } l2_rsp_t;

  l2_rsp_t l2_rsp_q;

  always_comb begin
	l2_req_ready_i = 1'b1;
	l2_resp_hit_i  = 1'b1;
	l2_resp_error_i = 1'b0;
  end

  always @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
	  l2_resp_valid_i <= 1'b0;
	  l2_resp_rdata_i <= '0;
	  l2_rsp_q.pending <= 1'b0;
	  l2_rsp_q.we      <= 1'b0;
	  l2_rsp_q.addr    <= '0;
	  l2_rsp_q.wdata   <= '0;
	  l2_rsp_q.wmask   <= '0;
	  l2_rsp_q.delay   <= 0;
	end
	else begin
	  l2_resp_valid_i <= 1'b0;
	  l2_resp_rdata_i <= '0;

	  if (l2_req_valid_o && l2_req_ready_i && !l2_rsp_q.pending) begin
		l2_rsp_q.pending <= 1'b1;
		l2_rsp_q.we      <= l2_req_we_o;
		l2_rsp_q.addr    <= l2_req_addr_o;
		l2_rsp_q.wdata   <= l2_req_wdata_o;
		l2_rsp_q.wmask   <= l2_req_wmask_o;
		l2_rsp_q.delay   <= 1 + $urandom_range(0,1);
	  end

	  if (l2_rsp_q.pending) begin
		if (l2_rsp_q.delay > 0) begin
		  l2_rsp_q.delay <= l2_rsp_q.delay - 1;
		end
		else begin
		  if (l2_rsp_q.we)
			apply_line_write(l2_rsp_q.addr, l2_rsp_q.wdata, l2_rsp_q.wmask);

		  l2_resp_valid_i <= 1'b1;
		  l2_resp_rdata_i <= make_line(l2_rsp_q.addr);
		  l2_rsp_q.pending <= 1'b0;
		end
	  end
	end
  end

  // ------------------------------------------------------------
  // Simple coherence response model
  // ------------------------------------------------------------
  typedef struct packed {
	logic        pending;
	logic [1:0]  cmd;
	integer      delay;
  } coh_rsp_t;

  coh_rsp_t coh_rsp_q;

  always_comb begin
	coh_req_ready_i = 1'b1;
  end

  always @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
	  coh_trans_done_i   <= 1'b0;
	  coh_trans_shared_i <= 1'b0;
	  coh_trans_dirty_i  <= 1'b0;
	  coh_rsp_q.pending  <= 1'b0;
	  coh_rsp_q.cmd      <= 2'b0;
	  coh_rsp_q.delay    <= 0;
	end
	else begin
	  coh_trans_done_i   <= 1'b0;
	  coh_trans_shared_i <= 1'b0;
	  coh_trans_dirty_i  <= 1'b0;

	  if (coh_req_valid_o && coh_req_ready_i && !coh_rsp_q.pending) begin
		coh_rsp_q.pending <= 1'b1;
		coh_rsp_q.cmd     <= coh_req_cmd_o;
		coh_rsp_q.delay   <= 1;
	  end

	  if (coh_rsp_q.pending) begin
		if (coh_rsp_q.delay > 0)
		  coh_rsp_q.delay <= coh_rsp_q.delay - 1;
		else begin
		  coh_trans_done_i <= 1'b1;

		  case (coh_rsp_q.cmd)
			SNOOP_BUSRD: begin
			  coh_trans_shared_i <= 1'b1;
			  coh_trans_dirty_i  <= 1'b0;
			end
			SNOOP_BUSRDX: begin
			  coh_trans_shared_i <= 1'b0;
			  coh_trans_dirty_i  <= 1'b0;
			end
			SNOOP_BUSUPGR: begin
			  coh_trans_shared_i <= 1'b0;
			  coh_trans_dirty_i  <= 1'b0;
			end
			default: begin
			  coh_trans_shared_i <= 1'b0;
			  coh_trans_dirty_i  <= 1'b0;
			end
		  endcase

		  coh_rsp_q.pending <= 1'b0;
		end
	  end
	end
  end

  // ------------------------------------------------------------
  // Coverage helpers
  // ------------------------------------------------------------
  logic [2:0] op_kind_cov;
  logic [1:0] snoop_cmd_cov;
  logic       snoop_hit_cov;
  logic       snoop_dirty_cov;
  logic       miss_cov;

  covergroup cg_core @(posedge clk_i);
	cp_state: coverpoint dut.state_q {
	  bins lookup      = {STATE_LOOKUP};
	  bins refill      = {STATE_REFILL};
	  bins read_st     = {STATE_READ};
	  bins write_st    = {STATE_WRITE};
	  bins evict       = {STATE_EVICT};
	  bins inval       = {STATE_INVALIDATE};
	  bins writeback   = {STATE_WRITEBACK};
	  bins snoop_req   = {STATE_SNOOP_REQ};
	  bins snoop_check = {STATE_SNOOP_CHECK};
	  bins flushes[]   = {STATE_FLUSH_ADDR, STATE_FLUSH};
	}

	cp_op: coverpoint op_kind_cov {
	  bins rd    = {0};
	  bins wr    = {1};
	  bins inv   = {2};
	  bins wb    = {3};
	  bins fl    = {4};
	  bins snp   = {5};
	}

	cp_miss: coverpoint miss_cov {
	  bins hit  = {0};
	  bins miss = {1};
	}

	cp_snoop_cmd: coverpoint snoop_cmd_cov {
	  bins busrd   = {SNOOP_BUSRD};
	  bins busrdx  = {SNOOP_BUSRDX};
	  bins busupgr = {SNOOP_BUSUPGR};
	}

	cp_snoop_hit: coverpoint snoop_hit_cov     { bins nohit = {0}; bins hit = {1}; }
	cp_snoop_dirty: coverpoint snoop_dirty_cov { bins clean = {0}; bins dirty = {1}; }

	x_snoop: cross cp_snoop_cmd, cp_snoop_hit, cp_snoop_dirty {
	  ignore_bins miss_dirty =
		binsof(cp_snoop_hit) intersect {0} &&
		binsof(cp_snoop_dirty) intersect {1};

	  ignore_bins busupgr_dirty =
		binsof(cp_snoop_cmd) intersect {SNOOP_BUSUPGR} &&
		binsof(cp_snoop_dirty) intersect {1};
	}

	x_op_miss: cross cp_op, cp_miss {
	  ignore_bins non_lookup_ops =
		binsof(cp_op) intersect {2,3,4,5};
	}
  endgroup

  cg_core cov = new();

  // ------------------------------------------------------------
  // Utility functions/tasks
  // ------------------------------------------------------------
  function automatic [7:0] line_index(input [31:0] addr);
	line_index = addr[12:5];
  endfunction

  function automatic [18:0] addr_tag(input [31:0] addr);
	addr_tag = addr[31:13];
  endfunction

  function automatic [1:0] get_way_state(input int way, input [31:0] addr);
	logic [20:0] tagv;
	begin
	  if (way == 0)
		tagv = dut.u_tag0.ram[line_index(addr)];
	  else
		tagv = dut.u_tag1.ram[line_index(addr)];

	  get_way_state = tagv[20:19];
	end
  endfunction

  function automatic [18:0] get_way_tag(input int way, input [31:0] addr);
	logic [20:0] tagv;
	begin
	  if (way == 0)
		tagv = dut.u_tag0.ram[line_index(addr)];
	  else
		tagv = dut.u_tag1.ram[line_index(addr)];

	  get_way_tag = tagv[18:0];
	end
  endfunction

  function automatic bit way_hits_addr(input int way, input [31:0] addr);
	logic [1:0] st;
	logic [18:0] tg;
	begin
	  st = get_way_state(way, addr);
	  tg = get_way_tag(way, addr);
	  way_hits_addr = (st != MSI_I) && (tg == addr_tag(addr));
	end
  endfunction

  function automatic bit line_present(input [31:0] addr);
	line_present = way_hits_addr(0, addr) || way_hits_addr(1, addr);
  endfunction

  function automatic bit line_modified(input [31:0] addr);
	line_modified =
	  (way_hits_addr(0, addr) && (get_way_state(0, addr) == MSI_M)) ||
	  (way_hits_addr(1, addr) && (get_way_state(1, addr) == MSI_M));
  endfunction

  function automatic bit line_shared(input [31:0] addr);
	line_shared =
	  (way_hits_addr(0, addr) && (get_way_state(0, addr) == MSI_S)) ||
	  (way_hits_addr(1, addr) && (get_way_state(1, addr) == MSI_S));
  endfunction

  task automatic clear_cpu_inputs;
	begin
	  mem_addr_i       = 32'h0;
	  mem_data_wr_i    = 32'h0;
	  mem_rd_i         = 1'b0;
	  mem_wr_i         = 4'h0;
	  mem_cacheable_i  = 1'b1;
	  mem_req_tag_i    = 11'h0;
	  mem_invalidate_i = 1'b0;
	  mem_writeback_i  = 1'b0;
	  mem_flush_i      = 1'b0;
	end
  endtask

  task automatic clear_snoop_inputs;
	begin
	  snoop_valid_i = 1'b0;
	  snoop_cmd_i   = 2'b0;
	  snoop_addr_i  = 32'h0;
	end
  endtask

  task automatic wait_lookup;
	int timeout;
	begin
	  timeout = 10000;
	  while (dut.state_q !== STATE_LOOKUP && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail("timeout waiting for STATE_LOOKUP");
	end
  endtask

  task automatic wait_mem_accept;
	int timeout;
	begin
	  timeout = 1000;
	  while (!mem_accept_o && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail("timeout waiting for mem_accept_o");
	end
  endtask

  task automatic wait_mem_ack;
	int timeout;
	begin
	  timeout = 10000;
	  while (!mem_ack_o && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail("timeout waiting for mem_ack_o");
	end
  endtask

  task automatic cpu_read(input [31:0] addr, input [10:0] tag, output [31:0] data);
	begin
	  op_kind_cov = 0;
	  miss_cov    = line_present(addr) ? 0 : 1;

	  @(posedge clk_i);
	  mem_addr_i       <= addr;
	  mem_data_wr_i    <= 32'h0;
	  mem_rd_i         <= 1'b1;
	  mem_wr_i         <= 4'h0;
	  mem_cacheable_i  <= 1'b1;
	  mem_req_tag_i    <= tag;
	  mem_invalidate_i <= 1'b0;
	  mem_writeback_i  <= 1'b0;
	  mem_flush_i      <= 1'b0;

	  wait_mem_accept();

	  @(posedge clk_i);
	  mem_rd_i   <= 1'b0;
	  mem_addr_i <= 32'h0;

	  wait_mem_ack();
	  #1;
	  data = mem_data_rd_o;
	  check_eq1("cpu_read tag", (mem_resp_tag_o == tag), 1'b1);
	  @(posedge clk_i);
	end
  endtask

  task automatic cpu_write(input [31:0] addr, input [31:0] data, input [3:0] strb, input [10:0] tag);
	begin
	  op_kind_cov = 1;
	  miss_cov    = line_present(addr) ? 0 : 1;

	  @(posedge clk_i);
	  mem_addr_i       <= addr;
	  mem_data_wr_i    <= data;
	  mem_rd_i         <= 1'b0;
	  mem_wr_i         <= strb;
	  mem_cacheable_i  <= 1'b1;
	  mem_req_tag_i    <= tag;
	  mem_invalidate_i <= 1'b0;
	  mem_writeback_i  <= 1'b0;
	  mem_flush_i      <= 1'b0;

	  wait_mem_accept();

	  @(posedge clk_i);
	  mem_wr_i       <= 4'h0;
	  mem_addr_i     <= 32'h0;
	  mem_data_wr_i  <= 32'h0;

	  wait_mem_ack();
	  #1;
	  check_eq1("cpu_write tag", (mem_resp_tag_o == tag), 1'b1);
	  @(posedge clk_i);
	end
  endtask

  task automatic cpu_invalidate(input [31:0] addr, input [10:0] tag);
	begin
	  op_kind_cov = 2;
	  miss_cov    = 0;

	  @(posedge clk_i);
	  mem_addr_i       <= addr;
	  mem_data_wr_i    <= 32'h0;
	  mem_rd_i         <= 1'b0;
	  mem_wr_i         <= 4'h0;
	  mem_cacheable_i  <= 1'b1;
	  mem_req_tag_i    <= tag;
	  mem_invalidate_i <= 1'b1;
	  mem_writeback_i  <= 1'b0;
	  mem_flush_i      <= 1'b0;

	  wait_mem_accept();

	  @(posedge clk_i);
	  mem_invalidate_i <= 1'b0;
	  mem_addr_i       <= 32'h0;

	  wait_mem_ack();
	  #1;
	  check_eq1("cpu_invalidate tag", (mem_resp_tag_o == tag), 1'b1);
	  @(posedge clk_i);
	
	end
  endtask

  task automatic cpu_writeback(input [31:0] addr, input [10:0] tag);
	begin
	  op_kind_cov = 3;
	  miss_cov    = 0;

	  @(posedge clk_i);
	  mem_addr_i       <= addr;
	  mem_data_wr_i    <= 32'h0;
	  mem_rd_i         <= 1'b0;
	  mem_wr_i         <= 4'h0;
	  mem_cacheable_i  <= 1'b1;
	  mem_req_tag_i    <= tag;
	  mem_invalidate_i <= 1'b0;
	  mem_writeback_i  <= 1'b1;
	  mem_flush_i      <= 1'b0;

	  wait_mem_accept();

	  @(posedge clk_i);
	  mem_writeback_i <= 1'b0;
	  mem_addr_i      <= 32'h0;

	  wait_mem_ack();
	  #1;
	  check_eq1("cpu_writeback tag", (mem_resp_tag_o == tag), 1'b1);
	  @(posedge clk_i);
	end
  endtask

  task automatic cpu_flush(input [10:0] tag);
	begin
	  op_kind_cov = 4;
	  miss_cov    = 0;

	  @(posedge clk_i);
	  mem_addr_i       <= 32'h0;
	  mem_data_wr_i    <= 32'h0;
	  mem_rd_i         <= 1'b0;
	  mem_wr_i         <= 4'h0;
	  mem_cacheable_i  <= 1'b1;
	  mem_req_tag_i    <= tag;
	  mem_invalidate_i <= 1'b0;
	  mem_writeback_i  <= 1'b0;
	  mem_flush_i      <= 1'b1;

	  wait_mem_accept();

	  @(posedge clk_i);
	  mem_flush_i <= 1'b0;

	  wait_mem_ack();
	  #1;
	  check_eq1("cpu_flush tag", (mem_resp_tag_o == tag), 1'b1);
	  @(posedge clk_i);
	end
  endtask

  task automatic do_snoop
  (
	input  [1:0]  cmd,
	input  [31:0] addr,
	output logic  hit,
	output logic  dirty
  );
	int timeout;
	begin
	  op_kind_cov   = 5;
	  snoop_cmd_cov = cmd;

	  @(posedge clk_i);
	  snoop_valid_i <= 1'b1;
	  snoop_cmd_i   <= cmd;
	  snoop_addr_i  <= addr;

	  timeout = 1000;
	  while (!snoop_ack_o && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end

	  if (timeout == 0)
		fail("timeout waiting for snoop_ack_o");

	  #1;
	  hit   = snoop_hit_o;
	  dirty = snoop_dirty_o;
	  snoop_hit_cov   = hit;
	  snoop_dirty_cov = dirty;

	  @(posedge clk_i);
	  snoop_valid_i <= 1'b0;
	  snoop_cmd_i   <= 2'b0;
	  snoop_addr_i  <= 32'h0;
	end
  endtask

  // ------------------------------------------------------------
  // Tests
  // ------------------------------------------------------------
  task automatic test_reset_idle;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] reset_idle");
	  wait_lookup();
	  check_eq1("state after reset is LOOKUP", (dut.state_q == STATE_LOOKUP), 1'b1);
	  check_eq1("mem_ack_o after reset", mem_ack_o, 1'b0);
	  check_eq1("snoop_ack_o after reset", snoop_ack_o, 1'b0);
	end
  endtask

  task automatic test_read_miss_then_hit;
	logic [31:0] rd;
	logic [31:0] a;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] read_miss_then_hit");
	  a = 32'h0000_1048;

	  cpu_read(a, 11'h011, rd);
	  check_eq32("read miss refill data", rd, model_mem[a[17:2]]);
	  check_true("line present after refill", line_present(a));
	  check_true("line shared after read refill", line_shared(a));

	  cpu_read(a, 11'h012, rd);
	  check_eq32("read hit data", rd, model_mem[a[17:2]]);
	  check_true("line still present", line_present(a));
	  check_true("line still shared", line_shared(a));
	end
  endtask

  task automatic test_write_miss_then_hit;
	logic [31:0] rd;
	logic [31:0] a;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] write_miss_then_hit");
	  a = 32'h0000_208c;

	  cpu_write(a, 32'hdeadbeef, 4'hF, 11'h021);
	  check_true("line present after write miss", line_present(a));
	  check_true("line modified after write miss", line_modified(a));

	  cpu_read(a, 11'h022, rd);
	  check_eq32("read back after write miss", rd, 32'hdeadbeef);

	  cpu_write(a, 32'hc001d00d, 4'hF, 11'h023);
	  check_true("line remains modified after write hit", line_modified(a));

	  cpu_read(a, 11'h024, rd);
	  check_eq32("read back after write hit", rd, 32'hc001d00d);
	end
  endtask

  task automatic test_invalidate;
	logic [31:0] rd;
	logic [31:0] a;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] invalidate");
	  a = 32'h0000_3040;

	  cpu_read(a, 11'h031, rd);
	  check_true("line present before invalidate", line_present(a));

	  cpu_invalidate(a, 11'h032);
	  check_eq1("line absent after invalidate", line_present(a), 1'b0);
	end
  endtask

  task automatic test_writeback;
	logic [31:0] a;
	logic [31:0] line_base;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] writeback");
	  a = 32'h0000_4100;

	  cpu_write(a + 32'd0,  32'h11111111, 4'hF, 11'h041);
	  cpu_write(a + 32'd4,  32'h22222222, 4'hF, 11'h042);
	  cpu_write(a + 32'd8,  32'h33333333, 4'hF, 11'h043);
	  cpu_write(a + 32'd12, 32'h44444444, 4'hF, 11'h044);

	  check_true("line modified before writeback", line_modified(a));

	  cpu_writeback(a, 11'h045);

	  line_base = {a[31:5], 5'b0};
	  check_eq32("memory writeback word0", model_mem[(line_base >> 2) + 0], 32'h11111111);
	  check_eq32("memory writeback word1", model_mem[(line_base >> 2) + 1], 32'h22222222);
	  check_eq32("memory writeback word2", model_mem[(line_base >> 2) + 2], 32'h33333333);
	  check_eq32("memory writeback word3", model_mem[(line_base >> 2) + 3], 32'h44444444);
	end
  endtask

  task automatic test_flush;
	logic [31:0] a0;
	logic [31:0] a1;
	logic [31:0] rd;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] flush");

	  a0 = 32'h0000_5000;
	  a1 = 32'h0000_6000;

	  cpu_write(a0, 32'haaaa5555, 4'hF, 11'h051);
	  cpu_read(a1, 11'h052, rd);

	  check_true("a0 present before flush", line_present(a0));
	  check_true("a1 present before flush", line_present(a1));

	  cpu_flush(11'h053);

	  check_eq1("a0 absent after flush", line_present(a0), 1'b0);
	  check_eq1("a1 absent after flush", line_present(a1), 1'b0);
	end
  endtask

  task automatic test_snoop_busrd_on_modified;
	logic [31:0] a;
	logic        hit;
	logic        dirty;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] snoop_busrd_on_modified");

	  a = 32'h0000_7100;
	  cpu_write(a, 32'h13579bdf, 4'hF, 11'h061);
	  check_true("line modified before busrd", line_modified(a));

	  do_snoop(SNOOP_BUSRD, a, hit, dirty);
	  check_eq1("snoop busrd hit", hit, 1'b1);
	  check_eq1("snoop busrd dirty", dirty, 1'b1);
	  check_true("line downgraded to shared after busrd", line_shared(a));
	end
  endtask

  task automatic test_snoop_busrdx_on_shared;
	logic [31:0] a;
	logic [31:0] rd;
	logic        hit;
	logic        dirty;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] snoop_busrdx_on_shared");

	  a = 32'h0000_7200;
	  cpu_read(a, 11'h071, rd);
	  check_true("line shared before busrdx", line_shared(a));

	  do_snoop(SNOOP_BUSRDX, a, hit, dirty);
	  check_eq1("snoop busrdx hit", hit, 1'b1);
	  check_eq1("snoop busrdx dirty", dirty, 1'b0);
	  check_eq1("line absent after busrdx", line_present(a), 1'b0);
	end
  endtask

  task automatic test_snoop_busupgr_on_shared;
	logic [31:0] a;
	logic [31:0] rd;
	logic        hit;
	logic        dirty;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] snoop_busupgr_on_shared");

	  a = 32'h0000_7300;
	  cpu_read(a, 11'h081, rd);
	  check_true("line shared before busupgr", line_shared(a));

	  do_snoop(SNOOP_BUSUPGR, a, hit, dirty);
	  check_eq1("snoop busupgr hit", hit, 1'b1);
	  check_eq1("snoop busupgr dirty", dirty, 1'b0);
	  check_eq1("line absent after busupgr", line_present(a), 1'b0);
	end
  endtask

  task automatic test_snoop_miss;
	logic [31:0] a;
	logic        hit;
	logic        dirty;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] snoop_miss");

	  a = 32'h0000_7f00;
	  do_snoop(SNOOP_BUSRD, a, hit, dirty);
	  check_eq1("snoop miss hit=0", hit, 1'b0);
	  check_eq1("snoop miss dirty=0", dirty, 1'b0);
	end
  endtask

  task automatic test_random;
	int i;
	int sel;
	logic [31:0] a;
	logic [31:0] d;
	logic [31:0] rd;
	logic [3:0]  strb;
	logic        hit;
	logic        dirty;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] random");

	  for (i = 0; i < 250; i++) begin
		a    = {16'h0000, $urandom_range(0, 16'h7fff)};
		a[1:0] = 2'b00;
		d    = $urandom;
		strb = $urandom_range(1, 15);
		sel  = $urandom_range(0, 6);

		case (sel)
		  0: cpu_read(a, $urandom_range(0, 2047), rd);
		  1: cpu_write(a, d, 4'hF, $urandom_range(0, 2047));
		  2: cpu_write(a, d, strb, $urandom_range(0, 2047));
		  3: cpu_invalidate(a, $urandom_range(0, 2047));
		  4: cpu_writeback(a, $urandom_range(0, 2047));
		  5: do_snoop($urandom_range(0,2), a, hit, dirty);
		  6: cpu_flush($urandom_range(0, 2047));
		endcase

		wait_lookup();
	  end

	  pass("random completed");
	end
  endtask

  task automatic init_model_mem;
	integer i;
	begin
	  for (i = 0; i < 65536; i = i + 1)
		model_mem[i] = 32'h1000_0000 ^ (i * 32'h0101_0101);
	end
  endtask

  initial begin
	pass_count = 0;
	fail_count = 0;
	test_count = 0;

	clear_cpu_inputs();
	clear_snoop_inputs();

	rst_i = 1'b1;
	init_model_mem();

`ifdef FSDB
	$fsdbDumpfile("tb_dcache_core_l2.fsdb");
	$fsdbDumpvars(0, tb_dcache_core_l2);
`else
	$dumpfile("tb_dcache_core_l2.vcd");
	$dumpvars(0, tb_dcache_core_l2);
`endif

	repeat (10) @(posedge clk_i);
	rst_i = 1'b0;

	wait_lookup();

	test_reset_idle();
	test_read_miss_then_hit();
	test_write_miss_then_hit();
	test_invalidate();
	test_writeback();
	test_flush();
	test_snoop_busrd_on_modified();
	test_snoop_busrdx_on_shared();
	test_snoop_busupgr_on_shared();
	test_snoop_miss();
	test_random();

	$display("==================================================");
	$display("DCACHE_CORE_L2 TB SUMMARY");
	$display("  test_count = %0d", test_count);
	$display("  pass_count = %0d", pass_count);
	$display("  fail_count = %0d", fail_count);
	$display("==================================================");

	if (fail_count == 0)
	  $display("TB PASSED");
	else
	  $display("TB FAILED");

	#50;
	$finish;
  end

endmodule