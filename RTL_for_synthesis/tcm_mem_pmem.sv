
//---------------------------------------------------------------------
// Module: tcm_mem_pmem
// Type  : AXI-to-simple-memory bridge
//
// Description:
// This module bridges a simplified AXI-style interface to a very simple
// RAM-like interface.
//
// It accepts AXI read and write transactions and converts them into:
//
//   - ram_rd_o          : single read request pulse
//   - ram_wr_o          : byte write strobes for write requests
//   - ram_addr_o        : memory address
//   - ram_write_data_o  : write data
//
// It also converts RAM acknowledgements and read data back into AXI
// response channels:
//
//   - AXI read data channel (R)
//   - AXI write response channel (B)
//
// Main features:
// - Supports burst progression by internally tracking remaining beats.
// - Tracks transaction ID and whether a response belongs to a read or
//   write request.
// - Uses small FIFOs to preserve ordering between issued RAM requests
//   and returned responses.
// - Arbitration between reads and writes is done with a round-robin
//   style priority mechanism, with hold logic when RAM does not accept
//   a request immediately.
//
// Notes:
// - This bridge assumes the RAM side returns one acknowledgement per
//   accepted request beat.
// - The RAM interface is much simpler than AXI and does not explicitly
//   encode burst types beyond internal address generation.
// - Response errors are currently hardwired to OKAY (2'b00).
//---------------------------------------------------------------------
`timescale 1ns/1ps


module tcm_mem_pmem
(
	// Inputs
	input  logic        clk_i,
	input  logic        rst_i,
	input  logic        axi_awvalid_i,
	input  logic [31:0] axi_awaddr_i,
	input  logic [3:0]  axi_awid_i,
	input  logic [7:0]  axi_awlen_i,
	input  logic [1:0]  axi_awburst_i,
	input  logic        axi_wvalid_i,
	input  logic [31:0] axi_wdata_i,
	input  logic [3:0]  axi_wstrb_i,
	input  logic        axi_wlast_i,
	input  logic        axi_bready_i,
	input  logic        axi_arvalid_i,
	input  logic [31:0] axi_araddr_i,
	input  logic [3:0]  axi_arid_i,
	input  logic [7:0]  axi_arlen_i,
	input  logic [1:0]  axi_arburst_i,
	input  logic        axi_rready_i,
	input  logic        ram_accept_i,
	input  logic        ram_ack_i,
	input  logic        ram_error_i,
	input  logic [31:0] ram_read_data_i,

	// Outputs
	output logic        axi_awready_o,
	output logic        axi_wready_o,
	output logic        axi_bvalid_o,
	output logic [1:0]  axi_bresp_o,
	output logic [3:0]  axi_bid_o,
	output logic        axi_arready_o,
	output logic        axi_rvalid_o,
	output logic [31:0] axi_rdata_o,
	output logic [1:0]  axi_rresp_o,
	output logic [3:0]  axi_rid_o,
	output logic        axi_rlast_o,
	output logic [3:0]  ram_wr_o,
	output logic        ram_rd_o,
	output logic [7:0]  ram_len_o,
	output logic [31:0] ram_addr_o,
	output logic [31:0] ram_write_data_o
);

	//-----------------------------------------------------------------
	// Function: calculate_addr_next
	//
	// Computes the next address for a burst transfer.
	// Supported behavior depends on compile-time defines:
	//   - INCR  : default
	//   - FIXED : optional
	//   - WRAP  : optional
	//-----------------------------------------------------------------
	function automatic logic [31:0] calculate_addr_next;
		input logic [31:0] addr;
		input logic [1:0]  axtype;
		input logic [7:0]  axlen;

		logic [31:0] mask;
		begin
			mask = 32'b0;

			case (axtype)
`ifdef SUPPORT_FIXED_BURST
				2'd0: begin
					// AXI4_BURST_FIXED
					calculate_addr_next = addr;
				end
`endif

`ifdef SUPPORT_WRAP_BURST
				2'd2: begin
					// AXI4_BURST_WRAP
					case (axlen)
						8'd0:    mask = 32'h0000_0003;
						8'd1:    mask = 32'h0000_0007;
						8'd3:    mask = 32'h0000_000F;
						8'd7:    mask = 32'h0000_001F;
						8'd15:   mask = 32'h0000_003F;
						default: mask = 32'h0000_003F;
					endcase

					calculate_addr_next = (addr & ~mask) | ((addr + 32'd4) & mask);
				end
`endif

				default: begin
					// AXI4_BURST_INCR
					calculate_addr_next = addr + 32'd4;
				end
			endcase
		end
	endfunction

	//-----------------------------------------------------------------
	// Registers / Internal Signals
	//-----------------------------------------------------------------
	logic [7:0]  req_len_q;
	logic [31:0] req_addr_q;
	logic        req_rd_q;
	logic        req_wr_q;
	logic [3:0]  req_id_q;
	logic [1:0]  req_axburst_q;
	logic [7:0]  req_axlen_q;
	logic        req_prio_q;
	logic        req_hold_rd_q;
	logic        req_hold_wr_q;

	logic        req_fifo_accept_w;

	//-----------------------------------------------------------------
	// Request State Tracking
	//-----------------------------------------------------------------
	// Tracks the currently active burst request on the RAM side:
	// - whether it is read or write
	// - remaining number of beats
	// - address progression
	// - AXI ID and burst type information
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			req_len_q     <= 8'b0;
			req_addr_q    <= 32'b0;
			req_wr_q      <= 1'b0;
			req_rd_q      <= 1'b0;
			req_id_q      <= 4'b0;
			req_axburst_q <= 2'b0;
			req_axlen_q   <= 8'b0;
			req_prio_q    <= 1'b0;
		end
		else begin
			// Continue an already issued burst if RAM accepted the beat
			if (((ram_wr_o != 4'b0) || ram_rd_o) && ram_accept_i) begin
				if (req_len_q == 8'd0) begin
					req_rd_q <= 1'b0;
					req_wr_q <= 1'b0;
				end
				else begin
					req_addr_q <= calculate_addr_next(req_addr_q, req_axburst_q, req_axlen_q);
					req_len_q  <= req_len_q - 8'd1;
				end
			end

			// New write command accepted
			if (axi_awvalid_i && axi_awready_o) begin
				// Address and first data beat accepted together
				if (axi_wvalid_i && axi_wready_o) begin
					req_wr_q      <= !axi_wlast_i;
					req_len_q     <= axi_awlen_i - 8'd1;
					req_id_q      <= axi_awid_i;
					req_axburst_q <= axi_awburst_i;
					req_axlen_q   <= axi_awlen_i;
					req_addr_q    <= calculate_addr_next(axi_awaddr_i, axi_awburst_i, axi_awlen_i);
				end
				// Address accepted, data beat still pending
				else begin
					req_wr_q      <= 1'b1;
					req_len_q     <= axi_awlen_i;
					req_id_q      <= axi_awid_i;
					req_axburst_q <= axi_awburst_i;
					req_axlen_q   <= axi_awlen_i;
					req_addr_q    <= axi_awaddr_i;
				end

				req_prio_q <= !req_prio_q;
			end
			// New read command accepted
			else if (axi_arvalid_i && axi_arready_o) begin
				req_rd_q      <= (axi_arlen_i != 8'd0);
				req_len_q     <= axi_arlen_i - 8'd1;
				req_addr_q    <= calculate_addr_next(axi_araddr_i, axi_arburst_i, axi_arlen_i);
				req_id_q      <= axi_arid_i;
				req_axburst_q <= axi_arburst_i;
				req_axlen_q   <= axi_arlen_i;
				req_prio_q    <= !req_prio_q;
			end
		end
	end

	//-----------------------------------------------------------------
	// Hold Tracking
	//-----------------------------------------------------------------
	// If a read/write request was issued but RAM did not accept it,
	// remember that request direction and keep prioritizing it.
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			req_hold_rd_q <= 1'b0;
			req_hold_wr_q <= 1'b0;
		end
		else begin
			if (ram_rd_o && !ram_accept_i)
				req_hold_rd_q <= 1'b1;
			else if (ram_accept_i)
				req_hold_rd_q <= 1'b0;

			if ((|ram_wr_o) && !ram_accept_i)
				req_hold_wr_q <= 1'b1;
			else if (ram_accept_i)
				req_hold_wr_q <= 1'b0;
		end
	end

	//-----------------------------------------------------------------
	// Request Tracking FIFO
	//-----------------------------------------------------------------
	// For every accepted RAM request beat, push metadata describing:
	//   [5]   : 1 = read, 0 = write
	//   [4]   : 1 = last beat of burst
	//   [3:0] : AXI ID
	//
	// This allows proper reconstruction of AXI responses once RAM
	// acknowledgements come back.
	logic       req_push_w;
	logic [5:0] req_in_r;

	logic       req_out_valid_w;
	logic [5:0] req_out_w;
	logic       resp_accept_w;

	assign req_push_w = (ram_rd_o || (ram_wr_o != 4'b0)) && ram_accept_i;

	always_comb begin
		req_in_r = 6'b0;

		// First beat of a read burst
		if (axi_arvalid_i && axi_arready_o)
			req_in_r = {1'b1, (axi_arlen_i == 8'd0), axi_arid_i};

		// First beat of a write burst
		else if (axi_awvalid_i && axi_awready_o)
			req_in_r = {1'b0, (axi_awlen_i == 8'd0), axi_awid_i};

		// Later burst beats
		else
			req_in_r = {ram_rd_o, (req_len_q == 8'd0), req_id_q};
	end

	tcm_mem_pmem_fifo2
	#(
		.WIDTH (1 + 1 + 4)
	)
	u_requests
	(
		.clk_i      (clk_i),
		.rst_i      (rst_i),

		// Input side
		.data_in_i  (req_in_r),
		.push_i     (req_push_w),
		.pop_i      (resp_accept_w),
		.data_out_o (req_out_w),
		.accept_o   (req_fifo_accept_w),
		.valid_o    (req_out_valid_w)
	);

	logic       resp_is_write_w;
	logic       resp_is_read_w;
	logic       resp_is_last_w;
	logic [3:0] resp_id_w;

	assign resp_is_write_w = req_out_valid_w ? ~req_out_w[5] : 1'b0;
	assign resp_is_read_w  = req_out_valid_w ?  req_out_w[5] : 1'b0;
	assign resp_is_last_w  = req_out_w[4];
	assign resp_id_w       = req_out_w[3:0];

	//-----------------------------------------------------------------
	// Response Data FIFO
	//-----------------------------------------------------------------
	// Read data from RAM is buffered so it can be aligned with request
	// metadata and consumed on the AXI response channel.
	logic resp_valid_w;

	tcm_mem_pmem_fifo2
	#(
		.WIDTH (32)
	)
	u_response
	(
		.clk_i      (clk_i),
		.rst_i      (rst_i),

		// Input side
		.data_in_i  (ram_read_data_i),
		.push_i     (ram_ack_i),
		.pop_i      (resp_accept_w),
		.data_out_o (axi_rdata_o),
		.accept_o   (),
		.valid_o    (resp_valid_w)
	);

	//-----------------------------------------------------------------
	// RAM Request Arbitration
	//-----------------------------------------------------------------
	// Round-robin style arbitration between read and write channels.
	// Hold bits keep an unaccepted direction active until RAM accepts it.
	logic write_prio_w;
	logic read_prio_w;
	logic write_active_w;
	logic read_active_w;
	logic [31:0] addr_w;
	logic        wr_w;
	logic        rd_w;

	assign write_prio_w   = ((req_prio_q  & !req_hold_rd_q) | req_hold_wr_q);
	assign read_prio_w    = ((!req_prio_q & !req_hold_wr_q) | req_hold_rd_q);

	assign write_active_w = (axi_awvalid_i || req_wr_q) &&
							!req_rd_q &&
							req_fifo_accept_w &&
							(write_prio_w || req_wr_q || !axi_arvalid_i);

	assign read_active_w  = (axi_arvalid_i || req_rd_q) &&
							!req_wr_q &&
							req_fifo_accept_w &&
							(read_prio_w || req_rd_q || !axi_awvalid_i);

	assign axi_awready_o  = write_active_w && !req_wr_q && ram_accept_i && req_fifo_accept_w;
	assign axi_wready_o   = write_active_w &&              ram_accept_i && req_fifo_accept_w;
	assign axi_arready_o  = read_active_w  && !req_rd_q && ram_accept_i && req_fifo_accept_w;

	assign addr_w = (req_wr_q || req_rd_q) ? req_addr_q :
					(write_active_w       ? axi_awaddr_i : axi_araddr_i);

	assign wr_w = write_active_w && axi_wvalid_i;
	assign rd_w = read_active_w;

	//-----------------------------------------------------------------
	// RAM Interface Outputs
	//-----------------------------------------------------------------
	assign ram_addr_o       = addr_w;
	assign ram_write_data_o = axi_wdata_i;
	assign ram_rd_o         = rd_w;
	assign ram_wr_o         = wr_w ? axi_wstrb_i : 4'b0;
	assign ram_len_o        = 8'b0;

	//-----------------------------------------------------------------
	// AXI Response Generation
	//-----------------------------------------------------------------
	assign axi_bvalid_o = resp_valid_w & resp_is_write_w & resp_is_last_w;
	assign axi_bresp_o  = 2'b0;
	assign axi_bid_o    = resp_id_w;

	assign axi_rvalid_o = resp_valid_w & resp_is_read_w;
	assign axi_rresp_o  = 2'b0;
	assign axi_rid_o    = resp_id_w;
	assign axi_rlast_o  = resp_is_last_w;

	// Consume a response when:
	// - AXI read data is accepted, or
	// - AXI write response is accepted, or
	// - it is an intermediate write-burst beat response that should not
	//   be exposed on AXI B channel.
	assign resp_accept_w = (axi_rvalid_o & axi_rready_i) |
						   (axi_bvalid_o & axi_bready_i) |
						   (resp_valid_w & resp_is_write_w & !resp_is_last_w);

endmodule


//---------------------------------------------------------------------
// Module: tcm_mem_pmem_fifo2
// Type  : Simple synchronous FIFO
//
// Description:
// This is a small parameterized FIFO used inside tcm_mem_pmem for:
//
//   1. tracking request metadata
//   2. buffering read response data
//
// Characteristics:
// - single clock
// - synchronous push/pop
// - simple count-based full/empty tracking
// - output is combinationally read from the current read pointer
//
// Parameters:
// - WIDTH  : data width
// - DEPTH  : number of entries
// - ADDR_W : pointer width, usually log2(DEPTH)
//
// Notes:
// - Push happens only when accept_o is high.
// - Pop happens only when valid_o is high.
// - Simultaneous push and pop are supported.
//---------------------------------------------------------------------
module tcm_mem_pmem_fifo2
#(
	parameter int WIDTH  = 8,
	parameter int DEPTH  = 4,
	parameter int ADDR_W = 2
)
(
	// Inputs
	input  logic             clk_i,
	input  logic             rst_i,
	input  logic [WIDTH-1:0] data_in_i,
	input  logic             push_i,
	input  logic             pop_i,

	// Outputs
	output logic [WIDTH-1:0] data_out_o,
	output logic             accept_o,
	output logic             valid_o
);

	//-----------------------------------------------------------------
	// Local Parameters
	//-----------------------------------------------------------------
	localparam int COUNT_W = ADDR_W + 1;

	//-----------------------------------------------------------------
	// Storage / Pointers / Count
	//-----------------------------------------------------------------
	logic [WIDTH-1:0] ram [0:DEPTH-1];
	logic [ADDR_W-1:0] rd_ptr;
	logic [ADDR_W-1:0] wr_ptr;
	logic [COUNT_W-1:0] count;

	//-----------------------------------------------------------------
	// Sequential Logic
	//-----------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			count  <= '0;
			rd_ptr <= '0;
			wr_ptr <= '0;
		end
		else begin
			// Push
			if (push_i && accept_o) begin
				ram[wr_ptr] <= data_in_i;
				wr_ptr      <= wr_ptr + 1'b1;
			end

			// Pop
			if (pop_i && valid_o)
				rd_ptr <= rd_ptr + 1'b1;

			// Count management
			if ((push_i && accept_o) && !(pop_i && valid_o))
				count <= count + 1'b1;
			else if (!(push_i && accept_o) && (pop_i && valid_o))
				count <= count - 1'b1;
		end
	end

	//-----------------------------------------------------------------
	// Combinational Status / Output
	//-----------------------------------------------------------------
	/* verilator lint_off WIDTH */
	assign accept_o   = (count != DEPTH);
	assign valid_o    = (count != 0);
	/* verilator lint_on WIDTH */

	assign data_out_o = ram[rd_ptr];

endmodule