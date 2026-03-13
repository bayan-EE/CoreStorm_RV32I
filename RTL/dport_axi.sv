//=====================================================================
// Module: dport_axi
//=====================================================================
// Description:
// Bridges a simple memory request interface to AXI.
//
// Behavior:
// - Supports one outstanding AXI transaction at a time
// - Buffers requests in a small FIFO
// - Tracks the tag of the request that actually left to AXI
// - Returns registered response outputs
//=====================================================================

module dport_axi
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
	input  logic         axi_awready_i,
	input  logic         axi_wready_i,
	input  logic         axi_bvalid_i,
	input  logic [1:0]   axi_bresp_i,
	input  logic         axi_arready_i,
	input  logic         axi_rvalid_i,
	input  logic [31:0]  axi_rdata_i,
	input  logic [1:0]   axi_rresp_i,

	output logic [31:0]  mem_data_rd_o,
	output logic         mem_accept_o,
	output logic         mem_ack_o,
	output logic         mem_error_o,
	output logic [10:0]  mem_resp_tag_o,
	output logic         axi_awvalid_o,
	output logic [31:0]  axi_awaddr_o,
	output logic         axi_wvalid_o,
	output logic [31:0]  axi_wdata_o,
	output logic [3:0]   axi_wstrb_o,
	output logic         axi_bready_o,
	output logic         axi_arvalid_o,
	output logic [31:0]  axi_araddr_o,
	output logic         axi_rready_o
);

	// ------------------------------------------------------------
	// Internal handshake / FIFO signals
	// ------------------------------------------------------------
	logic         res_accept_w;
	logic         req_accept_w;

	logic         write_complete_w;
	logic         read_complete_w;

	logic         request_pending_q;
	logic         request_in_progress_w;

	logic         req_pop_w;
	logic         req_valid_w;
	logic [68:0]  req_w;
	logic         req_push_w;
	logic         res_push_w;

	logic         req_is_read_w;
	logic         req_is_write_w;

	logic         awvalid_inhibit_q;
	logic         wvalid_inhibit_q;

	logic         axi_resp_valid_w;
	logic [10:0]  resp_tag_head_w;

	// Tag of the request that actually left to AXI
	logic [10:0]  active_tag_q;

	// ------------------------------------------------------------
	// FIFO control
	// ------------------------------------------------------------
	assign req_pop_w      = read_complete_w | write_complete_w;
	assign req_push_w     = (mem_rd_i || (mem_wr_i != 4'b0000)) && res_accept_w;
	assign res_push_w     = (mem_rd_i || (mem_wr_i != 4'b0000)) && req_accept_w;
	assign mem_accept_o   = req_accept_w & res_accept_w;

	// ------------------------------------------------------------
	// Request FIFO
	// Format:
	// {mem_rd_i, mem_wr_i, mem_data_wr_i, mem_addr_i}
	// ------------------------------------------------------------
	dport_axi_fifo
	#(
		.WIDTH (69),
		.DEPTH (2),
		.ADDR_W(1)
	)
	u_req
	(
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.data_in_i  ({mem_rd_i, mem_wr_i, mem_data_wr_i, mem_addr_i}),
		.push_i     (req_push_w),
		.accept_o   (req_accept_w),
		.valid_o    (req_valid_w),
		.data_out_o (req_w),
		.pop_i      (req_pop_w)
	);

	// ------------------------------------------------------------
	// Response tag FIFO
	// Still used for buffered tags
	// ------------------------------------------------------------
	dport_axi_fifo
	#(
		.WIDTH (11),
		.DEPTH (2),
		.ADDR_W(1)
	)
	u_resp
	(
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.data_in_i  (mem_req_tag_i),
		.push_i     (res_push_w),
		.accept_o   (res_accept_w),
		.valid_o    (),
		.data_out_o (resp_tag_head_w),
		.pop_i      (req_pop_w)
	);

	// ------------------------------------------------------------
	// Outstanding request tracking
	// ------------------------------------------------------------
	assign request_in_progress_w = request_pending_q;

	assign req_is_read_w  = (req_valid_w && !request_in_progress_w) ?  req_w[68] : 1'b0;
	assign req_is_write_w = (req_valid_w && !request_in_progress_w) ? ~req_w[68] : 1'b0;

	// ------------------------------------------------------------
	// Write split-handshake inhibit logic
	// ------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			awvalid_inhibit_q <= 1'b0;
		else if (axi_awvalid_o && axi_awready_i && axi_wvalid_o && !axi_wready_i)
			awvalid_inhibit_q <= 1'b1;
		else if (axi_wvalid_o && axi_wready_i)
			awvalid_inhibit_q <= 1'b0;
	end

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			wvalid_inhibit_q <= 1'b0;
		else if (axi_wvalid_o && axi_wready_i && axi_awvalid_o && !axi_awready_i)
			wvalid_inhibit_q <= 1'b1;
		else if (axi_awvalid_o && axi_awready_i)
			wvalid_inhibit_q <= 1'b0;
	end

	// ------------------------------------------------------------
	// AXI request generation
	// ------------------------------------------------------------
	assign axi_awvalid_o = req_is_write_w && !awvalid_inhibit_q;
	assign axi_awaddr_o  = req_is_write_w ? {req_w[31:2], 2'b00} : 32'b0;

	assign axi_wvalid_o  = req_is_write_w && !wvalid_inhibit_q;
	assign axi_wdata_o   = req_is_write_w ? req_w[63:32] : 32'b0;
	assign axi_wstrb_o   = req_is_write_w ? req_w[67:64] : 4'b0000;

	assign axi_bready_o  = 1'b1;

	assign write_complete_w = (awvalid_inhibit_q || axi_awready_i) &&
							  (wvalid_inhibit_q  || axi_wready_i)  &&
							  req_is_write_w;

	assign axi_arvalid_o = req_is_read_w;
	assign axi_araddr_o  = req_is_read_w ? {req_w[31:2], 2'b00} : 32'b0;
	assign axi_rready_o  = 1'b1;

	assign read_complete_w = axi_arvalid_o && axi_arready_i;

	// ------------------------------------------------------------
	// AXI response detect
	// ------------------------------------------------------------
	assign axi_resp_valid_w = axi_bvalid_i || axi_rvalid_i;

	// ------------------------------------------------------------
	// Capture the tag of the request that actually left to AXI
	// ------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			active_tag_q <= 11'b0;
		else if (read_complete_w || write_complete_w)
			active_tag_q <= resp_tag_head_w;
	end

	// ------------------------------------------------------------
	// Registered memory-side response
	// ------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			mem_ack_o      <= 1'b0;
			mem_error_o    <= 1'b0;
			mem_data_rd_o  <= 32'b0;
			mem_resp_tag_o <= 11'b0;
		end
		else begin
			mem_ack_o <= axi_resp_valid_w;

			if (axi_resp_valid_w) begin
				mem_resp_tag_o <= active_tag_q;
				mem_data_rd_o  <= axi_rvalid_i ? axi_rdata_i : 32'b0;
				mem_error_o    <= axi_bvalid_i ? (axi_bresp_i != 2'b00)
											   : (axi_rresp_i != 2'b00);
			end
		end
	end

	// ------------------------------------------------------------
	// One outstanding request tracking
	// ------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			request_pending_q <= 1'b0;
		else if (read_complete_w || write_complete_w)
			request_pending_q <= 1'b1;
		else if (axi_resp_valid_w)
			request_pending_q <= 1'b0;
	end

endmodule