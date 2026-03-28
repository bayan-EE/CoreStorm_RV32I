`timescale 1ns/1ps

import coherence_pkg::*;

module tb_riscv_top_multi_coh_auto;

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

  wire [NUM_CORES-1:0]               coh_req_ready_o;
  wire [NUM_CORES-1:0]               coh_req_valid_dbg_o;
  wire [NUM_CORES-1:0][1:0]          coh_req_cmd_dbg_o;
  wire [NUM_CORES-1:0][31:0]         coh_req_addr_dbg_o;

  wire [NUM_CORES-1:0]               snoop_hit_o;
  wire [NUM_CORES-1:0]               snoop_dirty_o;
  wire [NUM_CORES-1:0]               snoop_ack_o;
  wire [NUM_CORES-1:0][31:0]         cpu_id_o;
  
  // ------------------------------------------------------------
  // Sticky monitors for one-cycle pulses
  // ------------------------------------------------------------
  logic                        trans_seen_q;
  logic [CORE_IDX_W-1:0]       trans_core_seen_q;
  snoop_cmd_t                  trans_cmd_seen_q;
  logic [31:0]                 trans_addr_seen_q;
  logic                        trans_shared_seen_q;
  logic                        trans_dirty_seen_q;
  logic                        trans_need_mem_read_seen_q;
  logic                        trans_need_writeback_seen_q;

  logic [NUM_CORES-1:0]        ack_seen_q;
  logic [NUM_CORES-1:0][10:0]  ack_resp_tag_seen_q;
  logic [NUM_CORES-1:0][31:0]  ack_data_seen_q;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv_top_multi #(
	.NUM_CORES(NUM_CORES)
  ) dut (
	.clk_i(clk_i),
	.rst_i(rst_i),
	.rst_cpu_i(rst_cpu_i),

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

	.coh_req_ready_o(coh_req_ready_o),
	.coh_req_valid_dbg_o(coh_req_valid_dbg_o),
	.coh_req_cmd_dbg_o(coh_req_cmd_dbg_o),
	.coh_req_addr_dbg_o(coh_req_addr_dbg_o),

	.snoop_hit_o(snoop_hit_o),
	.snoop_dirty_o(snoop_dirty_o),
	.snoop_ack_o(snoop_ack_o),
	.cpu_id_o(cpu_id_o)
  );
  
  
  integer mon_i;
  always @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
	  trans_seen_q               <= 1'b0;
	  trans_core_seen_q          <= '0;
	  trans_cmd_seen_q           <= SNOOP_NONE;
	  trans_addr_seen_q          <= 32'h0;
	  trans_shared_seen_q        <= 1'b0;
	  trans_dirty_seen_q         <= 1'b0;
	  trans_need_mem_read_seen_q <= 1'b0;
	  trans_need_writeback_seen_q<= 1'b0;

	  ack_seen_q                 <= '0;
	  ack_resp_tag_seen_q        <= '0;
	  ack_data_seen_q            <= '0;
	end
	else begin
	  if (coh_trans_done_o) begin
		trans_seen_q                <= 1'b1;
		trans_core_seen_q           <= coh_trans_core_o;
		trans_cmd_seen_q            <= coh_trans_cmd_o;
		trans_addr_seen_q           <= coh_trans_addr_o;
		trans_shared_seen_q         <= coh_trans_shared_o;
		trans_dirty_seen_q          <= coh_trans_dirty_o;
		trans_need_mem_read_seen_q  <= coh_trans_need_mem_read_o;
		trans_need_writeback_seen_q <= coh_trans_need_writeback_o;
	  end

	  for (mon_i = 0; mon_i < NUM_CORES; mon_i = mon_i + 1) begin
		if (dut.dcache_ack_w[mon_i]) begin
		  ack_seen_q[mon_i]          <= 1'b1;
		  ack_resp_tag_seen_q[mon_i] <= dut.dcache_resp_tag_w[mon_i];
		  ack_data_seen_q[mon_i]     <= dut.dcache_data_rd_w[mon_i];
		end
	  end
	end
  end
  
  
  task automatic clear_trans_seen;
	  begin
		trans_seen_q                = 1'b0;
		trans_core_seen_q           = '0;
		trans_cmd_seen_q            = SNOOP_NONE;
		trans_addr_seen_q           = 32'h0;
		trans_shared_seen_q         = 1'b0;
		trans_dirty_seen_q          = 1'b0;
		trans_need_mem_read_seen_q  = 1'b0;
		trans_need_writeback_seen_q = 1'b0;
	  end
	endtask

	task automatic clear_ack_seen(input int core);
	  begin
		ack_seen_q[core]          = 1'b0;
		ack_resp_tag_seen_q[core] = '0;
		ack_data_seen_q[core]     = '0;
	  end
	endtask
	

  // ------------------------------------------------------------
  // Shared memory model
  // ------------------------------------------------------------
  logic [31:0] shared_mem [0:65535];

  logic [NUM_CORES-1:0]       rd_active_q;
  logic [NUM_CORES-1:0][31:0] rd_base_addr_q;
  integer                     rd_beat_q   [0:NUM_CORES-1];
  integer                     rd_delay_q  [0:NUM_CORES-1];
  
  logic [NUM_CORES-1:0]       rd_resp_pending_q;
  logic [NUM_CORES-1:0][31:0] rd_data_hold_q;
  logic [NUM_CORES-1:0][3:0]  rd_id_hold_q;
  logic [NUM_CORES-1:0]       rd_last_hold_q;

  logic [NUM_CORES-1:0]       wr_active_q;
  logic [NUM_CORES-1:0][31:0] wr_base_addr_q;
  integer                     wr_beat_q   [0:NUM_CORES-1];
  logic [NUM_CORES-1:0]       b_pending_q;
  integer                     b_delay_q   [0:NUM_CORES-1];

  task automatic mem_write_word(input [31:0] addr, input [31:0] data, input [3:0] strb);
	logic [31:0] tmp;
	begin
	  tmp = shared_mem[addr[17:2]];
	  if (strb[0]) tmp[7:0]   = data[7:0];
	  if (strb[1]) tmp[15:8]  = data[15:8];
	  if (strb[2]) tmp[23:16] = data[23:16];
	  if (strb[3]) tmp[31:24] = data[31:24];
	  shared_mem[addr[17:2]] = tmp;
	end
  endtask

  integer mc;
  always @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
	  axi_d_rvalid_i <= '0;
	  axi_d_rdata_i  <= '0;
	  axi_d_rresp_i  <= '0;
	  axi_d_rid_i    <= '0;
	  axi_d_rlast_i  <= '0;
	  axi_d_bvalid_i <= '0;
	  axi_d_bresp_i  <= '0;
	  axi_d_bid_i    <= '0;

	  rd_active_q    <= '0;
	  rd_base_addr_q <= '0;
	  wr_active_q    <= '0;
	  wr_base_addr_q <= '0;
	  b_pending_q    <= '0;
	  rd_resp_pending_q <= '0;
	  rd_data_hold_q    <= '0;
	  rd_id_hold_q      <= '0;
	  rd_last_hold_q    <= '0;

	  for (mc = 0; mc < NUM_CORES; mc++) begin
		rd_beat_q[mc]  = 0;
		rd_delay_q[mc] = 0;
		wr_beat_q[mc]  = 0;
		b_delay_q[mc]  = 0;
	  end
	end
	else begin
	  axi_d_rvalid_i <= '0;
	  axi_d_rlast_i  <= '0;
	  axi_d_bvalid_i <= '0;

	  for (mc = 0; mc < NUM_CORES; mc++) begin
		// Start read burst
		if (axi_d_arvalid_o[mc] && axi_d_arready_i[mc] && !rd_active_q[mc]) begin
		  rd_active_q[mc]    <= 1'b1;
		  rd_base_addr_q[mc] <= {axi_d_araddr_o[mc][31:5], 5'b0};
		  rd_beat_q[mc]      <= 0;
		  rd_delay_q[mc]     <= 1;
		end

		// Read response
		if (rd_active_q[mc]) begin
			if (rd_delay_q[mc] > 0) begin
			  rd_delay_q[mc] <= rd_delay_q[mc] - 1;
			end
			else if (!rd_resp_pending_q[mc]) begin
			  // Stage the read data one cycle before asserting rvalid
			  rd_resp_pending_q[mc] <= 1'b1;
			  rd_data_hold_q[mc]    <= shared_mem[(rd_base_addr_q[mc] >> 2) + rd_beat_q[mc]];
			  rd_id_hold_q[mc]      <= axi_d_arid_o[mc];
			  rd_last_hold_q[mc]    <= (rd_beat_q[mc] == 7);
			end
			else begin
			  axi_d_rvalid_i[mc] <= 1'b1;
			  axi_d_rdata_i[mc]  <= rd_data_hold_q[mc];
			  axi_d_rresp_i[mc]  <= 2'b00;
			  axi_d_rid_i[mc]    <= rd_id_hold_q[mc];
			  axi_d_rlast_i[mc]  <= rd_last_hold_q[mc];

			  rd_resp_pending_q[mc] <= 1'b0;

			  if (rd_last_hold_q[mc]) begin
				rd_active_q[mc] <= 1'b0;
				rd_beat_q[mc]   <= 0;
			  end
			  else begin
				rd_beat_q[mc]   <= rd_beat_q[mc] + 1;
			  end
			end
		  end

		// Start write burst address
		if (axi_d_awvalid_o[mc] && axi_d_awready_i[mc]) begin
		  wr_active_q[mc]    <= 1'b1;
		  wr_base_addr_q[mc] <= {axi_d_awaddr_o[mc][31:5], 5'b0};
		  wr_beat_q[mc]      <= 0;
		end

		// Write data beats
		if (axi_d_wvalid_o[mc] && axi_d_wready_i[mc]) begin
		  logic [31:0] cur_addr;
		  if (wr_active_q[mc])
			cur_addr = wr_base_addr_q[mc] + (wr_beat_q[mc] * 4);
		  else
			cur_addr = {axi_d_awaddr_o[mc][31:5], 5'b0};

		  mem_write_word(cur_addr, axi_d_wdata_o[mc], axi_d_wstrb_o[mc]);

		  if (axi_d_wlast_o[mc]) begin
			wr_active_q[mc] <= 1'b0;
			b_pending_q[mc] <= 1'b1;
			b_delay_q[mc]   <= 1;
			wr_beat_q[mc]   <= 0;
		  end
		  else begin
			wr_beat_q[mc]   <= wr_beat_q[mc] + 1;
		  end
		end

		// Write response
		if (b_pending_q[mc]) begin
		  if (b_delay_q[mc] > 0) begin
			b_delay_q[mc] <= b_delay_q[mc] - 1;
		  end
		  else begin
			axi_d_bvalid_i[mc] <= 1'b1;
			axi_d_bresp_i[mc]  <= 2'b00;
			axi_d_bid_i[mc]    <= axi_d_awid_o[mc];
			b_pending_q[mc]    <= 1'b0;
		  end
		end
	  end
	end
  end

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

  function automatic [10:0] data_word_index(input [31:0] addr);
	data_word_index = addr[12:2];
  endfunction

  task automatic clear_inputs;
	integer i;
	begin
	  rst_cpu_i      = '1; // hold CPUs in reset

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

	  intr_i         = '0;
	  reset_vector_i = '0;

	  for (i = 0; i < 65536; i++)
		shared_mem[i] = 32'h1000_0000 ^ (i * 32'h0101_0101);
	end
  endtask

  task automatic wait_all_dcache_lookup;
	  integer timeout;
	  bit all_lookup;
	  begin
		  timeout = 30000;
		  while (timeout > 0) begin
			  all_lookup =
				   (dut.gen_core[0].u_dcache.u_core.state_q == STATE_LOOKUP) &&
				   (dut.gen_core[1].u_dcache.u_core.state_q == STATE_LOOKUP) &&
				   (dut.gen_core[2].u_dcache.u_core.state_q == STATE_LOOKUP) &&
				   (dut.gen_core[3].u_dcache.u_core.state_q == STATE_LOOKUP) &&

				   !dut.gen_core[0].u_dcache.u_core.snoop_pending_q &&
				   !dut.gen_core[1].u_dcache.u_core.snoop_pending_q &&
				   !dut.gen_core[2].u_dcache.u_core.snoop_pending_q &&
				   !dut.gen_core[3].u_dcache.u_core.snoop_pending_q &&

				   !dut.gen_core[0].u_dcache.u_core.coh_req_valid_q &&
				   !dut.gen_core[1].u_dcache.u_core.coh_req_valid_q &&
				   !dut.gen_core[2].u_dcache.u_core.coh_req_valid_q &&
				   !dut.gen_core[3].u_dcache.u_core.coh_req_valid_q &&

				   !dut.gen_core[0].u_dcache.u_core.coh_wait_done_q &&
				   !dut.gen_core[1].u_dcache.u_core.coh_wait_done_q &&
				   !dut.gen_core[2].u_dcache.u_core.coh_wait_done_q &&
				   !dut.gen_core[3].u_dcache.u_core.coh_wait_done_q &&

				   !dut.dcache_ack_w[0] &&
				   !dut.dcache_ack_w[1] &&
				   !dut.dcache_ack_w[2] &&
				   !dut.dcache_ack_w[3] &&
				   !coh_trans_done_o;

			  if (all_lookup)
				  return;

			  @(posedge clk_i);
			  timeout = timeout - 1;
		  end

		  fail("timeout waiting for all dcache cores to become fully idle");
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

  task automatic program_word_way0(input int core, input [31:0] addr, input [31:0] data);
	int widx;
	begin
	  widx = data_word_index(addr);
	  case (core)
		0: dut.gen_core[0].u_dcache.u_core.u_data0.ram[widx] = data;
		1: dut.gen_core[1].u_dcache.u_core.u_data0.ram[widx] = data;
		2: dut.gen_core[2].u_dcache.u_core.u_data0.ram[widx] = data;
		3: dut.gen_core[3].u_dcache.u_core.u_data0.ram[widx] = data;
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

  // ------------------------------------------------------------
  // Force-driven CPU request injection into internal dcache wires
  // ------------------------------------------------------------
  task drive_req(
		  input int core,
		  input [31:0] addr,
		  input [31:0] data,
		  input logic rd,
		  input [3:0] wr,
		  input logic cacheable,
		  input [10:0] tag
		);
		begin
		  case (core)
			0: begin
			  force dut.dcache_addr_w[0]       = addr;
			  force dut.dcache_data_wr_w[0]    = data;
			  force dut.dcache_rd_w[0]         = rd;
			  force dut.dcache_wr_w[0]         = wr;
			  force dut.dcache_cacheable_w[0]  = cacheable;
			  force dut.dcache_req_tag_w[0]    = tag;
			  force dut.dcache_invalidate_w[0] = 1'b0;
			  force dut.dcache_writeback_w[0]  = 1'b0;
			  force dut.dcache_flush_w[0]      = 1'b0;
			end

			1: begin
			  force dut.dcache_addr_w[1]       = addr;
			  force dut.dcache_data_wr_w[1]    = data;
			  force dut.dcache_rd_w[1]         = rd;
			  force dut.dcache_wr_w[1]         = wr;
			  force dut.dcache_cacheable_w[1]  = cacheable;
			  force dut.dcache_req_tag_w[1]    = tag;
			  force dut.dcache_invalidate_w[1] = 1'b0;
			  force dut.dcache_writeback_w[1]  = 1'b0;
			  force dut.dcache_flush_w[1]      = 1'b0;
			end

			2: begin
			  force dut.dcache_addr_w[2]       = addr;
			  force dut.dcache_data_wr_w[2]    = data;
			  force dut.dcache_rd_w[2]         = rd;
			  force dut.dcache_wr_w[2]         = wr;
			  force dut.dcache_cacheable_w[2]  = cacheable;
			  force dut.dcache_req_tag_w[2]    = tag;
			  force dut.dcache_invalidate_w[2] = 1'b0;
			  force dut.dcache_writeback_w[2]  = 1'b0;
			  force dut.dcache_flush_w[2]      = 1'b0;
			end

			3: begin
			  force dut.dcache_addr_w[3]       = addr;
			  force dut.dcache_data_wr_w[3]    = data;
			  force dut.dcache_rd_w[3]         = rd;
			  force dut.dcache_wr_w[3]         = wr;
			  force dut.dcache_cacheable_w[3]  = cacheable;
			  force dut.dcache_req_tag_w[3]    = tag;
			  force dut.dcache_invalidate_w[3] = 1'b0;
			  force dut.dcache_writeback_w[3]  = 1'b0;
			  force dut.dcache_flush_w[3]      = 1'b0;
			end

			default: ;
		  endcase
		end
		endtask

		task release_req(input int core);
		begin
		  case (core)
			0: begin
			  release dut.dcache_addr_w[0];
			  release dut.dcache_data_wr_w[0];
			  release dut.dcache_rd_w[0];
			  release dut.dcache_wr_w[0];
			  release dut.dcache_cacheable_w[0];
			  release dut.dcache_req_tag_w[0];
			  release dut.dcache_invalidate_w[0];
			  release dut.dcache_writeback_w[0];
			  release dut.dcache_flush_w[0];
			end

			1: begin
			  release dut.dcache_addr_w[1];
			  release dut.dcache_data_wr_w[1];
			  release dut.dcache_rd_w[1];
			  release dut.dcache_wr_w[1];
			  release dut.dcache_cacheable_w[1];
			  release dut.dcache_req_tag_w[1];
			  release dut.dcache_invalidate_w[1];
			  release dut.dcache_writeback_w[1];
			  release dut.dcache_flush_w[1];
			end

			2: begin
			  release dut.dcache_addr_w[2];
			  release dut.dcache_data_wr_w[2];
			  release dut.dcache_rd_w[2];
			  release dut.dcache_wr_w[2];
			  release dut.dcache_cacheable_w[2];
			  release dut.dcache_req_tag_w[2];
			  release dut.dcache_invalidate_w[2];
			  release dut.dcache_writeback_w[2];
			  release dut.dcache_flush_w[2];
			end

			3: begin
			  release dut.dcache_addr_w[3];
			  release dut.dcache_data_wr_w[3];
			  release dut.dcache_rd_w[3];
			  release dut.dcache_wr_w[3];
			  release dut.dcache_cacheable_w[3];
			  release dut.dcache_req_tag_w[3];
			  release dut.dcache_invalidate_w[3];
			  release dut.dcache_writeback_w[3];
			  release dut.dcache_flush_w[3];
			end

			default: ;
		  endcase
		end
		endtask

  task automatic wait_accept(input int core);
	integer timeout;
	begin
	  timeout = 5000;
	  while (!dut.dcache_accept_w[core] && timeout > 0) begin
		@(posedge clk_i);
		timeout = timeout - 1;
	  end
	  if (timeout == 0)
		fail($sformatf("timeout waiting for dcache_accept_w core%0d", core));
	end
  endtask

  task automatic wait_ack(input int core);
	  integer timeout;
	  begin
		timeout = 30000;
		while (!ack_seen_q[core] && timeout > 0) begin
		  @(posedge clk_i);
		  timeout = timeout - 1;
		end
		if (timeout == 0)
		  fail($sformatf("timeout waiting for dcache_ack_w core%0d", core));
	  end
	endtask

	task automatic cpu_read_req(
			input int           core,
			input logic [31:0]  addr,
			input logic [10:0]  tag,
			output logic [31:0] data
		);
			integer timeout;
			begin
				wait_all_dcache_lookup();
				while (dut.coh_busy_o) @(posedge clk_i);

				clear_ack_seen(core);
				clear_trans_seen();

				@(posedge clk_i);
				drive_req(core, addr, 32'h0, 1'b1, 4'h0, 1'b1, tag);

				timeout = 100;
				while (!dut.coh_req_valid_dbg_o[core] && !ack_seen_q[core] && timeout > 0) begin
					@(posedge clk_i);
					timeout = timeout - 1;
				end

				if (timeout == 0)
					fail($sformatf("core%0d request did not reach coh_req_valid/ack", core));

				@(posedge clk_i);
				release_req(core);

				wait_ack(core);
				check_eq32($sformatf("core%0d read resp_tag", core), ack_resp_tag_seen_q[core], tag);
				data = ack_data_seen_q[core];

				wait_all_dcache_lookup();
				while (dut.coh_busy_o) @(posedge clk_i);
			end
		endtask

		task automatic cpu_write_req(
				input int           core,
				input logic [31:0]  addr,
				input logic [31:0]  data,
				input logic [3:0]   strb,
				input logic [10:0]  tag
			);
				integer timeout;
				begin
					wait_all_dcache_lookup();
					while (dut.coh_busy_o) @(posedge clk_i);

					clear_ack_seen(core);
					clear_trans_seen();

					@(posedge clk_i);
					drive_req(core, addr, data, 1'b0, strb, 1'b1, tag);

					timeout = 100;
					while (!dut.coh_req_valid_dbg_o[core] && !ack_seen_q[core] && timeout > 0) begin
						@(posedge clk_i);
						timeout = timeout - 1;
					end

					if (timeout == 0)
						fail($sformatf("core%0d request did not reach coh_req_valid/ack", core));

					@(posedge clk_i);
					release_req(core);

					wait_ack(core);
					check_eq32($sformatf("core%0d write resp_tag", core), ack_resp_tag_seen_q[core], tag);

					wait_all_dcache_lookup();
					while (dut.coh_busy_o) @(posedge clk_i);
				end
			endtask

  task automatic wait_trans_done;
	  integer timeout;
	  begin
		timeout = 20000;
		while (!trans_seen_q && timeout > 0) begin
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

			  check_eq32("coh_trans_addr_o", trans_addr_seen_q, addr);
			  check_eq_cmd("coh_trans_cmd_o", trans_cmd_seen_q, cmd);
			  check_eq32("coh_trans_core_o", trans_core_seen_q, src);
			  check_eq1 ("coh_trans_shared_o", trans_shared_seen_q, shared);
			  check_eq1 ("coh_trans_dirty_o", trans_dirty_seen_q, dirty);
			  check_eq1 ("coh_trans_need_mem_read_o", trans_need_mem_read_seen_q, need_mem_read);
			  check_eq1 ("coh_trans_need_writeback_o", trans_need_writeback_seen_q, need_wb);
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
		check_eq1($sformatf("coh_req_valid_dbg_o core%0d reset", c), coh_req_valid_dbg_o[c], 1'b0);
	  end
	end
  endtask

  task automatic test_read_miss_generates_busrd;
	logic [31:0] addr;
	logic [31:0] rd;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] read_miss_generates_busrd");

	  addr = 32'h8000_1000;
	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  cpu_read_req(1, addr, 11'h011, rd);
	  check_result(1, SNOOP_BUSRD, addr, 1'b0, 1'b0, 1'b1, 1'b0);

	  check_eq32("read miss refill data", rd, shared_mem[addr[17:2]]);
	  check_eq1("requester line becomes S", (line_state(1, addr) == MSI_S), 1'b1);
	end
  endtask

  task automatic test_write_miss_generates_busrdx;
	logic [31:0] addr;
	logic [31:0] rd;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] write_miss_generates_busrdx");

	  addr = 32'h8000_2000;
	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  program_line(0, addr, MSI_S);

	  cpu_write_req(2, addr, 32'hdeadbeef, 4'hF, 11'h021);
	  check_result(2, SNOOP_BUSRDX, addr, 1'b1, 1'b0, 1'b1, 1'b0);

	  check_eq1("core0 invalidated on BUSRDX", (line_state(0, addr) == MSI_I), 1'b1);
	  check_eq1("requester line becomes M",     (line_state(2, addr) == MSI_M), 1'b1);

	  cpu_read_req(2, addr, 11'h022, rd);
	  check_eq32("write miss readback", rd, 32'hdeadbeef);
	end
  endtask

  task automatic test_write_hit_shared_generates_busupgr;
	logic [31:0] addr;
	logic [31:0] rd;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] write_hit_shared_generates_busupgr");

	  addr = 32'h8000_3000;
	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  program_line(1, addr, MSI_S);
	  program_line(3, addr, MSI_S);
	  program_word_way0(1, addr, 32'h11112222);

	  cpu_write_req(1, addr, 32'hc001d00d, 4'hF, 11'h031);
	  check_result(1, SNOOP_BUSUPGR, addr, 1'b1, 1'b0, 1'b0, 1'b0);

	  check_eq1("requester line S->M after BUSUPGR", (line_state(1, addr) == MSI_M), 1'b1);
	  check_eq1("peer sharer invalidated",           (line_state(3, addr) == MSI_I), 1'b1);

	  cpu_read_req(1, addr, 11'h032, rd);
	  check_eq32("write hit shared readback", rd, 32'hc001d00d);
	end
  endtask

  task automatic test_busrd_from_modified_owner;
	logic [31:0] addr;
	logic [31:0] rd;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] busrd_from_modified_owner");

	  addr = 32'h8000_4000;
	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  program_line(0, addr, MSI_M);
	  program_word_way0(0, addr, 32'habcdef01);

	  cpu_read_req(1, addr, 11'h041, rd);
	  check_result(1, SNOOP_BUSRD, addr, 1'b1, 1'b1, 1'b0, 1'b1);

	  check_eq1("modified owner downgraded M->S", (line_state(0, addr) == MSI_S), 1'b1);
	  check_eq1("requester line becomes S",       (line_state(1, addr) == MSI_S), 1'b1);
	end
  endtask

  task automatic test_nohit_busrd;
	logic [31:0] addr;
	logic [31:0] rd;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] nohit_busrd");

	  addr = 32'h8000_5000;
	  clear_line(0, addr);
	  clear_line(1, addr);
	  clear_line(2, addr);
	  clear_line(3, addr);

	  cpu_read_req(3, addr, 11'h051, rd);
	  check_result(3, SNOOP_BUSRD, addr, 1'b0, 1'b0, 1'b1, 1'b0);
	  check_eq1("requester line becomes S", (line_state(3, addr) == MSI_S), 1'b1);
	end
  endtask
  


  task automatic test_random;
	int iter;
	int src;
	int c;
	logic [31:0] addr;
	logic [31:0] data;
	logic [31:0] rd;
	logic [1:0] preload_state [0:NUM_CORES-1];
	snoop_cmd_t exp_cmd;
	logic exp_shared;
	logic exp_dirty;
	logic exp_need_mem_read;
	logic exp_need_wb;
	int op;
	begin
	  test_count = test_count + 1;
	  $display("\n[TEST] random");

	  for (iter = 0; iter < 80; iter++) begin
		src  = $urandom_range(0, NUM_CORES-1);
		addr = 32'h8000_8000 + (iter * 32'h40);
		data = $urandom;
		op   = $urandom_range(0,2); // 0 read miss, 1 write miss, 2 write hit shared

		for (c = 0; c < NUM_CORES; c++) begin
		  clear_line(c, addr);
		  preload_state[c] = MSI_I;
		end

		case (op)
		  0: begin
			exp_cmd           = SNOOP_BUSRD;
			exp_shared        = 1'b0;
			exp_dirty         = 1'b0;
			exp_need_mem_read = 1'b1;
			exp_need_wb       = 1'b0;

			if ($urandom_range(0,1)) begin
			  c = (src + 1) % NUM_CORES;
			  program_line(c, addr, MSI_S);
			  preload_state[c] = MSI_S;
			  exp_shared = 1'b1;
			end

			if ($urandom_range(0,1)) begin
			  c = (src + 2) % NUM_CORES;
			  program_line(c, addr, MSI_M);
			  preload_state[c] = MSI_M;
			  exp_shared = 1'b1;
			  exp_dirty  = 1'b1;
			  exp_need_mem_read = 1'b0;
			  exp_need_wb = 1'b1;
			end

			cpu_read_req(src, addr, iter[10:0], rd);
		  end

		  1: begin
			exp_cmd           = SNOOP_BUSRDX;
			exp_shared        = 1'b0;
			exp_dirty         = 1'b0;
			exp_need_mem_read = 1'b1;
			exp_need_wb       = 1'b0;

			if ($urandom_range(0,1)) begin
			  c = (src + 1) % NUM_CORES;
			  program_line(c, addr, MSI_S);
			  preload_state[c] = MSI_S;
			  exp_shared = 1'b1;
			end

			if ($urandom_range(0,1)) begin
			  c = (src + 2) % NUM_CORES;
			  program_line(c, addr, MSI_M);
			  preload_state[c] = MSI_M;
			  exp_shared = 1'b1;
			  exp_dirty  = 1'b1;
			  exp_need_mem_read = 1'b0;
			  exp_need_wb = 1'b1;
			end

			cpu_write_req(src, addr, data, 4'hF, iter[10:0]);
		  end

		  default: begin
			exp_cmd           = SNOOP_BUSUPGR;
			exp_shared        = 1'b1;
			exp_dirty         = 1'b0;
			exp_need_mem_read = 1'b0;
			exp_need_wb       = 1'b0;

			program_line(src, addr, MSI_S);
			program_word_way0(src, addr, shared_mem[addr[17:2]]);

			c = (src + 1) % NUM_CORES;
			program_line(c, addr, MSI_S);
			preload_state[c] = MSI_S;

			cpu_write_req(src, addr, data, 4'hF, iter[10:0]);
		  end
		endcase

		check_result(src, exp_cmd, addr, exp_shared, exp_dirty, exp_need_mem_read, exp_need_wb);

		if (exp_cmd == SNOOP_BUSUPGR || exp_cmd == SNOOP_BUSRDX)
		  check_eq1($sformatf("rand requester core%0d becomes M", src), (line_state(src, addr) == MSI_M), 1'b1);
		else
		  check_eq1($sformatf("rand requester core%0d becomes S", src), (line_state(src, addr) == MSI_S), 1'b1);

		for (c = 0; c < NUM_CORES; c++) begin
		  if (c != src) begin
			case (exp_cmd)
			  SNOOP_BUSRD: begin
				if (preload_state[c] == MSI_M)
				  check_eq1($sformatf("rand core%0d M->S", c), (line_state(c, addr) == MSI_S), 1'b1);
				else if (preload_state[c] == MSI_S)
				  check_eq1($sformatf("rand core%0d S stays S", c), (line_state(c, addr) == MSI_S), 1'b1);
			  end

			  SNOOP_BUSRDX: begin
				if (preload_state[c] != MSI_I)
				  check_eq1($sformatf("rand core%0d -> I on BUSRDX", c), (line_state(c, addr) == MSI_I), 1'b1);
			  end

			  SNOOP_BUSUPGR: begin
				if (preload_state[c] == MSI_S)
				  check_eq1($sformatf("rand core%0d S->I on BUSUPGR", c), (line_state(c, addr) == MSI_I), 1'b1);
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
	  $fsdbDumpfile("tb_riscv_top_multi_coh_auto.fsdb");
	  $fsdbDumpvars(0, tb_riscv_top_multi_coh_auto);
	`else
	  $dumpfile("tb_riscv_top_multi_coh_auto.vcd");
	  $dumpvars(0, tb_riscv_top_multi_coh_auto);
	`endif

	repeat (10) @(posedge clk_i);
	rst_i = 1'b0;

	test_reset_idle();
	test_read_miss_generates_busrd();
	test_write_miss_generates_busrdx();
	test_write_hit_shared_generates_busupgr();
	test_busrd_from_modified_owner();
	test_nohit_busrd();
	test_random();

	$display("==================================================");
	$display("RISCV_TOP_MULTI_COH_AUTO TB SUMMARY");
	$display("  test_count = %0d", test_count);
	$display("  pass_count = %0d", pass_count);
	$display("  fail_count = %0d", fail_count);
	$display("  coverage   = %0.2f %%", cov.get_inst_coverage());
	$display("==================================================");

	if (fail_count == 0)
	  $display("TB PASSED");
	else
	  $display("TB FAILED");

	#50;
	$finish;
  end

endmodule