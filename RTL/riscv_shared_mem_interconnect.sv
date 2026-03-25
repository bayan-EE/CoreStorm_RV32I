`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// RISC-V Shared Memory Interconnect
// -----------------------------------------------------------------------------
// This module provides a simple interconnect layer between multiple CPU cores
// and a shared memory subsystem.
//
// Main functionality:
// - Each core presents a standard memory request interface.
// - The interconnect decodes the request address.
// - Requests that fall inside the shared-memory address window are forwarded
//   to the shared memory block.
// - Requests outside the supported address window are completed locally with
//   an error response.
// - One response is returned to the requesting core, including the original tag.
//
// Current design scope:
// - Single shared-memory target
// - Address-range decode
// - Pass-through request/response routing
// - Local error generation for unmapped addresses
//
// Design intent:
// - Keep the first interconnect stage simple and deterministic.
// - Provide a clean integration point between multi-core CPU request ports
//   and the shared memory module.
// - Establish a structure that can later be extended with:
//     * local memory regions
//     * MMIO / peripheral regions
//     * multiple downstream targets
//     * arbitration between multiple memory banks
//     * cache coherence or snoop support
//
// Notes:
// - The shared memory itself is responsible for arbitration between ports.
// - This interconnect mainly performs decode, routing, and error handling.
// - Invalid accesses are accepted immediately and return an error response
//   after one cycle.
// -----------------------------------------------------------------------------

module riscv_shared_mem_interconnect #(
	parameter int NUM_PORTS   = 4,
	parameter int ADDR_WIDTH  = 32,
	parameter int DATA_WIDTH  = 32,
	parameter int STRB_WIDTH  = DATA_WIDTH / 8,
	parameter int TAG_WIDTH   = 11,
	parameter int MEM_BYTES   = 64 * 1024,
	parameter int MEM_LATENCY = 2,
	parameter logic [ADDR_WIDTH-1:0] SHARED_BASE_ADDR = 32'h1000_0000
)(
	input  logic                                 clk_i,
	input  logic                                 rst_i,

	// -------------------------------------------------------------------------
	// Per-core request channel
	// -------------------------------------------------------------------------
	input  logic [NUM_PORTS-1:0]                 req_valid_i,
	input  logic [NUM_PORTS-1:0]                 req_write_i,
	input  logic [NUM_PORTS-1:0][ADDR_WIDTH-1:0] req_addr_i,
	input  logic [NUM_PORTS-1:0][DATA_WIDTH-1:0] req_wdata_i,
	input  logic [NUM_PORTS-1:0][STRB_WIDTH-1:0] req_wstrb_i,
	input  logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]  req_tag_i,
	output logic [NUM_PORTS-1:0]                 req_accept_o,

	// -------------------------------------------------------------------------
	// Per-core response channel
	// -------------------------------------------------------------------------
	output logic [NUM_PORTS-1:0]                 resp_valid_o,
	output logic [NUM_PORTS-1:0][DATA_WIDTH-1:0] resp_rdata_o,
	output logic [NUM_PORTS-1:0]                 resp_error_o,
	output logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]  resp_tag_o
);

	localparam int PORT_IDX_W = (NUM_PORTS <= 1) ? 1 : $clog2(NUM_PORTS);

	// -------------------------------------------------------------------------
	// Address decode helpers
	// -------------------------------------------------------------------------
	logic [NUM_PORTS-1:0]                 dec_shared_w;
	logic [NUM_PORTS-1:0]                 dec_invalid_w;

	// -------------------------------------------------------------------------
	// Shared memory routed signals
	// -------------------------------------------------------------------------
	logic [NUM_PORTS-1:0]                 shm_req_valid_w;
	logic [NUM_PORTS-1:0]                 shm_req_write_w;
	logic [NUM_PORTS-1:0][ADDR_WIDTH-1:0] shm_req_addr_w;
	logic [NUM_PORTS-1:0][DATA_WIDTH-1:0] shm_req_wdata_w;
	logic [NUM_PORTS-1:0][STRB_WIDTH-1:0] shm_req_wstrb_w;
	logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]  shm_req_tag_w;
	logic [NUM_PORTS-1:0]                 shm_req_accept_w;

	logic [NUM_PORTS-1:0]                 shm_resp_valid_w;
	logic [NUM_PORTS-1:0][DATA_WIDTH-1:0] shm_resp_rdata_w;
	logic [NUM_PORTS-1:0]                 shm_resp_error_w;
	logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]  shm_resp_tag_w;

	// -------------------------------------------------------------------------
	// One-cycle local error response path for unmapped addresses
	// -------------------------------------------------------------------------
	logic [NUM_PORTS-1:0]                 err_pending_q;
	logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]  err_tag_q;
	logic [NUM_PORTS-1:0]                 port_busy_q;

	// -------------------------------------------------------------------------
	// Address decode function
	// -------------------------------------------------------------------------
	function automatic logic addr_in_shared_range(
		input logic [ADDR_WIDTH-1:0] addr
	);
		logic [ADDR_WIDTH:0] lo_addr;
		logic [ADDR_WIDTH:0] hi_addr;
		logic [ADDR_WIDTH:0] end_addr;
		begin
			lo_addr  = {1'b0, addr};
			hi_addr  = {1'b0, SHARED_BASE_ADDR};
			end_addr = {1'b0, SHARED_BASE_ADDR} + MEM_BYTES - 1;

			addr_in_shared_range = ((lo_addr >= hi_addr) &&
									((lo_addr + 3) <= end_addr));
		end
	endfunction

	// -------------------------------------------------------------------------
	// Decode and routing
	// -------------------------------------------------------------------------
	always_comb begin
		dec_shared_w  = '0;
		dec_invalid_w = '0;

		shm_req_valid_w = '0;
		shm_req_write_w = '0;
		shm_req_addr_w  = '0;
		shm_req_wdata_w = '0;
		shm_req_wstrb_w = '0;
		shm_req_tag_w   = '0;

		req_accept_o    = '0;

		for (int p = 0; p < NUM_PORTS; p++) begin
			if (req_valid_i[p] && !port_busy_q[p]) begin
				if (addr_in_shared_range(req_addr_i[p])) begin
					dec_shared_w[p]    = 1'b1;

					shm_req_valid_w[p] = 1'b1;
					shm_req_write_w[p] = req_write_i[p];
					shm_req_addr_w[p]  = req_addr_i[p];
					shm_req_wdata_w[p] = req_wdata_i[p];
					shm_req_wstrb_w[p] = req_wstrb_i[p];
					shm_req_tag_w[p]   = req_tag_i[p];

					req_accept_o[p]    = shm_req_accept_w[p];
				end
				else begin
					dec_invalid_w[p] = 1'b1;
					req_accept_o[p]  = !err_pending_q[p];
				end
			end
		end
	end

	// -------------------------------------------------------------------------
	// Shared memory instance
	// -------------------------------------------------------------------------
	shared_memory_multi #(
		.NUM_PORTS   (NUM_PORTS),
		.ADDR_WIDTH  (ADDR_WIDTH),
		.DATA_WIDTH  (DATA_WIDTH),
		.STRB_WIDTH  (STRB_WIDTH),
		.TAG_WIDTH   (TAG_WIDTH),
		.MEM_BYTES   (MEM_BYTES),
		.MEM_LATENCY (MEM_LATENCY),
		.BASE_ADDR   (SHARED_BASE_ADDR)
	) u_shared_memory_multi (
		.clk_i        (clk_i),
		.rst_i        (rst_i),
		.req_valid_i  (shm_req_valid_w),
		.req_write_i  (shm_req_write_w),
		.req_addr_i   (shm_req_addr_w),
		.req_wdata_i  (shm_req_wdata_w),
		.req_wstrb_i  (shm_req_wstrb_w),
		.req_tag_i    (shm_req_tag_w),
		.req_accept_o (shm_req_accept_w),
		.resp_valid_o (shm_resp_valid_w),
		.resp_rdata_o (shm_resp_rdata_w),
		.resp_error_o (shm_resp_error_w),
		.resp_tag_o   (shm_resp_tag_w)
	);

	// -------------------------------------------------------------------------
	// Local error-response tracking
	// -------------------------------------------------------------------------
	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			err_pending_q <= '0;
			err_tag_q     <= '0;
			port_busy_q   <= '0;
		end
		else begin
			for (int p = 0; p < NUM_PORTS; p++) begin
				// Clear busy once a response is actually issued on this port
				if (resp_valid_o[p]) begin
					port_busy_q[p] <= 1'b0;
				end

				// Clear local error pending after it is emitted
				if (err_pending_q[p]) begin
					err_pending_q[p] <= 1'b0;
				end

				// Accepted invalid request
				if (req_valid_i[p] && dec_invalid_w[p] && req_accept_o[p]) begin
					err_pending_q[p] <= 1'b1;
					err_tag_q[p]     <= req_tag_i[p];
					port_busy_q[p]   <= 1'b1;
				end

				// Accepted shared-memory request
				if (req_valid_i[p] && dec_shared_w[p] && req_accept_o[p]) begin
					port_busy_q[p] <= 1'b1;
				end
			end
		end
	end

	// -------------------------------------------------------------------------
	// Final response mux
	// Priority:
	//   1) Local unmapped-address error response
	//   2) Shared memory response
	// -------------------------------------------------------------------------
	always_comb begin
		resp_valid_o = '0;
		resp_rdata_o = '0;
		resp_error_o = '0;
		resp_tag_o   = '0;

		for (int p = 0; p < NUM_PORTS; p++) begin
			if (err_pending_q[p]) begin
				resp_valid_o[p] = 1'b1;
				resp_rdata_o[p] = '0;
				resp_error_o[p] = 1'b1;
				resp_tag_o[p]   = err_tag_q[p];
			end
			else if (shm_resp_valid_w[p]) begin
				resp_valid_o[p] = shm_resp_valid_w[p];
				resp_rdata_o[p] = shm_resp_rdata_w[p];
				resp_error_o[p] = shm_resp_error_w[p];
				resp_tag_o[p]   = shm_resp_tag_w[p];
			end
		end
	end

endmodule