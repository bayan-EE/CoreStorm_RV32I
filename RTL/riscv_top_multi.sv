`timescale 1ns/1ps

//---------------------------------------------------------------------
// Module: riscv_top_multi
// Type  : Multi-core top-level RISC-V SoC wrapper
//
// Description:
// This module is a multi-core version of the single-core riscv_top.
// It replicates the following per core:
//
//   - riscv_core
//   - icache
//   - dcache
//
// Each core has:
//   - its own instruction AXI port
//   - its own data AXI port
//   - its own interrupt input
//   - its own reset vector
//
// Notes:
// - This is a structural wrapper.
// - It does not implement coherence or shared arbitration.
// - Every core is fully independent at this level.
// - CPU ID is generated internally as CORE_ID_BASE + core_index.
//
// Recommended use:
// - Private caches per core
// - Later, a shared memory / coherence layer can be added above this top
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
	parameter int NUM_RAS_ENTRIES_W             = 3
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
	output logic [NUM_CORES-1:0]                  axi_d_rready_o
);

	//-----------------------------------------------------------------
	// Internal interconnect arrays
	//-----------------------------------------------------------------

	// Instruction-side signals between each core and its icache
	logic [NUM_CORES-1:0]                  icache_valid_w;
	logic [NUM_CORES-1:0]                  icache_flush_w;
	logic [NUM_CORES-1:0]                  icache_invalidate_w;
	logic [NUM_CORES-1:0]                  icache_error_w;
	logic [NUM_CORES-1:0]                  icache_accept_w;
	logic [NUM_CORES-1:0][63:0]            icache_inst_w;
	logic [NUM_CORES-1:0][31:0]            icache_pc_w;
	logic [NUM_CORES-1:0]                  icache_rd_w;

	// Data-side signals between each core and its dcache
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

	// CPU ID per core
	logic [NUM_CORES-1:0][31:0]            cpu_id_w;

	genvar g;
	generate
		for (g = 0; g < NUM_CORES; g++) begin : gen_core

			//---------------------------------------------------------
			// Constant CPU ID assignment
			//---------------------------------------------------------
			assign cpu_id_w[g] = CORE_ID_BASE + g;

			//---------------------------------------------------------
			// Data Cache Instance
			//---------------------------------------------------------
			dcache
			#(
				.AXI_ID(DCACHE_AXI_ID_BASE + g)
			)
			u_dcache
			(
				.clk_i             (clk_i),
				.rst_i             (rst_i),

				.mem_addr_i        (dcache_addr_w[g]),
				.mem_data_wr_i     (dcache_data_wr_w[g]),
				.mem_rd_i          (dcache_rd_w[g]),
				.mem_wr_i          (dcache_wr_w[g]),
				.mem_cacheable_i   (dcache_cacheable_w[g]),
				.mem_req_tag_i     (dcache_req_tag_w[g]),
				.mem_invalidate_i  (dcache_invalidate_w[g]),
				.mem_writeback_i   (dcache_writeback_w[g]),
				.mem_flush_i       (dcache_flush_w[g]),

				.axi_awready_i     (axi_d_awready_i[g]),
				.axi_wready_i      (axi_d_wready_i[g]),
				.axi_bvalid_i      (axi_d_bvalid_i[g]),
				.axi_bresp_i       (axi_d_bresp_i[g]),
				.axi_bid_i         (axi_d_bid_i[g]),
				.axi_arready_i     (axi_d_arready_i[g]),
				.axi_rvalid_i      (axi_d_rvalid_i[g]),
				.axi_rdata_i       (axi_d_rdata_i[g]),
				.axi_rresp_i       (axi_d_rresp_i[g]),
				.axi_rid_i         (axi_d_rid_i[g]),
				.axi_rlast_i       (axi_d_rlast_i[g]),

				.mem_data_rd_o     (dcache_data_rd_w[g]),
				.mem_accept_o      (dcache_accept_w[g]),
				.mem_ack_o         (dcache_ack_w[g]),
				.mem_error_o       (dcache_error_w[g]),
				.mem_resp_tag_o    (dcache_resp_tag_w[g]),

				.axi_awvalid_o     (axi_d_awvalid_o[g]),
				.axi_awaddr_o      (axi_d_awaddr_o[g]),
				.axi_awid_o        (axi_d_awid_o[g]),
				.axi_awlen_o       (axi_d_awlen_o[g]),
				.axi_awburst_o     (axi_d_awburst_o[g]),
				.axi_wvalid_o      (axi_d_wvalid_o[g]),
				.axi_wdata_o       (axi_d_wdata_o[g]),
				.axi_wstrb_o       (axi_d_wstrb_o[g]),
				.axi_wlast_o       (axi_d_wlast_o[g]),
				.axi_bready_o      (axi_d_bready_o[g]),
				.axi_arvalid_o     (axi_d_arvalid_o[g]),
				.axi_araddr_o      (axi_d_araddr_o[g]),
				.axi_arid_o        (axi_d_arid_o[g]),
				.axi_arlen_o       (axi_d_arlen_o[g]),
				.axi_arburst_o     (axi_d_arburst_o[g]),
				.axi_rready_o      (axi_d_rready_o[g])
			);

			//---------------------------------------------------------
			// RISC-V Core Instance
			//---------------------------------------------------------
			riscv_core
			#(
				.MEM_CACHE_ADDR_MIN       (MEM_CACHE_ADDR_MIN),
				.MEM_CACHE_ADDR_MAX       (MEM_CACHE_ADDR_MAX),
				.SUPPORT_BRANCH_PREDICTION(SUPPORT_BRANCH_PREDICTION),
				.SUPPORT_MULDIV           (SUPPORT_MULDIV),
				.SUPPORT_SUPER            (SUPPORT_SUPER),
				.SUPPORT_MMU              (SUPPORT_MMU),
				.SUPPORT_DUAL_ISSUE       (SUPPORT_DUAL_ISSUE),
				.SUPPORT_LOAD_BYPASS      (SUPPORT_LOAD_BYPASS),
				.SUPPORT_MUL_BYPASS       (SUPPORT_MUL_BYPASS),
				.SUPPORT_REGFILE_XILINX   (SUPPORT_REGFILE_XILINX),
				.EXTRA_DECODE_STAGE       (EXTRA_DECODE_STAGE),
				.NUM_BTB_ENTRIES          (NUM_BTB_ENTRIES),
				.NUM_BTB_ENTRIES_W        (NUM_BTB_ENTRIES_W),
				.NUM_BHT_ENTRIES          (NUM_BHT_ENTRIES),
				.NUM_BHT_ENTRIES_W        (NUM_BHT_ENTRIES_W),
				.RAS_ENABLE               (RAS_ENABLE),
				.GSHARE_ENABLE            (GSHARE_ENABLE),
				.BHT_ENABLE               (BHT_ENABLE),
				.NUM_RAS_ENTRIES          (NUM_RAS_ENTRIES),
				.NUM_RAS_ENTRIES_W        (NUM_RAS_ENTRIES_W)
			)
			u_core
			(
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
			// Instruction Cache Instance
			//---------------------------------------------------------
			icache
			#(
				.AXI_ID(ICACHE_AXI_ID_BASE + g)
			)
			u_icache
			(
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

endmodule