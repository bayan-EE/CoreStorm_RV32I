`timescale 1ns/1ps


import coherence_pkg::*;

module snoop_bus
#(
	parameter int NUM_CORES  = 4,
	parameter int CORE_IDX_W = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES)
)
(
	input  logic                              clk_i,
	input  logic                              rst_i,

	input  logic                              start_i,
	input  logic [CORE_IDX_W-1:0]             source_core_i,
	input  snoop_cmd_t                        cmd_i,
	input  logic [31:0]                       addr_i,

	input  logic [NUM_CORES-1:0]              cache_snoop_hit_i,
	input  logic [NUM_CORES-1:0]              cache_snoop_dirty_i,
	input  logic [NUM_CORES-1:0]              cache_snoop_ack_i,

	output logic [NUM_CORES-1:0]              snoop_valid_o,
	output snoop_cmd_t [NUM_CORES-1:0]        snoop_cmd_o,
	output logic [NUM_CORES-1:0][31:0]        snoop_addr_o,

	output logic                              busy_o,
	output logic                              done_o,
	output logic                              any_hit_o,
	output logic                              any_dirty_o,
	output logic [NUM_CORES-1:0]              ack_seen_o
);

	logic                         active_q;
	logic                         done_q;
	logic [CORE_IDX_W-1:0]        source_core_q;
	snoop_cmd_t                   cmd_q;
	logic [31:0]                  addr_q;
	logic [NUM_CORES-1:0]         pending_ack_q;
	logic                         any_hit_q;
	logic                         any_dirty_q;

	logic [NUM_CORES-1:0]         next_pending_w;
	logic                         complete_w;

	always_comb begin
		int i;

		next_pending_w = pending_ack_q;

		for (i = 0; i < NUM_CORES; i++) begin
			if (cache_snoop_ack_i[i]) begin
				next_pending_w[i] = 1'b0;
			end
		end

		complete_w = (next_pending_w == '0) && active_q;
	end

	always_ff @(posedge clk_i) begin
		int i;

		if (rst_i) begin
			active_q       <= 1'b0;
			done_q         <= 1'b0;
			source_core_q  <= '0;
			cmd_q          <= SNOOP_NONE;
			addr_q         <= 32'h0;
			pending_ack_q  <= '0;
			any_hit_q      <= 1'b0;
			any_dirty_q    <= 1'b0;
		end
		else begin
			done_q <= 1'b0;

			if (start_i && !active_q) begin
				active_q      <= 1'b1;
				source_core_q <= source_core_i;
				cmd_q         <= cmd_i;
				addr_q        <= addr_i;
				any_hit_q     <= 1'b0;
				any_dirty_q   <= 1'b0;

				for (i = 0; i < NUM_CORES; i++) begin
					pending_ack_q[i] <= (i != source_core_i);
				end
			end
			else if (active_q) begin
				for (i = 0; i < NUM_CORES; i++) begin
					if (cache_snoop_ack_i[i] && pending_ack_q[i]) begin
						if (cache_snoop_hit_i[i]) begin
							any_hit_q <= 1'b1;
						end
						if (cache_snoop_dirty_i[i]) begin
							any_dirty_q <= 1'b1;
						end
					end
				end

				pending_ack_q <= next_pending_w;

				if (complete_w) begin
					active_q <= 1'b0;
					done_q   <= 1'b1;
				end
			end
		end
	end

	always_comb begin
		int i;

		for (i = 0; i < NUM_CORES; i++) begin
			snoop_valid_o[i] = active_q && (i != source_core_q);
			snoop_cmd_o[i]   = cmd_q;
			snoop_addr_o[i]  = addr_q;
		end
	end

	assign busy_o      = active_q;
	assign done_o      = done_q;
	assign any_hit_o   = any_hit_q;
	assign any_dirty_o = any_dirty_q;
	assign ack_seen_o  = ~pending_ack_q;

endmodule