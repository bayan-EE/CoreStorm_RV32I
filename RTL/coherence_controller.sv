`timescale 1ns/1ps


import coherence_pkg::*;

module coherence_controller
#(
	parameter int NUM_CORES  = 4,
	parameter int CORE_IDX_W = (NUM_CORES <= 1) ? 1 : $clog2(NUM_CORES)
)
(
	input  logic                              clk_i,
	input  logic                              rst_i,

	// Requests from per-core dcache/coherence front-end
	input  logic [NUM_CORES-1:0]              coh_req_valid_i,
	input  snoop_cmd_t [NUM_CORES-1:0]        coh_req_cmd_i,
	input  logic [NUM_CORES-1:0][31:0]        coh_req_addr_i,
	output logic [NUM_CORES-1:0]              coh_req_ready_o,

	// Responses from caches to snoop bus
	input  logic [NUM_CORES-1:0]              cache_snoop_hit_i,
	input  logic [NUM_CORES-1:0]              cache_snoop_dirty_i,
	input  logic [NUM_CORES-1:0]              cache_snoop_ack_i,

	// Broadcast snoop outputs to caches
	output logic [NUM_CORES-1:0]              snoop_valid_o,
	output snoop_cmd_t [NUM_CORES-1:0]        snoop_cmd_o,
	output logic [NUM_CORES-1:0][31:0]        snoop_addr_o,

	// Transaction result pulse
	output logic                              trans_done_o,
	output logic [CORE_IDX_W-1:0]            trans_core_o,
	output snoop_cmd_t                        trans_cmd_o,
	output logic [31:0]                       trans_addr_o,
	output logic                              trans_shared_o,
	output logic                              trans_dirty_o,
	output logic                              trans_need_mem_read_o,
	output logic                              trans_need_writeback_o,
	output logic                              busy_o
);

	coh_ctrl_state_t                 state_q;
	logic [CORE_IDX_W-1:0]          grant_core_w;
	logic                            any_req_w;
	logic                            bus_start_w;

	logic [CORE_IDX_W-1:0]          active_core_q;
	snoop_cmd_t                      active_cmd_q;
	logic [31:0]                     active_addr_q;

	logic                            bus_busy_w;
	logic                            bus_done_w;
	logic                            bus_any_hit_w;
	logic                            bus_any_dirty_w;
	logic [NUM_CORES-1:0]            bus_ack_seen_w;

	integer i;

	always_comb begin
		any_req_w    = 1'b0;
		grant_core_w = '0;

		for (i = 0; i < NUM_CORES; i++) begin
			if (!any_req_w && coh_req_valid_i[i]) begin
				any_req_w    = 1'b1;
				grant_core_w = i[CORE_IDX_W-1:0];
			end
		end
	end

	always_comb begin
		coh_req_ready_o = '0;
		bus_start_w     = 1'b0;

		if (state_q == CTRL_IDLE && any_req_w) begin
			coh_req_ready_o[grant_core_w] = 1'b1;
			bus_start_w                   = 1'b1;
		end
	end

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			state_q                 <= CTRL_IDLE;
			active_core_q           <= '0;
			active_cmd_q            <= SNOOP_NONE;
			active_addr_q           <= 32'h0;
			trans_done_o            <= 1'b0;
			trans_core_o            <= '0;
			trans_cmd_o             <= SNOOP_NONE;
			trans_addr_o            <= 32'h0;
			trans_shared_o          <= 1'b0;
			trans_dirty_o           <= 1'b0;
			trans_need_mem_read_o   <= 1'b0;
			trans_need_writeback_o  <= 1'b0;
		end
		else begin
			trans_done_o <= 1'b0;

			case (state_q)
				CTRL_IDLE: begin
					if (bus_start_w) begin
						active_core_q <= grant_core_w;
						active_cmd_q  <= coh_req_cmd_i[grant_core_w];
						active_addr_q <= coh_req_addr_i[grant_core_w];
						state_q       <= CTRL_WAIT;
					end
				end

				CTRL_WAIT: begin
					if (bus_done_w) begin
						trans_done_o   <= 1'b1;
						trans_core_o   <= active_core_q;
						trans_cmd_o    <= active_cmd_q;
						trans_addr_o   <= active_addr_q;
						trans_shared_o <= bus_any_hit_w | bus_any_dirty_w;
						trans_dirty_o  <= bus_any_dirty_w;

						if (active_cmd_q == SNOOP_BUSUPGR) begin
							trans_need_mem_read_o  <= 1'b0;
						end
						else begin
							trans_need_mem_read_o  <= ~bus_any_dirty_w;
						end

						trans_need_writeback_o <= bus_any_dirty_w;
						state_q                <= CTRL_IDLE;
					end
				end

				default: begin
					state_q <= CTRL_IDLE;
				end
			endcase
		end
	end

	snoop_bus #(
		.NUM_CORES(NUM_CORES)
	) u_snoop_bus (
		.clk_i               (clk_i),
		.rst_i               (rst_i),
		.start_i             (bus_start_w),
		.source_core_i       (grant_core_w),
		.cmd_i               (coh_req_cmd_i[grant_core_w]),
		.addr_i              (coh_req_addr_i[grant_core_w]),
		.cache_snoop_hit_i   (cache_snoop_hit_i),
		.cache_snoop_dirty_i (cache_snoop_dirty_i),
		.cache_snoop_ack_i   (cache_snoop_ack_i),
		.snoop_valid_o       (snoop_valid_o),
		.snoop_cmd_o         (snoop_cmd_o),
		.snoop_addr_o        (snoop_addr_o),
		.busy_o              (bus_busy_w),
		.done_o              (bus_done_w),
		.any_hit_o           (bus_any_hit_w),
		.any_dirty_o         (bus_any_dirty_w),
		.ack_seen_o          (bus_ack_seen_w)
	);

	assign busy_o = (state_q != CTRL_IDLE) | bus_busy_w;

endmodule