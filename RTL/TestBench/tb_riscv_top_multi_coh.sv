`timescale 1ns/1ps

import coherence_pkg::*;

module tb_riscv_top_multi_coh;

  localparam int NUM_CORES  = 4;
  localparam int CORE_IDX_W = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES);

  localparam logic [1:0] MSI_I = 2'b00;
  localparam logic [1:0] MSI_S = 2'b01;
  localparam logic [1:0] MSI_M = 2'b10;

  localparam int STATE_LOOKUP = 4'd3;

  // ------------------------------------------------------------
  // DUT inputs
  // ------------------------------------------------------------
  logic                              clk_i;
  logic                              rst_i;
  logic [NUM_CORES-1:0]              rst_cpu_i;

  logic [NUM_CORES-1:0]              coh_req_valid_i;
  snoop_cmd_t [NUM_CORES-1:0]        coh_req_cmd_i;
  logic [NUM_CORES-1:0][31:0]        coh_req_addr_i;
  wire  [NUM_CORES-1:0]              coh_req_ready_o;

  logic [NUM_CORES-1:0]              axi_i_awready_i;
  logic [NUM_CORES-1:0]              axi_i_wready_i;
  logic [NUM_CORES-1:0]              axi_i_bvalid_i;
  logic [NUM_CORES-1:0][1:0]         axi_i_bresp_i;
  logic [NUM_CORES-1:0][3:0]         axi_i_bid_i;
  logic [NUM_CORES-1:0]              axi_i_arready_i;
  logic [NUM_CORES-1:0]              axi_i_rvalid_i;
  logic [NUM_CORES-1:0][31:0]        axi_i_rdata_i;
  logic [NUM_CORES-1:0][1:0]         axi_i_rresp_i;
  logic [NUM_CORES-1:0][3:0]         axi_i_rid_i;
  logic [NUM_CORES-1:0]              axi_i_rlast_i;

  logic [NUM_CORES-1:0]              axi_d_awready_i;
  logic [NUM_CORES-1:0]              axi_d_wready_i;
  logic [NUM_CORES-1:0]              axi_d_bvalid_i;
  logic [NUM_CORES-1:0][1:0]         axi_d_bresp_i;
  logic [NUM_CORES-1:0][3:0]         axi_d_bid_i;
  logic [NUM_CORES-1:0]              axi_d_arready_i;
  logic [NUM_CORES-1:0]              axi_d_rvalid_i;
  logic [NUM_CORES-1:0][31:0]        axi_d_rdata_i;
  logic [NUM_CORES-1:0][1:0]         axi_d_rresp_i;
  logic [NUM_CORES-1:0][3:0]         axi_d_rid_i;
  logic [NUM_CORES-1:0]              axi_d_rlast_i;

  logic [NUM_CORES-1:0]              intr_i;
  logic [NUM_CORES-1:0][31:0]        reset_vector_i;

  // ------------------------------------------------------------
  // DUT outputs
  // ------------------------------------------------------------
  wire [NUM_CORES-1:0]               axi_i_awvalid_o;
  wire [NUM_CORES-1:0][31:0]         axi_i_awaddr_o;
  wire [NUM_CORES-1:0][3:0]          axi_i_awid_o;
  wire [NUM_CORES-1:0][7:0]          axi_i_awlen_o;
  wire [NUM_CORES-1:0][1:0]          axi_i_awburst_o;
  wire [NUM_CORES-1:0]               axi_i_wvalid_o;
  wire [NUM_CORES-1:0][31:0]         axi_i_wdata_o;
  wire [NUM_CORES-1:0][3:0]          axi_i_wstrb_o;
  wire [NUM_CORES-1:0]               axi_i_wlast_o;
  wire [NUM_CORES-1:0]               axi_i_bready_o;
  wire [NUM_CORES-1:0]               axi_i_arvalid_o;
  wire [NUM_CORES-1:0][31:0]         axi_i_araddr_o;
  wire [NUM_CORES-1:0][3:0]          axi_i_arid_o;
  wire [NUM_CORES-1:0][7:0]          axi_i_arlen_o;
  wire [NUM_CORES-1:0][1:0]          axi_i_arburst_o;
  wire [NUM_CORES-1:0]               axi_i_rready_o;

  wire [NUM_CORES-1:0]               axi_d_awvalid_o;
  wire [NUM_CORES-1:0][31:0]         axi_d_awaddr_o;
  wire [NUM_CORES-1:0][3:0]          axi_d_awid_o;
  wire [NUM_CORES-1:0][7:0]          axi_d_awlen_o;
  wire [NUM_CORES-1:0][1:0]          axi_d_awburst_o;
  wire [NUM_CORES-1:0]               axi_d_wvalid_o;
  wire [NUM_CORES-1:0][31:0]         axi_d_wdata_o;
  wire [NUM_CORES-1:0][3:0]          axi_d_wstrb_o;
  wire [NUM_CORES-1:0]               axi_d_wlast_o;
  wire [NUM_CORES-1:0]               axi_d_bready_o;
  wire [NUM_CORES-1:0]               axi_d_arvalid_o;
  wire [NUM_CORES-1:0][31:0]         axi_d_araddr_o;
  wire [NUM_CORES-1:0][3:0]          axi_d_arid_o;
  wire [NUM_CORES-1:0][7:0]          axi_d_arlen_o;
  wire [NUM_CORES-1:0][1:0]          axi_d_arburst_o;
  wire [NUM_CORES-1:0]               axi_d_rready_o;

  wire                               coh_trans_done_o;
  wire [CORE_IDX_W-1:0]              coh_trans_core_o;
  wire snoop_cmd_t                   coh_trans_cmd_o;
  wire [31:0]                        coh_trans_addr_o;
  wire                               coh_trans_shared_o;
  wire                               coh_trans_dirty_o;
  wire                               coh_trans_need_mem_read_o;
  wire                               coh_trans_need_writeback_o;
  wire                               coh_busy_o;

  wire [NUM_CORES-1:0]               snoop_hit_o;
  wire [NUM_CORES-1:0]               snoop_dirty_o;
  wire [NUM_CORES-1:0]               snoop_ack_o;
  wire [NUM_CORES-1:0][31:0]         cpu_id_o;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv_top_multi #(
	.NUM_CORES(NUM_CORES)
  ) dut (
	.clk_i(clk_i),
	.rst_i(rst_i),
	.rst_cpu_i(rst_cpu_i),

	.coh_req_valid_i(coh_req_valid_i),
	.coh_req_cmd_i(coh_req_cmd_i),
	.coh_req_addr_i(coh_req_addr_i),
	.coh_req_ready_o(coh_req_ready_o),

	.axi_i_awready_i(axi_i_awready_i),
	.axi_i_wready_i(axi_i_wready_i),
	.axi_i_bvalid_i(axi_i_bvalid_i),
	.axi_i_bresp_i(axi_i_bresp_i),
	.axi_i_bid_i(axi_i_bid_i),
	.axi_i_arready_i(axi_i_arready_i),
	.axi_i_rvalid_i(axi_i_rvalid_i),
	.axi_i_rdata_i(axi_i_rdata_i),
	.axi_i_rresp_i(axi_i_rresp_i),
	.axi_i_rid_i(axi_i_rid_i),
	.axi_i_rlast_i(axi_i_rlast_i),

	.axi_d_awready_i(axi_d_awready_i),
	.axi_d_wready_i(axi_d_wready_i),
	.axi_d_bvalid_i(axi_d_bvalid_i),
	.axi_d_bresp_i(axi_d_bresp_i),
	.axi_d_bid_i(axi_d_bid_i),
	.axi_d_arready_i(axi_d_arready_i),
	.axi_d_rvalid_i(axi_d_rvalid_i),
	.axi_d_rdata_i(axi_d_rdata_i),
	.axi_d_rresp_i(axi_d_rresp_i),
	.axi_d_rid_i(axi_d_rid_i),
	.axi_d_rlast_i(axi_d_rlast_i),

	.intr_i(intr_i),
	.reset_vector_i(reset_vector_i),

	.axi_i_awvalid_o(axi_i_awvalid_o),
	.axi_i_awaddr_o(axi_i_awaddr_o),
	.axi_i_awid_o(axi_i_awid_o),
	.axi_i_awlen_o(axi_i_awlen_o),
	.axi_i_awburst_o(axi_i_awburst_o),
	.axi_i_wvalid_o(axi_i_wvalid_o),
	.axi_i_wdata_o(axi_i_wdata_o),
	.axi_i_wstrb_o(axi_i_wstrb_o),
	.axi_i_wlast_o(axi_i_wlast_o),
	.axi_i_bready_o(axi_i_bready_o),
	.axi_i_arvalid_o(axi_i_arvalid_o),
	.axi_i_araddr_o(axi_i_araddr_o),
	.axi_i_arid_o(axi_i_arid_o),
	.axi_i_arlen_o(axi_i_arlen_o),
	.axi_i_arburst_o(axi_i_arburst_o),
	.axi_i_rready_o(axi_i_rready_o),

	.axi_d_awvalid_o(axi_d_awvalid_o),
	.axi_d_awaddr_o(axi_d_awaddr_o),
	.axi_d_awid_o(axi_d_awid_o),
	.axi_d_awlen_o(axi_d_awlen_o),
	.axi_d_awburst_o(axi_d_awburst_o),
	.axi_d_wvalid_o(axi_d_wvalid_o),
	.axi_d_wdata_o(axi_d_wdata_o),
	.axi_d_wstrb_o(axi_d_wstrb_o),
	.axi_d_wlast_o(axi_d_wlast_o),
	.axi_d_bready_o(axi_d_bready_o),
	.axi_d_arvalid_o(axi_d_arvalid_o),
	.axi_d_araddr_o(axi_d_araddr_o),
	.axi_d_arid_o(axi_d_arid_o),
	.axi_d_arlen_o(axi_d_arlen_o),
	.axi_d_arburst_o(axi_d_arburst_o),
	.axi_d_rready_o(axi_d_rready_o),

	.coh_trans_done_o(coh_trans_done_o),
	.coh_trans_core_o(coh_trans_core_o),
	.coh_trans_cmd_o(coh_trans_cmd_o),
	.coh_trans_addr_o(coh_trans_addr_o),
	.coh_trans_shared_o(coh_trans_shared_o),
	.coh_trans_dirty_o(coh_trans_dirty_o),
	.coh_trans_need_mem_read_o(coh_trans_need_mem_read_o),
	.coh_trans_need_writeback_o(coh_trans_need_writeback_o),
	.coh_busy_o(coh_busy_o),

	.snoop_hit_o(snoop_hit_o),
	.snoop_dirty_o(snoop_dirty_o),
	.snoop_ack_o(snoop_ack_o),
	.cpu_id_o(cpu_id_o)
  );

  // ------------------------------------------------------------
  // Scoreboard
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

  task automatic check_eq1(input string name, input logic got, input logic exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%0b exp=%0b", name, got, exp));
	  else
		pass($sformatf("%s = %0b", name, got));
	end
  endtask

  task automatic check_eq32(input string name, input logic [31:0] got, input logic [31:0] exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%08x exp=%08x", name, got, exp));
	  else
		pass($sformatf("%s = %08x", name, got));
	end
  endtask

  task automatic check_eq_cmd(input string name, input snoop_cmd_t got, input snoop_cmd_t exp);
	begin
	  if (got !== exp)
		fail($sformatf("%s got=%0d exp=%0d", name, got, exp));
	  else
		pass($sformatf("%s = %0d", name, got));
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
  // Coverage
  // ------------------------------------------------------------
  logic [1:0] cov_cmd;
  logic       cov_shared;
  logic       cov_dirty;

  covergroup cg_top @(posedge clk_i);
	cp_cmd: coverpoint cov_cmd {
	  bins busrd   = {SNOOP_BUSRD};
	  bins busrdx  = {SNOOP_BUSRDX};
	  bins busupgr = {SNOOP_BUSUPGR};
	}
	cp_shared: coverpoint cov_shared { bins no = {0}; bins yes = {1}; }
	cp_dirty:  coverpoint cov_dirty  { bins no = {0}; bins yes = {1}; }

	x_cmd_resp: cross cp_cmd, cp_shared, cp_dirty {
	  ignore_bins miss_dirty =
		binsof(cp_shared) intersect {0} &&
		binsof(cp_dirty)  intersect {1};

	  ignore_bins busupgr_dirty =
		binsof(cp_cmd) intersect {SNOOP_BUSUPGR} &&
		binsof(cp_dirty) intersect {1};
	}
  endgroup

  cg_top cov = new();

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  function automatic [7:0] line_index(input [31:0] addr);
	line_index = addr[12:5];
  endfunction

  function automatic [18:0] addr_tag(input [31:0] addr);
	addr_tag = addr[31:13];
  endfunction

  task automatic clear_inputs;
	integer i;
	begin
	  rst_cpu_i       = '1; // hold CPUs in reset for this TB

	  coh_req_valid_i = '0;
	  for (i = 0; i < NUM_CORES; i++) begin
		coh_req_cmd_i[i]  = SNOOP_NONE;
		coh_req_addr_i[i] = 32'h0;
	  end

	  axi_i_awready_i = '1;
	  axi_i_wready_i  = '1;
	  axi_i_bvalid_i  = '0;
	  axi_i_bresp_i   = '0;
	  axi_i_bid_i     = '0;
	  axi_i_arready_i = '1;
	  axi_i_rvalid_i  = '0;
	  axi_i_rdata_i   = '0;
	  axi_i_rresp_i   = '0;
	  axi_i_rid_i     = '0;
	  axi_i_rlast_i   = '0;

	  axi_d_awready_i = '1;
	  axi_d_wready_i  = '1;
	  axi_d_bvalid_i  = '0;
	  axi_d_bresp_i   = '0;
	  axi_d_bid_i     = '0;
	  axi_d_arready_i = '1;
	  axi_d_rvalid_i  = '0;
	  axi_d_rdata_i   = '0;
	  axi_d_rresp_i   = '0;
	  axi_d_rid_i     = '0;
	  axi_d_rlast_i   = '0;

	  intr_i          = '0;
	  reset_vector_i  = '0;
	end
  endtask

  task automatic wait_all_dcache_lookup;
	  integer timeout;
	  bit all_lookup;
	  begin
		timeout = 20000;
		while (timeout > 0) begin
		  all_lookup =
			   (dut.gen_core[0].u_dcache.u_core.state_q === STATE_LOOKUP)
			&& (dut.gen_core[1].u_dcache.u_core.state_q === STATE_LOOKUP)
			&& (dut.gen_core[2].u_dcache.u_core.state_q === STATE_LOOKUP)
			&& (dut.gen_core[3].u_dcache.u_core.state_q === STATE_LOOKUP);

		  if (all_lookup)
			break;

		  @(posedge clk_i);
		  timeout = timeout - 1;
		end

		if (timeout == 0)
		  fail("timeout waiting for all dcache cores to reach LOOKUP");
		else
		  pass("all dcache cores reached LOOKUP");
	  end
	endtask

	task automatic clear_line(input int core, input [31:0] addr);
		int idx;
		begin
		  idx = line_index(addr);

		  case (core)
			0: begin
			  dut.gen_core[0].u_dcache.u_core.u_tag0.ram[idx] = 21'h0;
			  dut.gen_core[0].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			end
			1: begin
			  dut.gen_core[1].u_dcache.u_core.u_tag0.ram[idx] = 21'h0;
			  dut.gen_core[1].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			end
			2: begin
			  dut.gen_core[2].u_dcache.u_core.u_tag0.ram[idx] = 21'h0;
			  dut.gen_core[2].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			end
			3: begin
			  dut.gen_core[3].u_dcache.u_core.u_tag0.ram[idx] = 21'h0;
			  dut.gen_core[3].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			end
			default: ;
		  endcase
		end
	  endtask

	  task automatic program_line(input int core, input [31:0] addr, input [1:0] state);
		  int idx;
		  begin
			idx = line_index(addr);

			case (core)
			  0: begin
				dut.gen_core[0].u_dcache.u_core.u_tag0.ram[idx] = {state, addr_tag(addr)};
				dut.gen_core[0].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			  end
			  1: begin
				dut.gen_core[1].u_dcache.u_core.u_tag0.ram[idx] = {state, addr_tag(addr)};
				dut.gen_core[1].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			  end
			  2: begin
				dut.gen_core[2].u_dcache.u_core.u_tag0.ram[idx] = {state, addr_tag(addr)};
				dut.gen_core[2].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			  end
			  3: begin
				dut.gen_core[3].u_dcache.u_core.u_tag0.ram[idx] = {state, addr_tag(addr)};
				dut.gen_core[3].u_dcache.u_core.u_tag1.ram[idx] = 21'h0;
			  end
			  default: ;
			endcase
		  end
		endtask

		function automatic [1:0] line_state(input int core, input [31:0] addr);
			logic [20:0] t0;
			logic [20:0] t1;
			int idx;
			begin
			  idx = line_index(addr);
			  t0  = 21'h0;
			  t1  = 21'h0;

			  case (core)
				0: begin
				  t0 = dut.gen_core[0].u_dcache.u_core.u_tag0.ram[idx];
				  t1 = dut.gen_core[0].u_dcache.u_core.u_tag1.ram[idx];
				end
				1: begin
				  t0 = dut.gen_core[1].u_dcache.u_core.u_tag0.ram[idx];
				  t1 = dut.gen_core[1].u_dcache.u_core.u_tag1.ram[idx];
				end
				2: begin
				  t0 = dut.gen_core[2].u_dcache.u_core.u_tag0.ram[idx];
				  t1 = dut.gen_core[2].u_dcache.u_core.u_tag1.ram[idx];
				end
				3: begin
				  t0 = dut.gen_core[3].u_dcache.u_core.u_tag0.ram[idx];
				  t1 = dut.gen_core[3].u_dcache.u_core.u_tag1.ram[idx];
				end
				default: begin
				  t0 = 21'h0;
				  t1 = 21'h0;
				end
			  endcase

			  if ((t0[20:19] != MSI_I) && (t0[18:0] == addr_tag(addr)))
				line_state = t0[20:19];
			  else if ((t1[20:19] != MSI_I) && (t1[18:0] == addr_tag(addr)))
				line_state = t1[20:19];
			  else
				line_state = MSI_I;
			end
		  endfunction

  task automatic issue_coh_req(
	input int src,
	input snoop_cmd_t cmd,
	input logic [31:0] addr
  );
	begin
	  @(posedge clk_i);
	  coh_req_valid_i[src] <= 1'b1;
	  coh_req_cmd_i[src]   <= cmd;
	  coh_req_addr_i[src]  <= addr;

	  @(posedge clk_i);
	  if (!coh_req_ready_o[src])
		fail($sformatf("coh request from core%0d not accepted", src));
	  else
		pass($sformatf("coh request from core%0d accepted", src));

	  coh_req_valid_i[src] <= 1'b0;
	  coh_req_cmd_i[src]   <= SNOOP_NONE;
	  coh_req_addr_i[src]  <= 32'h0;
	end
  endtask

  task automatic wait_trans_done;
	integer timeout;
	begin
	  timeout = 5000;
	  while (!coh_trans_done_o && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail("timeout waiting for coh_trans_done_o");
	end
  endtask

  task automatic check_result(
		  input int src,
		  input snoop_cmd_t cmd,
		  input logic [31:0] addr,
		  input logic shared,
		  input logic dirty,
		  input logic need_mem_read,
		  input logic need_wb
		);
		  begin
			wait_trans_done();

			cov_cmd    = cmd;
			cov_shared = shared;
			cov_dirty  = dirty;

			// Do NOT re-check coh_trans_done_o level here.
			// wait_trans_done() already confirmed the pulse happened.

			check_eq32("coh_trans_addr_o", coh_trans_addr_o, addr);
			check_eq_cmd("coh_trans_cmd_o", coh_trans_cmd_o, cmd);
			check_eq32("coh_trans_core_o", coh_trans_core_o, src);
			check_eq1 ("coh_trans_shared_o", coh_trans_shared_o, shared);
			check_eq1 ("coh_trans_dirty_o", coh_trans_dirty_o, dirty);
			check_eq1 ("coh_trans_need_mem_read_o", coh_trans_need_mem_read_o, need_mem_read);
			check_eq1 ("coh_trans_need_writeback_o", coh_trans_need_writeback_o, need_wb);

			@(posedge clk_i);
			check_eq1("coh_trans_done_o pulse clears", coh_trans_done_o, 1'b0);
		  end
		endtask

  // ------------------------------------------------------------
  // Tests
  // ------------------------------------------------------------
  task automatic test_reset_idle;
	integer c;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] reset_idle");

	  wait_all_dcache_lookup();

	  check_eq1("coh_busy_o after reset", coh_busy_o, 1'b0);
	  check_eq1("coh_trans_done_o after reset", coh_trans_done_o, 1'b0);

	  for (c = 0; c < NUM_CORES; c++) begin
		check_eq1($sformatf("snoop_ack_o core%0d after reset", c), snoop_ack_o[c], 1'b0);
	  end
	end
  endtask

  task automatic test_busrd_modified_downgrade;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrd_modified_downgrade");

	  addr = 32'h8000_1000;

	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  program_line(0, addr, MSI_M);

	  issue_coh_req(1, SNOOP_BUSRD, addr);
	  check_result(1, SNOOP_BUSRD, addr, 1'b1, 1'b1, 1'b0, 1'b1);

	  check_eq1("core0 downgraded M->S", (line_state(0, addr) == MSI_S), 1'b1);
	  check_eq1("core2 stays I",         (line_state(2, addr) == MSI_I), 1'b1);
	  check_eq1("core3 stays I",         (line_state(3, addr) == MSI_I), 1'b1);
	end
  endtask

  task automatic test_busrdx_shared_invalidate;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrdx_shared_invalidate");

	  addr = 32'h8000_2000;

	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  program_line(0, addr, MSI_S);
	  program_line(1, addr, MSI_S);

	  issue_coh_req(2, SNOOP_BUSRDX, addr);
	  check_result(2, SNOOP_BUSRDX, addr, 1'b1, 1'b0, 1'b1, 1'b0);

	  check_eq1("core0 invalidated S->I", (line_state(0, addr) == MSI_I), 1'b1);
	  check_eq1("core1 invalidated S->I", (line_state(1, addr) == MSI_I), 1'b1);
	  check_eq1("core3 stays I",          (line_state(3, addr) == MSI_I), 1'b1);
	end
  endtask

  task automatic test_busupgr_shared_invalidate;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busupgr_shared_invalidate");

	  addr = 32'h8000_3000;

	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  program_line(0, addr, MSI_S);
	  program_line(3, addr, MSI_S);

	  issue_coh_req(1, SNOOP_BUSUPGR, addr);
	  check_result(1, SNOOP_BUSUPGR, addr, 1'b1, 1'b0, 1'b0, 1'b0);

	  check_eq1("core0 invalidated S->I", (line_state(0, addr) == MSI_I), 1'b1);
	  check_eq1("core3 invalidated S->I", (line_state(3, addr) == MSI_I), 1'b1);
	  check_eq1("core2 stays I",          (line_state(2, addr) == MSI_I), 1'b1);
	end
  endtask

  task automatic test_busrd_nohit;
	logic [31:0] addr;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrd_nohit");

	  addr = 32'h8000_4000;

	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  issue_coh_req(0, SNOOP_BUSRD, addr);
	  check_result(0, SNOOP_BUSRD, addr, 1'b0, 1'b0, 1'b1, 1'b0);

	  check_eq1("core1 stays I", (line_state(1, addr) == MSI_I), 1'b1);
	  check_eq1("core2 stays I", (line_state(2, addr) == MSI_I), 1'b1);
	  check_eq1("core3 stays I", (line_state(3, addr) == MSI_I), 1'b1);
	end
  endtask

  task automatic test_random;
	int iter;
	int src;
	int c;
	logic [31:0] addr;
	snoop_cmd_t cmd;
	logic [1:0] preload_state [0:NUM_CORES-1];
	logic exp_shared;
	logic exp_dirty;
	logic exp_need_mem_read;
	logic exp_need_wb;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] random");

	  for (iter = 0; iter < 120; iter++) begin
		src      = $urandom_range(0, NUM_CORES-1);
		addr     = 32'h8000_8000 + (iter * 32'h40);

		case ($urandom_range(0,2))
		  0: cmd = SNOOP_BUSRD;
		  1: cmd = SNOOP_BUSRDX;
		  default: cmd = SNOOP_BUSUPGR;
		endcase

		for (c = 0; c < NUM_CORES; c++) begin
		  clear_line(c, addr);

		  if (c == src) begin
			preload_state[c] = MSI_I;
		  end
		  else begin
			if (cmd == SNOOP_BUSUPGR) begin
			  preload_state[c] = ($urandom_range(0,1) == 0) ? MSI_I : MSI_S;
			end
			else begin
			  case ($urandom_range(0,2))
				0: preload_state[c] = MSI_I;
				1: preload_state[c] = MSI_S;
				default: preload_state[c] = MSI_M;
			  endcase
			end

			if (preload_state[c] != MSI_I)
			  program_line(c, addr, preload_state[c]);
		  end
		end

		exp_shared = 1'b0;
		exp_dirty  = 1'b0;

		for (c = 0; c < NUM_CORES; c++) begin
		  if (c != src) begin
			if (preload_state[c] != MSI_I)
			  exp_shared = 1'b1;
			if (preload_state[c] == MSI_M)
			  exp_dirty = 1'b1;
		  end
		end

		if (cmd == SNOOP_BUSUPGR)
		  exp_need_mem_read = 1'b0;
		else
		  exp_need_mem_read = ~exp_dirty;

		exp_need_wb = exp_dirty;

		issue_coh_req(src, cmd, addr);
		check_result(src, cmd, addr, exp_shared, exp_dirty, exp_need_mem_read, exp_need_wb);

		for (c = 0; c < NUM_CORES; c++) begin
		  if (c != src) begin
			case (cmd)
			  SNOOP_BUSRD: begin
				if (preload_state[c] == MSI_M)
				  check_eq1($sformatf("rand core%0d M->S", c), (line_state(c, addr) == MSI_S), 1'b1);
				else if (preload_state[c] == MSI_S)
				  check_eq1($sformatf("rand core%0d S stays S", c), (line_state(c, addr) == MSI_S), 1'b1);
				else
				  check_eq1($sformatf("rand core%0d I stays I", c), (line_state(c, addr) == MSI_I), 1'b1);
			  end

			  SNOOP_BUSRDX: begin
				if (preload_state[c] != MSI_I)
				  check_eq1($sformatf("rand core%0d -> I on BUSRDX", c), (line_state(c, addr) == MSI_I), 1'b1);
				else
				  check_eq1($sformatf("rand core%0d I stays I on BUSRDX", c), (line_state(c, addr) == MSI_I), 1'b1);
			  end

			  SNOOP_BUSUPGR: begin
				if (preload_state[c] == MSI_S)
				  check_eq1($sformatf("rand core%0d S->I on BUSUPGR", c), (line_state(c, addr) == MSI_I), 1'b1);
				else
				  check_eq1($sformatf("rand core%0d unchanged on BUSUPGR", c), (line_state(c, addr) == preload_state[c]), 1'b1);
			  end

			  default: ;
			endcase
		  end
		end
	  end

	  pass("random completed");
	end
  endtask

  // ------------------------------------------------------------
  // Main
  // ------------------------------------------------------------
  initial begin
	pass_count = 0;
	fail_count = 0;
	test_count = 0;

	clear_inputs();
	rst_i = 1'b1;

	`ifdef FSDB
	  $fsdbDumpfile("tb_riscv_top_multi_coh.fsdb");
	  $fsdbDumpvars(0, tb_riscv_top_multi_coh);
	`else
	  $dumpfile("tb_riscv_top_multi_coh.vcd");
	  $dumpvars(0, tb_riscv_top_multi_coh);
	`endif

	repeat (10) @(posedge clk_i);
	rst_i = 1'b0;

	test_reset_idle();
	test_busrd_modified_downgrade();
	test_busrdx_shared_invalidate();
	test_busupgr_shared_invalidate();
	test_busrd_nohit();
	test_random();

	$display("==================================================");
	$display("RISCV_TOP_MULTI_COH TB SUMMARY");
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