//=====================================================================
// Module: dport_axi_fifo
//=====================================================================
// Description:
// Simple synchronous FIFO used by the AXI data-port bridge.
//
// Features:
// - Parameterized data width and depth
// - Single clock FIFO
// - Push/Pop interface
// - `accept_o` indicates space available for push
// - `valid_o` indicates data available for pop
//
// Notes:
// - This is a small FIFO intended for buffering request metadata
//   and response tags.
// - The implementation keeps the original functionality unchanged.
//=====================================================================
`timescale 1ns/1ps
module dport_axi_fifo
#(
	parameter int unsigned WIDTH  = 8,
	parameter int unsigned DEPTH  = 2,
	parameter int unsigned ADDR_W = 1
)
(
	input  logic             clk_i,
	input  logic             rst_i,
	input  logic [WIDTH-1:0] data_in_i,
	input  logic             push_i,
	input  logic             pop_i,

	output logic [WIDTH-1:0] data_out_o,
	output logic             accept_o,
	output logic             valid_o
);

	// ------------------------------------------------------------
	// Local parameters
	// ------------------------------------------------------------
	localparam int unsigned COUNT_W = ADDR_W + 1;

	// ------------------------------------------------------------
	// Internal storage and pointers
	// ------------------------------------------------------------
	logic [WIDTH-1:0] ram_q [0:DEPTH-1];
	logic [ADDR_W-1:0] rd_ptr_q;
	logic [ADDR_W-1:0] wr_ptr_q;
	logic [COUNT_W-1:0] count_q;

	// ------------------------------------------------------------
	// Sequential logic
	// ------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			count_q  <= '0;
			rd_ptr_q <= '0;
			wr_ptr_q <= '0;
		end
		else begin
			// Push into FIFO when allowed
			if (push_i && accept_o) begin
				ram_q[wr_ptr_q] <= data_in_i;
				wr_ptr_q        <= wr_ptr_q + 1'b1;
			end

			// Pop from FIFO when valid
			if (pop_i && valid_o) begin
				rd_ptr_q <= rd_ptr_q + 1'b1;
			end

			// Count update
			if ((push_i && accept_o) && !(pop_i && valid_o))
				count_q <= count_q + 1'b1;
			else if (!(push_i && accept_o) && (pop_i && valid_o))
				count_q <= count_q - 1'b1;
		end
	end

	// ------------------------------------------------------------
	// Combinational outputs
	// ------------------------------------------------------------
	assign valid_o    = (count_q != '0);
	assign accept_o   = (count_q != DEPTH);
	assign data_out_o = ram_q[rd_ptr_q];

endmodule