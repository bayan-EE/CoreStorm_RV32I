//-----------------------------------------------------------------------------
// Module: dcache_axi_fifo
//-----------------------------------------------------------------------------
// This module implements a small parameterized synchronous FIFO.
//
// Main responsibilities:
// 1. Temporarily store requests or data entries.
// 2. Decouple producer and consumer timing.
// 3. Provide simple push/pop flow control using accept_o and valid_o.
//
// The FIFO is generic and does not depend on AXI specifically.
// In this design, it is used as a request queue for dcache_axi.
//-----------------------------------------------------------------------------


`timescale 1ns/1ps

module dcache_axi_fifo
//-----------------------------------------------------------------
// Parameters
//-----------------------------------------------------------------
#(
	parameter int WIDTH  = 8,
	parameter int DEPTH  = 4,
	parameter int ADDR_W = 2
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
	input  logic              clk_i,
	input  logic              rst_i,
	input  logic [WIDTH-1:0]  data_in_i,
	input  logic              push_i,
	input  logic              pop_i,

	output logic [WIDTH-1:0]  data_out_o,
	output logic              accept_o,
	output logic              valid_o
);

	//-----------------------------------------------------------------
	// Local parameters
	//-----------------------------------------------------------------
	localparam int COUNT_W = ADDR_W + 1;

	//-----------------------------------------------------------------
	// Storage / pointers / occupancy
	//-----------------------------------------------------------------
	logic [WIDTH-1:0] ram_q [0:DEPTH-1];
	logic [ADDR_W-1:0] rd_ptr_q;
	logic [ADDR_W-1:0] wr_ptr_q;
	logic [COUNT_W-1:0] count_q;

	//-----------------------------------------------------------------
	// Sequential logic
	//-----------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			count_q  <= '0;
			rd_ptr_q <= '0;
			wr_ptr_q <= '0;
		end
		else begin
			// Push into FIFO when input is valid and FIFO is not full
			if (push_i && accept_o) begin
				ram_q[wr_ptr_q] <= data_in_i;
				wr_ptr_q        <= wr_ptr_q + 1'b1;
			end

			// Pop from FIFO when consumer accepts valid data
			if (pop_i && valid_o) begin
				rd_ptr_q <= rd_ptr_q + 1'b1;
			end

			// Update occupancy count
			if ((push_i && accept_o) && !(pop_i && valid_o)) begin
				count_q <= count_q + 1'b1;
			end
			else if (!(push_i && accept_o) && (pop_i && valid_o)) begin
				count_q <= count_q - 1'b1;
			end
		end
	end

	//-----------------------------------------------------------------
	// Combinational outputs
	//-----------------------------------------------------------------
	// FIFO has valid data whenever occupancy is non-zero
	assign valid_o  = (count_q != '0);

	// FIFO can accept data whenever it is not full
	assign accept_o = (count_q != DEPTH);

	// Show current head entry
	assign data_out_o = ram_q[rd_ptr_q];

endmodule