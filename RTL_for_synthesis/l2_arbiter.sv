`timescale 1ns/1ps

module l2_arbiter
#(
	parameter int NUM_PORTS = 4,
	parameter int IDX_W     = (NUM_PORTS <= 1) ? 1 : $clog2(NUM_PORTS)
)
(
	input  logic                   clk_i,
	input  logic                   rst_i,

	input  logic [NUM_PORTS-1:0]   req_i,
	input  logic                   accept_i,

	output logic                   grant_valid_o,
	output logic [IDX_W-1:0]       grant_idx_o,
	output logic [NUM_PORTS-1:0]   grant_onehot_o
);

	logic [IDX_W-1:0] rr_ptr_q;
	logic [IDX_W-1:0] sel_idx_r;
	logic             sel_valid_r;
	logic [NUM_PORTS-1:0] sel_onehot_r;

	integer k;
	integer idx;

	always_comb begin
		sel_valid_r  = 1'b0;
		sel_idx_r    = rr_ptr_q;
		sel_onehot_r = '0;

		for (k = 0; k < NUM_PORTS; k = k + 1) begin
			idx = rr_ptr_q + k;
			if (idx >= NUM_PORTS)
				idx = idx - NUM_PORTS;

			if (!sel_valid_r && req_i[idx]) begin
				sel_valid_r        = 1'b1;
				sel_idx_r          = idx[IDX_W-1:0];
				sel_onehot_r[idx]  = 1'b1;
			end
		end
	end

	assign grant_valid_o  = sel_valid_r;
	assign grant_idx_o    = sel_idx_r;
	assign grant_onehot_o = sel_onehot_r;

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			rr_ptr_q <= '0;
		end
		else begin
			if (grant_valid_o && accept_i) begin
				if (grant_idx_o == NUM_PORTS-1)
					rr_ptr_q <= '0;
				else
					rr_ptr_q <= grant_idx_o + 1'b1;
			end
		end
	end

endmodule