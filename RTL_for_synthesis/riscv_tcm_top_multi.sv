`timescale 1ns/1ps

module riscv_tcm_top_multi
#(
	 parameter int unsigned NUM_CORES                = 4,
	 parameter logic [31:0] BOOT_VECTOR             = 32'h00000000,
	 parameter int unsigned CORE_ID_BASE            = 0,
	 parameter logic [31:0] TCM_MEM_BASE            = 32'h00000000,
	 parameter bit SUPPORT_BRANCH_PREDICTION        = 1,
	 parameter bit SUPPORT_MULDIV                   = 1,
	 parameter bit SUPPORT_SUPER                    = 0,
	 parameter bit SUPPORT_MMU                      = 0,
	 parameter bit SUPPORT_DUAL_ISSUE               = 1,
	 parameter bit SUPPORT_LOAD_BYPASS              = 1,
	 parameter bit SUPPORT_MUL_BYPASS               = 1,
	 parameter bit SUPPORT_REGFILE_XILINX           = 0,
	 parameter bit EXTRA_DECODE_STAGE               = 0,
	 parameter logic [31:0] MEM_CACHE_ADDR_MIN      = 32'h80000000,
	 parameter logic [31:0] MEM_CACHE_ADDR_MAX      = 32'h8fffffff,
	 parameter int unsigned NUM_BTB_ENTRIES         = 32,
	 parameter int unsigned NUM_BTB_ENTRIES_W       = 5,
	 parameter int unsigned NUM_BHT_ENTRIES         = 512,
	 parameter int unsigned NUM_BHT_ENTRIES_W       = 9,
	 parameter bit RAS_ENABLE                       = 1,
	 parameter bit GSHARE_ENABLE                    = 0,
	 parameter bit BHT_ENABLE                       = 1,
	 parameter int unsigned NUM_RAS_ENTRIES         = 8,
	 parameter int unsigned NUM_RAS_ENTRIES_W       = 3
)
(
	input  logic                                   clk_i,
	input  logic                                   rst_i,
	input  logic [NUM_CORES-1:0]                   rst_cpu_i,

	//=============================================================
	// External AXI initiator side - one port per core
	//=============================================================
	input  logic [NUM_CORES-1:0]                   axi_i_awready_i,
	input  logic [NUM_CORES-1:0]                   axi_i_wready_i,
	input  logic [NUM_CORES-1:0]                   axi_i_bvalid_i,
	input  logic [NUM_CORES-1:0][1:0]              axi_i_bresp_i,
	input  logic [NUM_CORES-1:0]                   axi_i_arready_i,
	input  logic [NUM_CORES-1:0]                   axi_i_rvalid_i,
	input  logic [NUM_CORES-1:0][31:0]             axi_i_rdata_i,
	input  logic [NUM_CORES-1:0][1:0]              axi_i_rresp_i,

	output logic [NUM_CORES-1:0]                   axi_i_awvalid_o,
	output logic [NUM_CORES-1:0][31:0]             axi_i_awaddr_o,
	output logic [NUM_CORES-1:0]                   axi_i_wvalid_o,
	output logic [NUM_CORES-1:0][31:0]             axi_i_wdata_o,
	output logic [NUM_CORES-1:0][3:0]              axi_i_wstrb_o,
	output logic [NUM_CORES-1:0]                   axi_i_bready_o,
	output logic [NUM_CORES-1:0]                   axi_i_arvalid_o,
	output logic [NUM_CORES-1:0][31:0]             axi_i_araddr_o,
	output logic [NUM_CORES-1:0]                   axi_i_rready_o,

	//=============================================================
	// TCM AXI target side - one target port per core
	//=============================================================
	input  logic [NUM_CORES-1:0]                   axi_t_awvalid_i,
	input  logic [NUM_CORES-1:0][31:0]             axi_t_awaddr_i,
	input  logic [NUM_CORES-1:0][3:0]              axi_t_awid_i,
	input  logic [NUM_CORES-1:0][7:0]              axi_t_awlen_i,
	input  logic [NUM_CORES-1:0][1:0]              axi_t_awburst_i,
	input  logic [NUM_CORES-1:0]                   axi_t_wvalid_i,
	input  logic [NUM_CORES-1:0][31:0]             axi_t_wdata_i,
	input  logic [NUM_CORES-1:0][3:0]              axi_t_wstrb_i,
	input  logic [NUM_CORES-1:0]                   axi_t_wlast_i,
	input  logic [NUM_CORES-1:0]                   axi_t_bready_i,
	input  logic [NUM_CORES-1:0]                   axi_t_arvalid_i,
	input  logic [NUM_CORES-1:0][31:0]             axi_t_araddr_i,
	input  logic [NUM_CORES-1:0][3:0]              axi_t_arid_i,
	input  logic [NUM_CORES-1:0][7:0]              axi_t_arlen_i,
	input  logic [NUM_CORES-1:0][1:0]              axi_t_arburst_i,
	input  logic [NUM_CORES-1:0]                   axi_t_rready_i,

	output logic [NUM_CORES-1:0]                   axi_t_awready_o,
	output logic [NUM_CORES-1:0]                   axi_t_wready_o,
	output logic [NUM_CORES-1:0]                   axi_t_bvalid_o,
	output logic [NUM_CORES-1:0][1:0]              axi_t_bresp_o,
	output logic [NUM_CORES-1:0][3:0]              axi_t_bid_o,
	output logic [NUM_CORES-1:0]                   axi_t_arready_o,
	output logic [NUM_CORES-1:0]                   axi_t_rvalid_o,
	output logic [NUM_CORES-1:0][31:0]             axi_t_rdata_o,
	output logic [NUM_CORES-1:0][1:0]              axi_t_rresp_o,
	output logic [NUM_CORES-1:0][3:0]              axi_t_rid_o,
	output logic [NUM_CORES-1:0]                   axi_t_rlast_o,

	//=============================================================
	// Interrupt input - one 32-bit vector per core
	//=============================================================
	input  logic [NUM_CORES-1:0][31:0]             intr_i
);

	//=============================================================
	// Debug / constants per core
	//=============================================================
	logic [NUM_CORES-1:0][31:0] cpu_id_w;
	logic [NUM_CORES-1:0][31:0] boot_vector_w;

	//=============================================================
	// Per-core internal signals
	//=============================================================

	// Instruction fetch path - raw from core
	logic [NUM_CORES-1:0][31:0] ifetch_pc_raw_w;
	logic [NUM_CORES-1:0]       ifetch_rd_raw_w;
	logic [NUM_CORES-1:0]       ifetch_flush_raw_w;
	logic [NUM_CORES-1:0]       ifetch_invalidate_raw_w;

	// Instruction fetch path - gated to TCM
	logic [NUM_CORES-1:0][31:0] ifetch_pc_w;
	logic [NUM_CORES-1:0]       ifetch_rd_w;
	logic [NUM_CORES-1:0]       ifetch_accept_w;
	logic [NUM_CORES-1:0]       ifetch_valid_w;
	logic [NUM_CORES-1:0]       ifetch_error_w;
	logic [NUM_CORES-1:0]       ifetch_flush_w;
	logic [NUM_CORES-1:0]       ifetch_invalidate_w;
	logic [NUM_CORES-1:0][63:0] ifetch_inst_w;

	// CPU data-port request path - raw from core
	logic [NUM_CORES-1:0][31:0] dport_addr_raw_w;
	logic [NUM_CORES-1:0][31:0] dport_data_wr_raw_w;
	logic [NUM_CORES-1:0]       dport_rd_raw_w;
	logic [NUM_CORES-1:0][3:0]  dport_wr_raw_w;
	logic [NUM_CORES-1:0]       dport_cacheable_raw_w;
	logic [NUM_CORES-1:0][10:0] dport_req_tag_raw_w;
	logic [NUM_CORES-1:0]       dport_invalidate_raw_w;
	logic [NUM_CORES-1:0]       dport_writeback_raw_w;
	logic [NUM_CORES-1:0]       dport_flush_raw_w;

	// CPU data-port request/response path - gated/system side
	logic [NUM_CORES-1:0][31:0] dport_addr_w;
	logic [NUM_CORES-1:0][31:0] dport_data_wr_w;
	logic [NUM_CORES-1:0][31:0] dport_data_rd_w;
	logic [NUM_CORES-1:0]       dport_rd_w;
	logic [NUM_CORES-1:0][3:0]  dport_wr_w;
	logic [NUM_CORES-1:0]       dport_cacheable_w;
	logic [NUM_CORES-1:0][10:0] dport_req_tag_w;
	logic [NUM_CORES-1:0][10:0] dport_resp_tag_w;
	logic [NUM_CORES-1:0]       dport_invalidate_w;
	logic [NUM_CORES-1:0]       dport_writeback_w;
	logic [NUM_CORES-1:0]       dport_flush_w;
	logic [NUM_CORES-1:0]       dport_accept_w;
	logic [NUM_CORES-1:0]       dport_ack_w;
	logic [NUM_CORES-1:0]       dport_error_w;

	// TCM-side data-port signals
	logic [NUM_CORES-1:0][31:0] dport_tcm_addr_w;
	logic [NUM_CORES-1:0][31:0] dport_tcm_data_wr_w;
	logic [NUM_CORES-1:0][31:0] dport_tcm_data_rd_w;
	logic [NUM_CORES-1:0]       dport_tcm_rd_w;
	logic [NUM_CORES-1:0][3:0]  dport_tcm_wr_w;
	logic [NUM_CORES-1:0]       dport_tcm_cacheable_w;
	logic [NUM_CORES-1:0][10:0] dport_tcm_req_tag_w;
	logic [NUM_CORES-1:0][10:0] dport_tcm_resp_tag_w;
	logic [NUM_CORES-1:0]       dport_tcm_invalidate_w;
	logic [NUM_CORES-1:0]       dport_tcm_writeback_w;
	logic [NUM_CORES-1:0]       dport_tcm_flush_w;
	logic [NUM_CORES-1:0]       dport_tcm_accept_w;
	logic [NUM_CORES-1:0]       dport_tcm_ack_w;
	logic [NUM_CORES-1:0]       dport_tcm_error_w;

	// External AXI-side data-port signals
	logic [NUM_CORES-1:0][31:0] dport_axi_addr_w;
	logic [NUM_CORES-1:0][31:0] dport_axi_data_wr_w;
	logic [NUM_CORES-1:0][31:0] dport_axi_data_rd_w;
	logic [NUM_CORES-1:0]       dport_axi_rd_w;
	logic [NUM_CORES-1:0][3:0]  dport_axi_wr_w;
	logic [NUM_CORES-1:0]       dport_axi_cacheable_w;
	logic [NUM_CORES-1:0][10:0] dport_axi_req_tag_w;
	logic [NUM_CORES-1:0][10:0] dport_axi_resp_tag_w;
	logic [NUM_CORES-1:0]       dport_axi_invalidate_w;
	logic [NUM_CORES-1:0]       dport_axi_writeback_w;
	logic [NUM_CORES-1:0]       dport_axi_flush_w;
	logic [NUM_CORES-1:0]       dport_axi_accept_w;
	logic [NUM_CORES-1:0]       dport_axi_ack_w;
	logic [NUM_CORES-1:0]       dport_axi_error_w;

	genvar g;
	generate
		for (g = 0; g < NUM_CORES; g++) begin : gen_core
			assign cpu_id_w[g]      = CORE_ID_BASE + g;
			assign boot_vector_w[g] = BOOT_VECTOR;

			//=====================================================
			// RISC-V Core Instance
			//=====================================================
			riscv_core
			#(
				 .MEM_CACHE_ADDR_MIN        (MEM_CACHE_ADDR_MIN)
				,.MEM_CACHE_ADDR_MAX        (MEM_CACHE_ADDR_MAX)
				,.SUPPORT_BRANCH_PREDICTION (SUPPORT_BRANCH_PREDICTION)
				,.SUPPORT_MULDIV            (SUPPORT_MULDIV)
				,.SUPPORT_SUPER             (SUPPORT_SUPER)
				,.SUPPORT_MMU               (SUPPORT_MMU)
				,.SUPPORT_DUAL_ISSUE        (SUPPORT_DUAL_ISSUE)
				,.SUPPORT_LOAD_BYPASS       (SUPPORT_LOAD_BYPASS)
				,.SUPPORT_MUL_BYPASS        (SUPPORT_MUL_BYPASS)
				,.SUPPORT_REGFILE_XILINX    (SUPPORT_REGFILE_XILINX)
				,.EXTRA_DECODE_STAGE        (EXTRA_DECODE_STAGE)
				,.NUM_BTB_ENTRIES           (NUM_BTB_ENTRIES)
				,.NUM_BTB_ENTRIES_W         (NUM_BTB_ENTRIES_W)
				,.NUM_BHT_ENTRIES           (NUM_BHT_ENTRIES)
				,.NUM_BHT_ENTRIES_W         (NUM_BHT_ENTRIES_W)
				,.RAS_ENABLE                (RAS_ENABLE)
				,.GSHARE_ENABLE             (GSHARE_ENABLE)
				,.BHT_ENABLE                (BHT_ENABLE)
				,.NUM_RAS_ENTRIES           (NUM_RAS_ENTRIES)
				,.NUM_RAS_ENTRIES_W         (NUM_RAS_ENTRIES_W)
			)
			u_core
			(
				 .clk_i                 (clk_i)
				,.rst_i                 (rst_cpu_i[g])
				,.mem_d_data_rd_i       (dport_data_rd_w[g])
				,.mem_d_accept_i        (dport_accept_w[g])
				,.mem_d_ack_i           (dport_ack_w[g])
				,.mem_d_error_i         (dport_error_w[g])
				,.mem_d_resp_tag_i      (dport_resp_tag_w[g])
				,.mem_i_accept_i        (ifetch_accept_w[g])
				,.mem_i_valid_i         (ifetch_valid_w[g])
				,.mem_i_error_i         (ifetch_error_w[g])
				,.mem_i_inst_i          (ifetch_inst_w[g])
				,.intr_i                (|intr_i[g])
				,.reset_vector_i        (boot_vector_w[g])
				,.cpu_id_i              (cpu_id_w[g])

				,.mem_d_addr_o          (dport_addr_raw_w[g])
				,.mem_d_data_wr_o       (dport_data_wr_raw_w[g])
				,.mem_d_rd_o            (dport_rd_raw_w[g])
				,.mem_d_wr_o            (dport_wr_raw_w[g])
				,.mem_d_cacheable_o     (dport_cacheable_raw_w[g])
				,.mem_d_req_tag_o       (dport_req_tag_raw_w[g])
				,.mem_d_invalidate_o    (dport_invalidate_raw_w[g])
				,.mem_d_writeback_o     (dport_writeback_raw_w[g])
				,.mem_d_flush_o         (dport_flush_raw_w[g])

				,.mem_i_rd_o            (ifetch_rd_raw_w[g])
				,.mem_i_flush_o         (ifetch_flush_raw_w[g])
				,.mem_i_invalidate_o    (ifetch_invalidate_raw_w[g])
				,.mem_i_pc_o            (ifetch_pc_raw_w[g])
			);
			assign ifetch_pc_w[g]         = rst_cpu_i[g] ? 32'h0000_0000 : ifetch_pc_raw_w[g];
			assign ifetch_rd_w[g]         = rst_cpu_i[g] ? 1'b0         : ifetch_rd_raw_w[g];
			assign ifetch_flush_w[g]      = rst_cpu_i[g] ? 1'b0         : ifetch_flush_raw_w[g];
			assign ifetch_invalidate_w[g] = rst_cpu_i[g] ? 1'b0         : ifetch_invalidate_raw_w[g];

			assign dport_addr_w[g]        = rst_cpu_i[g] ? 32'h0000_0000 : dport_addr_raw_w[g];
			assign dport_data_wr_w[g]     = rst_cpu_i[g] ? 32'h0000_0000 : dport_data_wr_raw_w[g];
			assign dport_rd_w[g]          = rst_cpu_i[g] ? 1'b0          : dport_rd_raw_w[g];
			assign dport_wr_w[g]          = rst_cpu_i[g] ? 4'b0000       : dport_wr_raw_w[g];
			assign dport_cacheable_w[g]   = rst_cpu_i[g] ? 1'b0          : dport_cacheable_raw_w[g];
			assign dport_req_tag_w[g]     = rst_cpu_i[g] ? 11'h000       : dport_req_tag_raw_w[g];
			assign dport_invalidate_w[g]  = rst_cpu_i[g] ? 1'b0          : dport_invalidate_raw_w[g];
			assign dport_writeback_w[g]   = rst_cpu_i[g] ? 1'b0          : dport_writeback_raw_w[g];
			assign dport_flush_w[g]       = rst_cpu_i[g] ? 1'b0          : dport_flush_raw_w[g];

			//=====================================================
			// Data-Port Mux
			//=====================================================
			dport_mux
			#(
				 .TCM_MEM_BASE(TCM_MEM_BASE)
			)
			u_dmux
			(
				 .clk_i                 (clk_i)
				,.rst_i                 (rst_i)
				,.mem_addr_i            (dport_addr_w[g])
				,.mem_data_wr_i         (dport_data_wr_w[g])
				,.mem_rd_i              (dport_rd_w[g])
				,.mem_wr_i              (dport_wr_w[g])
				,.mem_cacheable_i       (dport_cacheable_w[g])
				,.mem_req_tag_i         (dport_req_tag_w[g])
				,.mem_invalidate_i      (dport_invalidate_w[g])
				,.mem_writeback_i       (dport_writeback_w[g])
				,.mem_flush_i           (dport_flush_w[g])
				,.mem_tcm_data_rd_i     (dport_tcm_data_rd_w[g])
				,.mem_tcm_accept_i      (dport_tcm_accept_w[g])
				,.mem_tcm_ack_i         (dport_tcm_ack_w[g])
				,.mem_tcm_error_i       (dport_tcm_error_w[g])
				,.mem_tcm_resp_tag_i    (dport_tcm_resp_tag_w[g])
				,.mem_ext_data_rd_i     (dport_axi_data_rd_w[g])
				,.mem_ext_accept_i      (dport_axi_accept_w[g])
				,.mem_ext_ack_i         (dport_axi_ack_w[g])
				,.mem_ext_error_i       (dport_axi_error_w[g])
				,.mem_ext_resp_tag_i    (dport_axi_resp_tag_w[g])

				,.mem_data_rd_o         (dport_data_rd_w[g])
				,.mem_accept_o          (dport_accept_w[g])
				,.mem_ack_o             (dport_ack_w[g])
				,.mem_error_o           (dport_error_w[g])
				,.mem_resp_tag_o        (dport_resp_tag_w[g])
				,.mem_tcm_addr_o        (dport_tcm_addr_w[g])
				,.mem_tcm_data_wr_o     (dport_tcm_data_wr_w[g])
				,.mem_tcm_rd_o          (dport_tcm_rd_w[g])
				,.mem_tcm_wr_o          (dport_tcm_wr_w[g])
				,.mem_tcm_cacheable_o   (dport_tcm_cacheable_w[g])
				,.mem_tcm_req_tag_o     (dport_tcm_req_tag_w[g])
				,.mem_tcm_invalidate_o  (dport_tcm_invalidate_w[g])
				,.mem_tcm_writeback_o   (dport_tcm_writeback_w[g])
				,.mem_tcm_flush_o       (dport_tcm_flush_w[g])
				,.mem_ext_addr_o        (dport_axi_addr_w[g])
				,.mem_ext_data_wr_o     (dport_axi_data_wr_w[g])
				,.mem_ext_rd_o          (dport_axi_rd_w[g])
				,.mem_ext_wr_o          (dport_axi_wr_w[g])
				,.mem_ext_cacheable_o   (dport_axi_cacheable_w[g])
				,.mem_ext_req_tag_o     (dport_axi_req_tag_w[g])
				,.mem_ext_invalidate_o  (dport_axi_invalidate_w[g])
				,.mem_ext_writeback_o   (dport_axi_writeback_w[g])
				,.mem_ext_flush_o       (dport_axi_flush_w[g])
			);

			//=====================================================
			// TCM Memory Instance
			//=====================================================
			tcm_mem
			u_tcm
			(
				 .clk_i                 (clk_i)
				,.rst_i                 (rst_i)
				,.mem_i_rd_i            (ifetch_rd_w[g])
				,.mem_i_flush_i         (ifetch_flush_w[g])
				,.mem_i_invalidate_i    (ifetch_invalidate_w[g])
				,.mem_i_pc_i            (ifetch_pc_w[g])
				,.mem_d_addr_i          (dport_tcm_addr_w[g])
				,.mem_d_data_wr_i       (dport_tcm_data_wr_w[g])
				,.mem_d_rd_i            (dport_tcm_rd_w[g])
				,.mem_d_wr_i            (dport_tcm_wr_w[g])
				,.mem_d_cacheable_i     (dport_tcm_cacheable_w[g])
				,.mem_d_req_tag_i       (dport_tcm_req_tag_w[g])
				,.mem_d_invalidate_i    (dport_tcm_invalidate_w[g])
				,.mem_d_writeback_i     (dport_tcm_writeback_w[g])
				,.mem_d_flush_i         (dport_tcm_flush_w[g])
				,.axi_awvalid_i         (axi_t_awvalid_i[g])
				,.axi_awaddr_i          (axi_t_awaddr_i[g])
				,.axi_awid_i            (axi_t_awid_i[g])
				,.axi_awlen_i           (axi_t_awlen_i[g])
				,.axi_awburst_i         (axi_t_awburst_i[g])
				,.axi_wvalid_i          (axi_t_wvalid_i[g])
				,.axi_wdata_i           (axi_t_wdata_i[g])
				,.axi_wstrb_i           (axi_t_wstrb_i[g])
				,.axi_wlast_i           (axi_t_wlast_i[g])
				,.axi_bready_i          (axi_t_bready_i[g])
				,.axi_arvalid_i         (axi_t_arvalid_i[g])
				,.axi_araddr_i          (axi_t_araddr_i[g])
				,.axi_arid_i            (axi_t_arid_i[g])
				,.axi_arlen_i           (axi_t_arlen_i[g])
				,.axi_arburst_i         (axi_t_arburst_i[g])
				,.axi_rready_i          (axi_t_rready_i[g])

				,.mem_i_accept_o        (ifetch_accept_w[g])
				,.mem_i_valid_o         (ifetch_valid_w[g])
				,.mem_i_error_o         (ifetch_error_w[g])
				,.mem_i_inst_o          (ifetch_inst_w[g])
				,.mem_d_data_rd_o       (dport_tcm_data_rd_w[g])
				,.mem_d_accept_o        (dport_tcm_accept_w[g])
				,.mem_d_ack_o           (dport_tcm_ack_w[g])
				,.mem_d_error_o         (dport_tcm_error_w[g])
				,.mem_d_resp_tag_o      (dport_tcm_resp_tag_w[g])
				,.axi_awready_o         (axi_t_awready_o[g])
				,.axi_wready_o          (axi_t_wready_o[g])
				,.axi_bvalid_o          (axi_t_bvalid_o[g])
				,.axi_bresp_o           (axi_t_bresp_o[g])
				,.axi_bid_o             (axi_t_bid_o[g])
				,.axi_arready_o         (axi_t_arready_o[g])
				,.axi_rvalid_o          (axi_t_rvalid_o[g])
				,.axi_rdata_o           (axi_t_rdata_o[g])
				,.axi_rresp_o           (axi_t_rresp_o[g])
				,.axi_rid_o             (axi_t_rid_o[g])
				,.axi_rlast_o           (axi_t_rlast_o[g])
			);

			//=====================================================
			// External AXI Data-Port Adapter
			//=====================================================
			dport_axi
			u_axi
			(
				 .clk_i                 (clk_i)
				,.rst_i                 (rst_i)
				,.mem_addr_i            (dport_axi_addr_w[g])
				,.mem_data_wr_i         (dport_axi_data_wr_w[g])
				,.mem_rd_i              (dport_axi_rd_w[g])
				,.mem_wr_i              (dport_axi_wr_w[g])
				,.mem_cacheable_i       (dport_axi_cacheable_w[g])
				,.mem_req_tag_i         (dport_axi_req_tag_w[g])
				,.mem_invalidate_i      (dport_axi_invalidate_w[g])
				,.mem_writeback_i       (dport_axi_writeback_w[g])
				,.mem_flush_i           (dport_axi_flush_w[g])
				,.axi_awready_i         (axi_i_awready_i[g])
				,.axi_wready_i          (axi_i_wready_i[g])
				,.axi_bvalid_i          (axi_i_bvalid_i[g])
				,.axi_bresp_i           (axi_i_bresp_i[g])
				,.axi_arready_i         (axi_i_arready_i[g])
				,.axi_rvalid_i          (axi_i_rvalid_i[g])
				,.axi_rdata_i           (axi_i_rdata_i[g])
				,.axi_rresp_i           (axi_i_rresp_i[g])

				,.mem_data_rd_o         (dport_axi_data_rd_w[g])
				,.mem_accept_o          (dport_axi_accept_w[g])
				,.mem_ack_o             (dport_axi_ack_w[g])
				,.mem_error_o           (dport_axi_error_w[g])
				,.mem_resp_tag_o        (dport_axi_resp_tag_w[g])
				,.axi_awvalid_o         (axi_i_awvalid_o[g])
				,.axi_awaddr_o          (axi_i_awaddr_o[g])
				,.axi_wvalid_o          (axi_i_wvalid_o[g])
				,.axi_wdata_o           (axi_i_wdata_o[g])
				,.axi_wstrb_o           (axi_i_wstrb_o[g])
				,.axi_bready_o          (axi_i_bready_o[g])
				,.axi_arvalid_o         (axi_i_arvalid_o[g])
				,.axi_araddr_o          (axi_i_araddr_o[g])
				,.axi_rready_o          (axi_i_rready_o[g])
			);
		end
	endgenerate

endmodule