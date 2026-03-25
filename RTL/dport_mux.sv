//=====================================================================
// Module: dport_mux
//=====================================================================
// Description:
// Multiplexes CPU data-port transactions between:
//
// 1. TCM memory region
// 2. External memory interface
//
// Behavior:
// - Address range [TCM_MEM_BASE, TCM_MEM_BASE + 64KB) goes to TCM
// - All other addresses go to external memory
//
// Important feature:
// - If there are pending requests to one destination and a new request
//   targets the other destination, the mux asserts an internal hold
//   to preserve ordering and correct response routing.
//
// Notes:
// - The response path uses `tcm_access_q` to remember which target
//   the accepted request was sent to.
//=====================================================================
`timescale 1ns/1ps
module dport_mux
#(
	parameter logic [31:0] TCM_MEM_BASE = 32'h00000000
)
(
	input  logic         clk_i,
	input  logic         rst_i,
	input  logic [31:0]  mem_addr_i,
	input  logic [31:0]  mem_data_wr_i,
	input  logic         mem_rd_i,
	input  logic [3:0]   mem_wr_i,
	input  logic         mem_cacheable_i,
	input  logic [10:0]  mem_req_tag_i,
	input  logic         mem_invalidate_i,
	input  logic         mem_writeback_i,
	input  logic         mem_flush_i,
	input  logic [31:0]  mem_tcm_data_rd_i,
	input  logic         mem_tcm_accept_i,
	input  logic         mem_tcm_ack_i,
	input  logic         mem_tcm_error_i,
	input  logic [10:0]  mem_tcm_resp_tag_i,
	input  logic [31:0]  mem_ext_data_rd_i,
	input  logic         mem_ext_accept_i,
	input  logic         mem_ext_ack_i,
	input  logic         mem_ext_error_i,
	input  logic [10:0]  mem_ext_resp_tag_i,

	output logic [31:0]  mem_data_rd_o,
	output logic         mem_accept_o,
	output logic         mem_ack_o,
	output logic         mem_error_o,
	output logic [10:0]  mem_resp_tag_o,
	output logic [31:0]  mem_tcm_addr_o,
	output logic [31:0]  mem_tcm_data_wr_o,
	output logic         mem_tcm_rd_o,
	output logic [3:0]   mem_tcm_wr_o,
	output logic         mem_tcm_cacheable_o,
	output logic [10:0]  mem_tcm_req_tag_o,
	output logic         mem_tcm_invalidate_o,
	output logic         mem_tcm_writeback_o,
	output logic         mem_tcm_flush_o,
	output logic [31:0]  mem_ext_addr_o,
	output logic [31:0]  mem_ext_data_wr_o,
	output logic         mem_ext_rd_o,
	output logic [3:0]   mem_ext_wr_o,
	output logic         mem_ext_cacheable_o,
	output logic [10:0]  mem_ext_req_tag_o,
	output logic         mem_ext_invalidate_o,
	output logic         mem_ext_writeback_o,
	output logic         mem_ext_flush_o
);

	// ------------------------------------------------------------
	// Internal control
	// ------------------------------------------------------------
	logic        hold_w;
	logic        tcm_access_w;
	logic        tcm_access_q;
	logic [4:0]  pending_q;
	logic [4:0]  pending_r;
	logic        request_w;

	// ------------------------------------------------------------
	// Address decode
	// TCM region = 64KB
	// ------------------------------------------------------------
	assign tcm_access_w = (mem_addr_i >= TCM_MEM_BASE) &&
						  (mem_addr_i < (TCM_MEM_BASE + 32'd65536));

	// ------------------------------------------------------------
	// Forward request to TCM
	// ------------------------------------------------------------
	assign mem_tcm_addr_o       = mem_addr_i;
	assign mem_tcm_data_wr_o    = mem_data_wr_i;
	assign mem_tcm_rd_o         = ( tcm_access_w && !hold_w) ? mem_rd_i          : 1'b0;
	assign mem_tcm_wr_o         = ( tcm_access_w && !hold_w) ? mem_wr_i          : 4'b0000;
	assign mem_tcm_cacheable_o  = mem_cacheable_i;
	assign mem_tcm_req_tag_o    = mem_req_tag_i;
	assign mem_tcm_invalidate_o = ( tcm_access_w && !hold_w) ? mem_invalidate_i  : 1'b0;
	assign mem_tcm_writeback_o  = ( tcm_access_w && !hold_w) ? mem_writeback_i   : 1'b0;
	assign mem_tcm_flush_o      = ( tcm_access_w && !hold_w) ? mem_flush_i       : 1'b0;

	// ------------------------------------------------------------
	// Forward request to external interface
	// ------------------------------------------------------------
	assign mem_ext_addr_o       = mem_addr_i;
	assign mem_ext_data_wr_o    = mem_data_wr_i;
	assign mem_ext_rd_o         = (!tcm_access_w && !hold_w) ? mem_rd_i          : 1'b0;
	assign mem_ext_wr_o         = (!tcm_access_w && !hold_w) ? mem_wr_i          : 4'b0000;
	assign mem_ext_cacheable_o  = mem_cacheable_i;
	assign mem_ext_req_tag_o    = mem_req_tag_i;
	assign mem_ext_invalidate_o = (!tcm_access_w && !hold_w) ? mem_invalidate_i  : 1'b0;
	assign mem_ext_writeback_o  = (!tcm_access_w && !hold_w) ? mem_writeback_i   : 1'b0;
	assign mem_ext_flush_o      = (!tcm_access_w && !hold_w) ? mem_flush_i       : 1'b0;

	// ------------------------------------------------------------
	// Accept path uses current target selection
	// ------------------------------------------------------------
	assign mem_accept_o = (tcm_access_w ? mem_tcm_accept_i : mem_ext_accept_i) && !hold_w;

	// ------------------------------------------------------------
	// Response path uses registered target selection
	// ------------------------------------------------------------
	assign mem_data_rd_o  = tcm_access_q ? mem_tcm_data_rd_i  : mem_ext_data_rd_i;
	assign mem_ack_o      = tcm_access_q ? mem_tcm_ack_i      : mem_ext_ack_i;
	assign mem_error_o    = tcm_access_q ? mem_tcm_error_i    : mem_ext_error_i;
	assign mem_resp_tag_o = tcm_access_q ? mem_tcm_resp_tag_i : mem_ext_resp_tag_i;

	// ------------------------------------------------------------
	// Request detection
	// ------------------------------------------------------------
	assign request_w = mem_rd_i ||
					   (mem_wr_i != 4'b0000) ||
					   mem_flush_i ||
					   mem_invalidate_i ||
					   mem_writeback_i;

	// ------------------------------------------------------------
	// Pending request counter
	// Tracks accepted-but-not-yet-acknowledged operations
	// ------------------------------------------------------------
	always_comb begin
		pending_r = pending_q;

		if ((request_w && mem_accept_o) && !mem_ack_o)
			pending_r = pending_q + 5'd1;
		else if (!(request_w && mem_accept_o) && mem_ack_o)
			pending_r = pending_q - 5'd1;
	end

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			pending_q <= '0;
		else
			pending_q <= pending_r;
	end

	// ------------------------------------------------------------
	// Remember destination of accepted request
	// ------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			tcm_access_q <= 1'b0;
		else if (request_w && mem_accept_o)
			tcm_access_q <= tcm_access_w;
	end

	// ------------------------------------------------------------
	// Hold when there are pending requests to one side and
	// a new request targets the other side.
	// ------------------------------------------------------------
	assign hold_w = (|pending_q) && (tcm_access_q != tcm_access_w);

endmodule