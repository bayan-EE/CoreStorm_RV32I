`timescale 1ns/1ps

import coherence_pkg::*;

//---------------------------------------------------------------------
// Module: riscv_top_multi
//
// Description:
// Multi-core top-level wrapper with:
// - One riscv_core per core
// - One icache per core
// - One dcache per core
// - One shared coherence_controller
//
// Notes:
// - Coherence requests are generated internally by each dcache.
// - The coherence controller broadcasts snoops to all dcache instances.
//---------------------------------------------------------------------
module riscv_top_multi
#(
	parameter int NUM_CORES                     = 4,
	parameter int CORE_ID_BASE                  = 0,
	parameter int ICACHE_AXI_ID_BASE            = 0,
	parameter int DCACHE_AXI_ID_BASE            = 0,
	parameter int SUPPORT_BRANCH_PREDICTION     = 1,
	parameter int SUPPORT_MULDIV                = 1,
	parameter int SUPPORT_SUPER                 = 0,
	parameter int SUPPORT_MMU                   = 0,
	parameter int SUPPORT_DUAL_ISSUE            = 1,
	parameter int SUPPORT_LOAD_BYPASS           = 1,
	parameter int SUPPORT_MUL_BYPASS            = 1,
	parameter int SUPPORT_REGFILE_XILINX        = 0,
	parameter int EXTRA_DECODE_STAGE            = 0,
	parameter logic [31:0] MEM_CACHE_ADDR_MIN   = 32'h8000_0000,
	parameter logic [31:0] MEM_CACHE_ADDR_MAX   = 32'h8fff_ffff,
	parameter int NUM_BTB_ENTRIES               = 32,
	parameter int NUM_BTB_ENTRIES_W             = 5,
	parameter int NUM_BHT_ENTRIES               = 512,
	parameter int NUM_BHT_ENTRIES_W             = 9,
	parameter int RAS_ENABLE                    = 1,
	parameter int GSHARE_ENABLE                 = 0,
	parameter int BHT_ENABLE                    = 1,
	parameter int NUM_RAS_ENTRIES               = 8,
	parameter int NUM_RAS_ENTRIES_W             = 3,
	parameter int CORE_IDX_W                    = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES)
)
(
	//-----------------------------------------------------------------
	// Clock / Reset
	//-----------------------------------------------------------------
	input  logic                                  clk_i,
	input  logic                                  rst_i,
	input  logic [NUM_CORES-1:0]                  rst_cpu_i,

	//-----------------------------------------------------------------
	// AXI Instruction Interface Inputs - one port per core
	//-----------------------------------------------------------------
	input  logic [NUM_CORES-1:0]                  axi_i_awready_i,
	input  logic [NUM_CORES-1:0]                  axi_i_wready_i,
	input  logic [NUM_CORES-1:0]                  axi_i_bvalid_i,
	input  logic [NUM_CORES-1:0][1:0]             axi_i_bresp_i,
	input  logic [NUM_CORES-1:0][3:0]             axi_i_bid_i,
	input  logic [NUM_CORES-1:0]                  axi_i_arready_i,
	input  logic [NUM_CORES-1:0]                  axi_i_rvalid_i,
	input  logic [NUM_CORES-1:0][31:0]            axi_i_rdata_i,
	input  logic [NUM_CORES-1:0][1:0]             axi_i_rresp_i,
	input  logic [NUM_CORES-1:0][3:0]             axi_i_rid_i,
	input  logic [NUM_CORES-1:0]                  axi_i_rlast_i,

	//-----------------------------------------------------------------
	// AXI Data Interface Inputs - one port per core
	//-----------------------------------------------------------------
	input  logic [NUM_CORES-1:0]                  axi_d_awready_i,
	input  logic [NUM_CORES-1:0]                  axi_d_wready_i,
	input  logic [NUM_CORES-1:0]                  axi_d_bvalid_i,
	input  logic [NUM_CORES-1:0][1:0]             axi_d_bresp_i,
	input  logic [NUM_CORES-1:0][3:0]             axi_d_bid_i,
	input  logic [NUM_CORES-1:0]                  axi_d_arready_i,
	input  logic [NUM_CORES-1:0]                  axi_d_rvalid_i,
	input  logic [NUM_CORES-1:0][31:0]            axi_d_rdata_i,
	input  logic [NUM_CORES-1:0][1:0]             axi_d_rresp_i,
	input  logic [NUM_CORES-1:0][3:0]             axi_d_rid_i,
	input  logic [NUM_CORES-1:0]                  axi_d_rlast_i,

	//-----------------------------------------------------------------
	// Misc Inputs - one per core
	//-----------------------------------------------------------------
	input  logic [NUM_CORES-1:0]                  intr_i,
	input  logic [NUM_CORES-1:0][31:0]            reset_vector_i,

	//-----------------------------------------------------------------
	// AXI Instruction Interface Outputs - one port per core
	//-----------------------------------------------------------------
	output logic [NUM_CORES-1:0]                  axi_i_awvalid_o,
	output logic [NUM_CORES-1:0][31:0]            axi_i_awaddr_o,
	output logic [NUM_CORES-1:0][3:0]             axi_i_awid_o,
	output logic [NUM_CORES-1:0][7:0]             axi_i_awlen_o,
	output logic [NUM_CORES-1:0][1:0]             axi_i_awburst_o,
	output logic [NUM_CORES-1:0]                  axi_i_wvalid_o,
	output logic [NUM_CORES-1:0][31:0]            axi_i_wdata_o,
	output logic [NUM_CORES-1:0][3:0]             axi_i_wstrb_o,
	output logic [NUM_CORES-1:0]                  axi_i_wlast_o,
	output logic [NUM_CORES-1:0]                  axi_i_bready_o,
	output logic [NUM_CORES-1:0]                  axi_i_arvalid_o,
	output logic [NUM_CORES-1:0][31:0]            axi_i_araddr_o,
	output logic [NUM_CORES-1:0][3:0]             axi_i_arid_o,
	output logic [NUM_CORES-1:0][7:0]             axi_i_arlen_o,
	output logic [NUM_CORES-1:0][1:0]             axi_i_arburst_o,
	output logic [NUM_CORES-1:0]                  axi_i_rready_o,

	//-----------------------------------------------------------------
	// AXI Data Interface Outputs - one port per core
	//-----------------------------------------------------------------
	output logic [NUM_CORES-1:0]                  axi_d_awvalid_o,
	output logic [NUM_CORES-1:0][31:0]            axi_d_awaddr_o,
	output logic [NUM_CORES-1:0][3:0]             axi_d_awid_o,
	output logic [NUM_CORES-1:0][7:0]             axi_d_awlen_o,
	output logic [NUM_CORES-1:0][1:0]             axi_d_awburst_o,
	output logic [NUM_CORES-1:0]                  axi_d_wvalid_o,
	output logic [NUM_CORES-1:0][31:0]            axi_d_wdata_o,
	output logic [NUM_CORES-1:0][3:0]             axi_d_wstrb_o,
	output logic [NUM_CORES-1:0]                  axi_d_wlast_o,
	output logic [NUM_CORES-1:0]                  axi_d_bready_o,
	output logic [NUM_CORES-1:0]                  axi_d_arvalid_o,
	output logic [NUM_CORES-1:0][31:0]            axi_d_araddr_o,
	output logic [NUM_CORES-1:0][3:0]             axi_d_arid_o,
	output logic [NUM_CORES-1:0][7:0]             axi_d_arlen_o,
	output logic [NUM_CORES-1:0][1:0]             axi_d_arburst_o,
	output logic [NUM_CORES-1:0]                  axi_d_rready_o,

	//-----------------------------------------------------------------
	// Coherence controller transaction result outputs
	//-----------------------------------------------------------------
	output logic                                  coh_trans_done_o,
	output logic [CORE_IDX_W-1:0]                 coh_trans_core_o,
	output snoop_cmd_t                            coh_trans_cmd_o,
	output logic [31:0]                           coh_trans_addr_o,
	output logic                                  coh_trans_shared_o,
	output logic                                  coh_trans_dirty_o,
	output logic                                  coh_trans_need_mem_read_o,
	output logic                                  coh_trans_need_writeback_o,
	output logic                                  coh_busy_o,

	//-----------------------------------------------------------------
	// Optional coherence debug visibility
	//-----------------------------------------------------------------
	output logic [NUM_CORES-1:0]                  coh_req_ready_o,
	output logic [NUM_CORES-1:0]                  coh_req_valid_dbg_o,
	output logic [NUM_CORES-1:0][1:0]             coh_req_cmd_dbg_o,
	output logic [NUM_CORES-1:0][31:0]            coh_req_addr_dbg_o,

	//-----------------------------------------------------------------
	// Snoop response debug visibility
	//-----------------------------------------------------------------
	output logic [NUM_CORES-1:0]                  snoop_hit_o,
	output logic [NUM_CORES-1:0]                  snoop_dirty_o,
	output logic [NUM_CORES-1:0]                  snoop_ack_o,

	//-----------------------------------------------------------------
	// Optional debug visibility
	//-----------------------------------------------------------------
	output logic [NUM_CORES-1:0][31:0]            cpu_id_o
);

	//-----------------------------------------------------------------
	// Internal signals
	//-----------------------------------------------------------------

	// I-cache side
	logic [NUM_CORES-1:0]                  icache_valid_w;
	logic [NUM_CORES-1:0]                  icache_flush_w;
	logic [NUM_CORES-1:0]                  icache_invalidate_w;
	logic [NUM_CORES-1:0]                  icache_error_w;
	logic [NUM_CORES-1:0]                  icache_accept_w;
	logic [NUM_CORES-1:0][63:0]            icache_inst_w;
	logic [NUM_CORES-1:0][31:0]            icache_pc_w;
	logic [NUM_CORES-1:0]                  icache_rd_w;

	// D-cache side
	logic [NUM_CORES-1:0]                  dcache_flush_w;
	logic [NUM_CORES-1:0]                  dcache_invalidate_w;
	logic [NUM_CORES-1:0]                  dcache_writeback_w;
	logic [NUM_CORES-1:0]                  dcache_ack_w;
	logic [NUM_CORES-1:0]                  dcache_rd_w;
	logic [NUM_CORES-1:0]                  dcache_accept_w;
	logic [NUM_CORES-1:0]                  dcache_cacheable_w;
	logic [NUM_CORES-1:0]                  dcache_error_w;
	logic [NUM_CORES-1:0][10:0]            dcache_resp_tag_w;
	logic [NUM_CORES-1:0][10:0]            dcache_req_tag_w;
	logic [NUM_CORES-1:0][31:0]            dcache_addr_w;
	logic [NUM_CORES-1:0][31:0]            dcache_data_rd_w;
	logic [NUM_CORES-1:0][31:0]            dcache_data_wr_w;
	logic [NUM_CORES-1:0][3:0]             dcache_wr_w;

	// D-cache snoop response signals
	logic [NUM_CORES-1:0]                  dcache_snoop_hit_w;
	logic [NUM_CORES-1:0]                  dcache_snoop_dirty_w;
	logic [NUM_CORES-1:0]                  dcache_snoop_ack_w;

	// Controller -> caches snoop signals
	logic [NUM_CORES-1:0]                  ctrl_snoop_valid_w;
	snoop_cmd_t [NUM_CORES-1:0]            ctrl_snoop_cmd_w;
	logic [NUM_CORES-1:0][31:0]            ctrl_snoop_addr_w;

	// Internal coherence request signals from each dcache
	logic [NUM_CORES-1:0]                  dcache_coh_req_valid_w;
	logic [NUM_CORES-1:0][1:0]             dcache_coh_req_cmd_w;
	logic [NUM_CORES-1:0][31:0]            dcache_coh_req_addr_w;
	snoop_cmd_t [NUM_CORES-1:0]            dcache_coh_req_cmd_enum_w;
	logic [NUM_CORES-1:0]                  dcache_coh_trans_done_w;

	// Controller ready signals
	logic [NUM_CORES-1:0]                  coh_req_ready_w;

	// CPU IDs
	logic [NUM_CORES-1:0][31:0]            cpu_id_w;

	//-----------------------------------------------------------------
	// Top-level debug/monitor outputs
	//-----------------------------------------------------------------
	assign snoop_hit_o         = dcache_snoop_hit_w;
	assign snoop_dirty_o       = dcache_snoop_dirty_w;
	assign snoop_ack_o         = dcache_snoop_ack_w;
	assign cpu_id_o            = cpu_id_w;

	assign coh_req_ready_o     = coh_req_ready_w;
	assign coh_req_valid_dbg_o = dcache_coh_req_valid_w;
	assign coh_req_cmd_dbg_o   = dcache_coh_req_cmd_w;
	assign coh_req_addr_dbg_o  = dcache_coh_req_addr_w;

	//-----------------------------------------------------------------
	// Per-core constant helper connections
	//-----------------------------------------------------------------
	genvar g;
	generate
		for (g = 0; g < NUM_CORES; g++) begin : gen_core
			assign cpu_id_w[g]                = CORE_ID_BASE + g;
			assign dcache_coh_req_cmd_enum_w[g] = snoop_cmd_t'(dcache_coh_req_cmd_w[g]);
			assign dcache_coh_trans_done_w[g] = coh_trans_done_o &&
												(coh_trans_core_o == g[CORE_IDX_W-1:0]);

			//---------------------------------------------------------
			// D-cache
			//---------------------------------------------------------
			dcache #(
				.AXI_ID(DCACHE_AXI_ID_BASE + g)
			) u_dcache (
				.clk_i              (clk_i),
				.rst_i              (rst_i),

				.mem_addr_i         (dcache_addr_w[g]),
				.mem_data_wr_i      (dcache_data_wr_w[g]),
				.mem_rd_i           (dcache_rd_w[g]),
				.mem_wr_i           (dcache_wr_w[g]),
				.mem_cacheable_i    (dcache_cacheable_w[g]),
				.mem_req_tag_i      (dcache_req_tag_w[g]),
				.mem_invalidate_i   (dcache_invalidate_w[g]),
				.mem_writeback_i    (dcache_writeback_w[g]),
				.mem_flush_i        (dcache_flush_w[g]),

				.snoop_valid_i      (ctrl_snoop_valid_w[g]),
				.snoop_cmd_i        (ctrl_snoop_cmd_w[g]),
				.snoop_addr_i       (ctrl_snoop_addr_w[g]),

				.coh_req_ready_i    (coh_req_ready_w[g]),
				.coh_trans_done_i   (dcache_coh_trans_done_w[g]),
				.coh_trans_shared_i (coh_trans_shared_o),
				.coh_trans_dirty_i  (coh_trans_dirty_o),
				.coh_req_valid_o    (dcache_coh_req_valid_w[g]),
				.coh_req_cmd_o      (dcache_coh_req_cmd_w[g]),
				.coh_req_addr_o     (dcache_coh_req_addr_w[g]),

				.axi_awready_i      (axi_d_awready_i[g]),
				.axi_wready_i       (axi_d_wready_i[g]),
				.axi_bvalid_i       (axi_d_bvalid_i[g]),
				.axi_bresp_i        (axi_d_bresp_i[g]),
				.axi_bid_i          (axi_d_bid_i[g]),
				.axi_arready_i      (axi_d_arready_i[g]),
				.axi_rvalid_i       (axi_d_rvalid_i[g]),
				.axi_rdata_i        (axi_d_rdata_i[g]),
				.axi_rresp_i        (axi_d_rresp_i[g]),
				.axi_rid_i          (axi_d_rid_i[g]),
				.axi_rlast_i        (axi_d_rlast_i[g]),

				.mem_data_rd_o      (dcache_data_rd_w[g]),
				.mem_accept_o       (dcache_accept_w[g]),
				.mem_ack_o          (dcache_ack_w[g]),
				.mem_error_o        (dcache_error_w[g]),
				.mem_resp_tag_o     (dcache_resp_tag_w[g]),

				.snoop_hit_o        (dcache_snoop_hit_w[g]),
				.snoop_dirty_o      (dcache_snoop_dirty_w[g]),
				.snoop_ack_o        (dcache_snoop_ack_w[g]),

				.axi_awvalid_o      (axi_d_awvalid_o[g]),
				.axi_awaddr_o       (axi_d_awaddr_o[g]),
				.axi_awid_o         (axi_d_awid_o[g]),
				.axi_awlen_o        (axi_d_awlen_o[g]),
				.axi_awburst_o      (axi_d_awburst_o[g]),
				.axi_wvalid_o       (axi_d_wvalid_o[g]),
				.axi_wdata_o        (axi_d_wdata_o[g]),
				.axi_wstrb_o        (axi_d_wstrb_o[g]),
				.axi_wlast_o        (axi_d_wlast_o[g]),
				.axi_bready_o       (axi_d_bready_o[g]),
				.axi_arvalid_o      (axi_d_arvalid_o[g]),
				.axi_araddr_o       (axi_d_araddr_o[g]),
				.axi_arid_o         (axi_d_arid_o[g]),
				.axi_arlen_o        (axi_d_arlen_o[g]),
				.axi_arburst_o      (axi_d_arburst_o[g]),
				.axi_rready_o       (axi_d_rready_o[g])
			);

			//---------------------------------------------------------
			// Core
			//---------------------------------------------------------
			riscv_core #(
				.MEM_CACHE_ADDR_MIN        (MEM_CACHE_ADDR_MIN),
				.MEM_CACHE_ADDR_MAX        (MEM_CACHE_ADDR_MAX),
				.SUPPORT_BRANCH_PREDICTION (SUPPORT_BRANCH_PREDICTION),
				.SUPPORT_MULDIV            (SUPPORT_MULDIV),
				.SUPPORT_SUPER             (SUPPORT_SUPER),
				.SUPPORT_MMU               (SUPPORT_MMU),
				.SUPPORT_DUAL_ISSUE        (SUPPORT_DUAL_ISSUE),
				.SUPPORT_LOAD_BYPASS       (SUPPORT_LOAD_BYPASS),
				.SUPPORT_MUL_BYPASS        (SUPPORT_MUL_BYPASS),
				.SUPPORT_REGFILE_XILINX    (SUPPORT_REGFILE_XILINX),
				.EXTRA_DECODE_STAGE        (EXTRA_DECODE_STAGE),
				.NUM_BTB_ENTRIES           (NUM_BTB_ENTRIES),
				.NUM_BTB_ENTRIES_W         (NUM_BTB_ENTRIES_W),
				.NUM_BHT_ENTRIES           (NUM_BHT_ENTRIES),
				.NUM_BHT_ENTRIES_W         (NUM_BHT_ENTRIES_W),
				.RAS_ENABLE                (RAS_ENABLE),
				.GSHARE_ENABLE             (GSHARE_ENABLE),
				.BHT_ENABLE                (BHT_ENABLE),
				.NUM_RAS_ENTRIES           (NUM_RAS_ENTRIES),
				.NUM_RAS_ENTRIES_W         (NUM_RAS_ENTRIES_W)
			) u_core (
				.clk_i              (clk_i),
				.rst_i              (rst_cpu_i[g]),

				.mem_d_data_rd_i    (dcache_data_rd_w[g]),
				.mem_d_accept_i     (dcache_accept_w[g]),
				.mem_d_ack_i        (dcache_ack_w[g]),
				.mem_d_error_i      (dcache_error_w[g]),
				.mem_d_resp_tag_i   (dcache_resp_tag_w[g]),

				.mem_i_accept_i     (icache_accept_w[g]),
				.mem_i_valid_i      (icache_valid_w[g]),
				.mem_i_error_i      (icache_error_w[g]),
				.mem_i_inst_i       (icache_inst_w[g]),

				.intr_i             (intr_i[g]),
				.reset_vector_i     (reset_vector_i[g]),
				.cpu_id_i           (cpu_id_w[g]),

				.mem_d_addr_o       (dcache_addr_w[g]),
				.mem_d_data_wr_o    (dcache_data_wr_w[g]),
				.mem_d_rd_o         (dcache_rd_w[g]),
				.mem_d_wr_o         (dcache_wr_w[g]),
				.mem_d_cacheable_o  (dcache_cacheable_w[g]),
				.mem_d_req_tag_o    (dcache_req_tag_w[g]),
				.mem_d_invalidate_o (dcache_invalidate_w[g]),
				.mem_d_writeback_o  (dcache_writeback_w[g]),
				.mem_d_flush_o      (dcache_flush_w[g]),

				.mem_i_rd_o         (icache_rd_w[g]),
				.mem_i_flush_o      (icache_flush_w[g]),
				.mem_i_invalidate_o (icache_invalidate_w[g]),
				.mem_i_pc_o         (icache_pc_w[g])
			);

			//---------------------------------------------------------
			// I-cache
			//---------------------------------------------------------
			icache #(
				.AXI_ID(ICACHE_AXI_ID_BASE + g)
			) u_icache (
				.clk_i             (clk_i),
				.rst_i             (rst_i),

				.req_rd_i          (icache_rd_w[g]),
				.req_flush_i       (icache_flush_w[g]),
				.req_invalidate_i  (icache_invalidate_w[g]),
				.req_pc_i          (icache_pc_w[g]),

				.axi_awready_i     (axi_i_awready_i[g]),
				.axi_wready_i      (axi_i_wready_i[g]),
				.axi_bvalid_i      (axi_i_bvalid_i[g]),
				.axi_bresp_i       (axi_i_bresp_i[g]),
				.axi_bid_i         (axi_i_bid_i[g]),
				.axi_arready_i     (axi_i_arready_i[g]),
				.axi_rvalid_i      (axi_i_rvalid_i[g]),
				.axi_rdata_i       (axi_i_rdata_i[g]),
				.axi_rresp_i       (axi_i_rresp_i[g]),
				.axi_rid_i         (axi_i_rid_i[g]),
				.axi_rlast_i       (axi_i_rlast_i[g]),

				.req_accept_o      (icache_accept_w[g]),
				.req_valid_o       (icache_valid_w[g]),
				.req_error_o       (icache_error_w[g]),
				.req_inst_o        (icache_inst_w[g]),

				.axi_awvalid_o     (axi_i_awvalid_o[g]),
				.axi_awaddr_o      (axi_i_awaddr_o[g]),
				.axi_awid_o        (axi_i_awid_o[g]),
				.axi_awlen_o       (axi_i_awlen_o[g]),
				.axi_awburst_o     (axi_i_awburst_o[g]),
				.axi_wvalid_o      (axi_i_wvalid_o[g]),
				.axi_wdata_o       (axi_i_wdata_o[g]),
				.axi_wstrb_o       (axi_i_wstrb_o[g]),
				.axi_wlast_o       (axi_i_wlast_o[g]),
				.axi_bready_o      (axi_i_bready_o[g]),
				.axi_arvalid_o     (axi_i_arvalid_o[g]),
				.axi_araddr_o      (axi_i_araddr_o[g]),
				.axi_arid_o        (axi_i_arid_o[g]),
				.axi_arlen_o       (axi_i_arlen_o[g]),
				.axi_arburst_o     (axi_i_arburst_o[g]),
				.axi_rready_o      (axi_i_rready_o[g])
			);
		end
	endgenerate

	//-----------------------------------------------------------------
	// Coherence controller
	//-----------------------------------------------------------------
	coherence_controller #(
		.NUM_CORES(NUM_CORES)
	) u_coherence_controller (
		.clk_i                   (clk_i),
		.rst_i                   (rst_i),

		.coh_req_valid_i         (dcache_coh_req_valid_w),
		.coh_req_cmd_i           (dcache_coh_req_cmd_enum_w),
		.coh_req_addr_i          (dcache_coh_req_addr_w),
		.coh_req_ready_o         (coh_req_ready_w),

		.cache_snoop_hit_i       (dcache_snoop_hit_w),
		.cache_snoop_dirty_i     (dcache_snoop_dirty_w),
		.cache_snoop_ack_i       (dcache_snoop_ack_w),

		.snoop_valid_o           (ctrl_snoop_valid_w),
		.snoop_cmd_o             (ctrl_snoop_cmd_w),
		.snoop_addr_o            (ctrl_snoop_addr_w),

		.trans_done_o            (coh_trans_done_o),
		.trans_core_o            (coh_trans_core_o),
		.trans_cmd_o             (coh_trans_cmd_o),
		.trans_addr_o            (coh_trans_addr_o),
		.trans_shared_o          (coh_trans_shared_o),
		.trans_dirty_o           (coh_trans_dirty_o),
		.trans_need_mem_read_o   (coh_trans_need_mem_read_o),
		.trans_need_writeback_o  (coh_trans_need_writeback_o),
		.busy_o                  (coh_busy_o)
	);

endmodule