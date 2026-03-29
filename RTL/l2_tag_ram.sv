`timescale 1ns/1ps

module l2_tag_ram
#(
	parameter int TAG_W  = 20,
	parameter int DEPTH  = 256,
	parameter int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)
(
	input  logic               clk_i,
	input  logic               rst_i,

	input  logic               en_i,
	input  logic               wr_i,
	input  logic [ADDR_W-1:0]  addr_i,

	input  logic [TAG_W-1:0]   tag_i,
	input  logic               valid_i,
	input  logic               dirty_i,

	output logic [TAG_W-1:0]   tag_o,
	output logic               valid_o,
	output logic               dirty_o
);

	typedef struct packed {
		logic [TAG_W-1:0] tag;
		logic             valid;
		logic             dirty;
	} tag_entry_t;

	tag_entry_t mem_q [0:DEPTH-1];
	tag_entry_t read_entry_w;

	integer i;

	always_comb begin
		read_entry_w = mem_q[addr_i];
	end

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			tag_o   <= '0;
			valid_o <= 1'b0;
			dirty_o <= 1'b0;

			for (i = 0; i < DEPTH; i = i + 1) begin
				mem_q[i] <= '0;
			end
		end
		else begin
			if (en_i) begin
				// Read-first behavior
				tag_o   <= read_entry_w.tag;
				valid_o <= read_entry_w.valid;
				dirty_o <= read_entry_w.dirty;

				if (wr_i) begin
					mem_q[addr_i].tag   <= tag_i;
					mem_q[addr_i].valid <= valid_i;
					mem_q[addr_i].dirty <= dirty_i;
				end
			end
		end
	end

endmodule