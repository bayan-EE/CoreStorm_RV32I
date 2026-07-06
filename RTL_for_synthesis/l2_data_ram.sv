`timescale 1ns/1ps

module l2_data_ram
#(
	parameter int DATA_W = 256,
	parameter int DEPTH  = 256,
	parameter int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
	parameter int BE_W   = DATA_W / 8
)
(
	input  logic                 clk_i,
	input  logic                 rst_i,

	input  logic                 en_i,
	input  logic                 wr_i,
	input  logic [ADDR_W-1:0]    addr_i,
	input  logic [DATA_W-1:0]    wdata_i,
	input  logic [BE_W-1:0]      wstrb_i,

	output logic [DATA_W-1:0]    rdata_o
);

	logic [DATA_W-1:0] mem_q [0:DEPTH-1];
	logic [DATA_W-1:0] read_data_w;

	integer i;
	integer b;

	always_comb begin
		read_data_w = mem_q[addr_i];
	end

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			rdata_o <= '0;
			for (i = 0; i < DEPTH; i = i + 1) begin
				mem_q[i] <= '0;
			end
		end
		else begin
			if (en_i) begin
				// Read-first behavior: output old memory contents
				rdata_o <= read_data_w;

				if (wr_i) begin
					for (b = 0; b < BE_W; b = b + 1) begin
						if (wstrb_i[b]) begin
							mem_q[addr_i][8*b +: 8] <= wdata_i[8*b +: 8];
						end
					end
				end
			end
		end
	end

endmodule