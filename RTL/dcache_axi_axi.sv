//-----------------------------------------------------------------------------
// Module: dcache_axi_axi
//-----------------------------------------------------------------------------
// This module converts a simplified internal memory request interface into
// AXI read/write channel transactions.
//
// Main responsibilities:
// 1. Generate AXI write address (AW) and write data (W) transactions.
// 2. Generate AXI read address (AR) transactions.
// 3. Forward AXI write responses (B) and read responses (R) back to the
//    internal interface.
// 4. Handle write-channel synchronization when AW and W are accepted in
//    different cycles.
// 5. Track write bursts and generate WLAST correctly.
// 6. Use a one-entry skid buffer to hold write data during stalls.
//
// In short, this module is the AXI protocol adapter for the dcache interface.
//-----------------------------------------------------------------------------


`timescale 1ns/1ps

module dcache_axi_axi
(
	// Inputs
	input  logic         clk_i,
	input  logic         rst_i,
	input  logic         inport_valid_i,
	input  logic         inport_write_i,
	input  logic [31:0]  inport_addr_i,
	input  logic [3:0]   inport_id_i,
	input  logic [7:0]   inport_len_i,
	input  logic [1:0]   inport_burst_i,
	input  logic [31:0]  inport_wdata_i,
	input  logic [3:0]   inport_wstrb_i,
	input  logic         inport_bready_i,
	input  logic         inport_rready_i,
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

	// Outputs
	output logic         inport_accept_o,
	output logic         inport_bvalid_o,
	output logic [1:0]   inport_bresp_o,
	output logic [3:0]   inport_bid_o,
	output logic         inport_rvalid_o,
	output logic [31:0]  inport_rdata_o,
	output logic [1:0]   inport_rresp_o,
	output logic [3:0]   inport_rid_o,
	output logic         inport_rlast_o,
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
	output logic         outport_rready_o
);

	//-------------------------------------------------------------
	// Write Request
	//-------------------------------------------------------------
	// These inhibit flags are used to prevent reissuing AW or W
	// when only one side of the AXI write handshake completed.
	logic awvalid_inhibit_q;
	logic wvalid_inhibit_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			awvalid_inhibit_q <= 1'b0;
		else if (outport_awvalid_o && outport_awready_i && outport_wvalid_o && !outport_wready_i)
			awvalid_inhibit_q <= 1'b1;
		else if (outport_awvalid_o && outport_awready_i && (outport_awlen_o != 8'b0))
			awvalid_inhibit_q <= 1'b1;
		else if (outport_wvalid_o && outport_wready_i && outport_wlast_o)
			awvalid_inhibit_q <= 1'b0;
	end

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			wvalid_inhibit_q <= 1'b0;
		else if (outport_wvalid_o && outport_wready_i && outport_awvalid_o && !outport_awready_i)
			wvalid_inhibit_q <= 1'b1;
		else if (outport_awvalid_o && outport_awready_i)
			wvalid_inhibit_q <= 1'b0;
	end

	assign outport_awvalid_o = inport_valid_i & inport_write_i & ~awvalid_inhibit_q;
	assign outport_awaddr_o  = inport_addr_i;
	assign outport_awid_o    = inport_id_i;
	assign outport_awlen_o   = inport_len_i;
	assign outport_awburst_o = inport_burst_i;

	//-------------------------------------------------------------
	// Write burst tracking
	//-------------------------------------------------------------
	// req_cnt_q tracks the remaining number of W beats in the burst.
	logic [7:0] req_cnt_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			req_cnt_q <= 8'b0;
		else if (outport_awvalid_o && outport_awready_i) begin
			// If AW is accepted but the first W beat is not accepted yet,
			// store total beats = AWLEN + 1.
			if (!outport_wready_i && !wvalid_inhibit_q)
				req_cnt_q <= (outport_awlen_o + 8'd1);
			// If first W beat is already accepted in same cycle,
			// remaining beats = AWLEN.
			else
				req_cnt_q <= outport_awlen_o;
		end
		else if ((req_cnt_q != 8'd0) && outport_wvalid_o && outport_wready_i)
			req_cnt_q <= req_cnt_q - 8'd1;
	end

	logic wlast_w;
	assign wlast_w = (outport_awvalid_o && (outport_awlen_o == 8'b0)) || (req_cnt_q == 8'd1);

	//-------------------------------------------------------------
	// Write data skid buffer
	//-------------------------------------------------------------
	// This buffer stores one W beat when AW is accepted but W is stalled.
	logic        buf_valid_q;
	logic [36:0] buf_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			buf_valid_q <= 1'b0;
		else if (outport_wvalid_o && !outport_wready_i && outport_awvalid_o && outport_awready_i)
			buf_valid_q <= 1'b1;
		else if (outport_wready_i)
			buf_valid_q <= 1'b0;
	end

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			buf_q <= 37'b0;
		else
			buf_q <= {outport_wlast_o, outport_wstrb_o, outport_wdata_o};
	end

	assign outport_wvalid_o = buf_valid_q ? 1'b1 : (inport_valid_i & inport_write_i & ~wvalid_inhibit_q);
	assign outport_wdata_o  = buf_valid_q ? buf_q[31:0]  : inport_wdata_i;
	assign outport_wstrb_o  = buf_valid_q ? buf_q[35:32] : inport_wstrb_i;
	assign outport_wlast_o  = buf_valid_q ? buf_q[36]    : wlast_w;

	assign inport_bvalid_o  = outport_bvalid_i;
	assign inport_bresp_o   = outport_bresp_i;
	assign inport_bid_o     = outport_bid_i;
	assign outport_bready_o = inport_bready_i;

	//-------------------------------------------------------------
	// Read Request
	//-------------------------------------------------------------
	assign outport_arvalid_o = inport_valid_i & ~inport_write_i;
	assign outport_araddr_o  = inport_addr_i;
	assign outport_arid_o    = inport_id_i;
	assign outport_arlen_o   = inport_len_i;
	assign outport_arburst_o = inport_burst_i;
	assign outport_rready_o  = inport_rready_i;

	assign inport_rvalid_o   = outport_rvalid_i;
	assign inport_rdata_o    = outport_rdata_i;
	assign inport_rresp_o    = outport_rresp_i;
	assign inport_rid_o      = outport_rid_i;
	assign inport_rlast_o    = outport_rlast_i;

	//-------------------------------------------------------------
	// Accept logic
	//-------------------------------------------------------------
	// The input request is considered accepted when either:
	// 1) AW handshake completes
	// 2) W handshake completes without buffered data
	// 3) AR handshake completes
	assign inport_accept_o = (outport_awvalid_o && outport_awready_i) ||
							 (outport_wvalid_o  && outport_wready_i && !buf_valid_q) ||
							 (outport_arvalid_o && outport_arready_i);

endmodule