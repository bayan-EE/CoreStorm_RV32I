//-----------------------------------------------------------------------------
// Module: dcache_axi
//-----------------------------------------------------------------------------
// This module acts as a bridge between a simple internal data-cache style
// request interface and an AXI bus interface.
//
// Main responsibilities:
// 1. Buffer incoming read/write requests using a small request FIFO.
// 2. Issue requests only when response tracking allows new outstanding
//    transactions.
// 3. Track outstanding read/write responses.
// 4. Forward requests to the AXI helper module (dcache_axi_axi).
// 5. Return acknowledge, error, and read data back to the internal requester.
//
// In short, this module manages request flow control between the cache side
// and the AXI side.
//-----------------------------------------------------------------------------


`timescale 1ns/1ps

module dcache_axi
//-----------------------------------------------------------------
// Parameters
//-----------------------------------------------------------------
#(
	parameter int AXI_ID = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
	// Clock / Reset
	input  logic         clk_i,
	input  logic         rst_i,

	// AXI output-channel handshake inputs from external bus
	input  logic         outport_awready_i,
	input  logic         outport_wready_i,
	input  logic         outport_bvalid_i,
	input  logic [1:0]   outport_bresp_i,
	input  logic [3:0]   outport_bid_i,
	input  logic         outport_arready_i,
	input  logic         outport_rvalid_i,
	input  logic [31:0]  outport_rdata_i,
	input  logic [1:0]   outport_rresp_i,
	input  logic [3:0]   outport_rid_i,
	input  logic         outport_rlast_i,

	// Internal request-side inputs
	input  logic [3:0]   inport_wr_i,
	input  logic         inport_rd_i,
	input  logic [7:0]   inport_len_i,
	input  logic [31:0]  inport_addr_i,
	input  logic [31:0]  inport_write_data_i,

	// AXI output-channel signals to external bus
	output logic         outport_awvalid_o,
	output logic [31:0]  outport_awaddr_o,
	output logic [3:0]   outport_awid_o,
	output logic [7:0]   outport_awlen_o,
	output logic [1:0]   outport_awburst_o,
	output logic         outport_wvalid_o,
	output logic [31:0]  outport_wdata_o,
	output logic [3:0]   outport_wstrb_o,
	output logic         outport_wlast_o,
	output logic         outport_bready_o,
	output logic         outport_arvalid_o,
	output logic [31:0]  outport_araddr_o,
	output logic [3:0]   outport_arid_o,
	output logic [7:0]   outport_arlen_o,
	output logic [1:0]   outport_arburst_o,
	output logic         outport_rready_o,

	// Internal response-side outputs
	output logic         inport_accept_o,
	output logic         inport_ack_o,
	output logic         inport_error_o,
	output logic [31:0]  inport_read_data_o
);

	//-----------------------------------------------------------------
	// Internal signals
	//-----------------------------------------------------------------

	// Response information coming back from AXI helper block
	logic         bvalid_w;
	logic         rvalid_w;
	logic [1:0]   bresp_w;
	logic [1:0]   rresp_w;

	// Request accepted by AXI helper
	logic         accept_w;

	// Outstanding-response tracking interface
	logic         res_accept_w;
	logic         req_accept_w;
	logic         res_valid_w;
	logic         req_valid_w;

	// Request FIFO payload:
	// {len[7:0], rd[0], wr[3:0], wdata[31:0], addr[31:0]}
	logic [76:0]  req_w;
	logic [76:0]  req_data_in_w;

	//-----------------------------------------------------------------
	// Request FIFO
	//-----------------------------------------------------------------
	// Push a request whenever there is either a read or a write request.
	// Write request is indicated by any active byte strobe in inport_wr_i.
	logic req_push_w;
	assign req_push_w    = inport_rd_i || (inport_wr_i != 4'b0000);
	assign req_data_in_w = {inport_len_i, inport_rd_i, inport_wr_i, inport_write_data_i, inport_addr_i};

	dcache_axi_fifo
	#(
		.ADDR_W (1),
		.DEPTH  (2),
		.WIDTH  (32 + 32 + 8 + 4 + 1)
	)
	u_req
	(
		.clk_i      (clk_i),
		.rst_i      (rst_i),

		// Input side
		.data_in_i  (req_data_in_w),
		.push_i     (req_push_w),
		.accept_o   (req_accept_w),

		// Output side
		.valid_o    (req_valid_w),
		.data_out_o (req_w),
		.pop_i      (accept_w)
	);

	// A request may issue only when:
	// 1) the request FIFO contains valid data
	// 2) the response tracker can still accept another outstanding response
	logic       req_can_issue_w;
	logic       req_is_read_w;
	logic       req_is_write_w;
	logic [7:0] req_len_w;

	assign req_can_issue_w = req_valid_w & res_accept_w;
	assign req_is_read_w   = req_can_issue_w ?  req_w[68] : 1'b0;
	assign req_is_write_w  = req_can_issue_w ? ~req_w[68] : 1'b0;
	assign req_len_w       = req_w[76:69];

	// Interface back to internal requester
	assign inport_accept_o = req_accept_w;
	assign inport_ack_o    = bvalid_w || rvalid_w;

	// Error is taken from either B channel or R channel depending on which response arrived
	assign inport_error_o  = bvalid_w ? (bresp_w != 2'b00) : (rresp_w != 2'b00);

	//-----------------------------------------------------------------
	// Write burst tracking
	//-----------------------------------------------------------------
	// req_cnt_q tracks the remaining beats in a write burst after the first beat.
	// This is needed because a burst write generates only one final write response (B channel),
	// and the module should track when that response is expected.
	logic [7:0] req_cnt_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			req_cnt_q <= 8'b0;
		end
		// First cycle of a multi-beat write burst:
		// store remaining beat count = len - 1
		else if (req_is_write_w && (req_cnt_q == 8'd0) && (req_len_w != 8'd0) && accept_w) begin
			req_cnt_q <= req_len_w - 8'd1;
		end
		// Continue counting down remaining beats of current write burst
		else if ((req_cnt_q != 8'd0) && req_is_write_w && accept_w) begin
			req_cnt_q <= req_cnt_q - 8'd1;
		end
	end

	// Last write beat detection
	// For a single-beat write (len == 0), last beat occurs immediately.
	logic req_last_w;
	assign req_last_w = req_is_write_w && (req_len_w == 8'd0) && (req_cnt_q == 8'd0);

	//-----------------------------------------------------------------
	// Response tracking
	//-----------------------------------------------------------------
	// Push a response slot into the outstanding tracker when:
	// - a write request issues and its final beat is accepted, or
	// - a read request issues
	//
	// Pop a response slot when:
	// - a write response (B) arrives, or
	// - the last read response beat (R with RLAST) arrives
	logic res_push_w;
	logic resp_pop_w;

	assign res_push_w = (req_is_write_w && req_last_w && accept_w) ||
						(req_is_read_w  && accept_w);

	assign resp_pop_w = outport_bvalid_i ||
						(outport_rvalid_i ? outport_rlast_i : 1'b0);

	// Maximum 2 outstanding responses are tracked here.
	logic [1:0] resp_outstanding_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			resp_outstanding_q <= 2'b00;
		end
		// Increment count
		else if ((res_push_w & res_accept_w) & ~(resp_pop_w & res_valid_w)) begin
			resp_outstanding_q <= resp_outstanding_q + 2'd1;
		end
		// Decrement count
		else if (~(res_push_w & res_accept_w) & (resp_pop_w & res_valid_w)) begin
			resp_outstanding_q <= resp_outstanding_q - 2'd1;
		end
	end

	assign res_valid_w  = (resp_outstanding_q != 2'd0);
	assign res_accept_w = (resp_outstanding_q != 2'd2);

	//-----------------------------------------------------------------
	// AXI helper block
	//-----------------------------------------------------------------
	// This block converts the simplified internal request interface
	// into AXI channel-level signaling.
	dcache_axi_axi
	u_axi
	(
		.clk_i              (clk_i),
		.rst_i              (rst_i),

		.inport_valid_i     (req_can_issue_w),
		.inport_write_i     (req_is_write_w),
		.inport_wdata_i     (req_w[63:32]),
		.inport_wstrb_i     (req_w[67:64]),
		.inport_addr_i      ({req_w[31:2], 2'b00}), // force word alignment
		.inport_id_i        (AXI_ID),
		.inport_len_i       (req_len_w),
		.inport_burst_i     (2'b01),                // INCR burst
		.inport_accept_o    (accept_w),

		.inport_bready_i    (1'b1),
		.inport_rready_i    (1'b1),
		.inport_bvalid_o    (bvalid_w),
		.inport_bresp_o     (bresp_w),
		.inport_bid_o       (),
		.inport_rvalid_o    (rvalid_w),
		.inport_rdata_o     (inport_read_data_o),
		.inport_rresp_o     (rresp_w),
		.inport_rid_o       (),
		.inport_rlast_o     (),

		.outport_awvalid_o  (outport_awvalid_o),
		.outport_awaddr_o   (outport_awaddr_o),
		.outport_awid_o     (outport_awid_o),
		.outport_awlen_o    (outport_awlen_o),
		.outport_awburst_o  (outport_awburst_o),
		.outport_wvalid_o   (outport_wvalid_o),
		.outport_wdata_o    (outport_wdata_o),
		.outport_wstrb_o    (outport_wstrb_o),
		.outport_wlast_o    (outport_wlast_o),
		.outport_bready_o   (outport_bready_o),
		.outport_arvalid_o  (outport_arvalid_o),
		.outport_araddr_o   (outport_araddr_o),
		.outport_arid_o     (outport_arid_o),
		.outport_arlen_o    (outport_arlen_o),
		.outport_arburst_o  (outport_arburst_o),
		.outport_rready_o   (outport_rready_o),

		.outport_awready_i  (outport_awready_i),
		.outport_wready_i   (outport_wready_i),
		.outport_bvalid_i   (outport_bvalid_i),
		.outport_bresp_i    (outport_bresp_i),
		.outport_bid_i      (outport_bid_i),
		.outport_arready_i  (outport_arready_i),
		.outport_rvalid_i   (outport_rvalid_i),
		.outport_rdata_i    (outport_rdata_i),
		.outport_rresp_i    (outport_rresp_i),
		.outport_rid_i      (outport_rid_i),
		.outport_rlast_i    (outport_rlast_i)
	);

endmodule