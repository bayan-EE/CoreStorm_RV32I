`timescale 1ns/1ps
module icache
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
	parameter int unsigned AXI_ID = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
	// Inputs
	input  logic         clk_i,
	input  logic         rst_i,              // NOTE: Active-high async reset (as in original)
	input  logic         req_rd_i,
	input  logic         req_flush_i,
	input  logic         req_invalidate_i,
	input  logic [31:0]  req_pc_i,

	// AXI (inputs)
	input  logic         axi_awready_i,
	input  logic         axi_wready_i,
	input  logic         axi_bvalid_i,
	input  logic [1:0]   axi_bresp_i,
	input  logic [3:0]   axi_bid_i,
	input  logic         axi_arready_i,
	input  logic         axi_rvalid_i,
	input  logic [31:0]  axi_rdata_i,
	input  logic [1:0]   axi_rresp_i,
	input  logic [3:0]   axi_rid_i,
	input  logic         axi_rlast_i,

	// Outputs
	output logic         req_accept_o,       // "ready/accept" for req_rd_i
	output logic         req_valid_o,        // instruction valid (cache hit)
	output logic         req_error_o,        // latched AXI error for this request
	output logic [63:0]  req_inst_o,         // 2x32b words packed into 64b (line word)
	output logic         axi_awvalid_o,
	output logic [31:0]  axi_awaddr_o,
	output logic [3:0]   axi_awid_o,
	output logic [7:0]   axi_awlen_o,
	output logic [1:0]   axi_awburst_o,
	output logic         axi_wvalid_o,
	output logic [31:0]  axi_wdata_o,
	output logic [3:0]   axi_wstrb_o,
	output logic         axi_wlast_o,
	output logic         axi_bready_o,
	output logic         axi_arvalid_o,
	output logic [31:0]  axi_araddr_o,
	output logic [3:0]   axi_arid_o,
	output logic [7:0]   axi_arlen_o,
	output logic [1:0]   axi_arburst_o,
	output logic         axi_rready_o
);

	//-----------------------------------------------------------------
	// This cache instance is 2-way set associative.
	// Total size ~16KB, line size 32B, 256 lines (per way).
	// Replacement policy: simple toggling between ways (pseudo-random).
	//-----------------------------------------------------------------

	localparam int unsigned ICACHE_NUM_WAYS       = 2;

	localparam int unsigned ICACHE_NUM_LINES      = 256;
	localparam int unsigned ICACHE_LINE_ADDR_W    = 8;

	localparam int unsigned ICACHE_LINE_SIZE_W    = 5;   // 2^5 = 32 bytes per line
	localparam int unsigned ICACHE_LINE_SIZE      = 32;
	localparam int unsigned ICACHE_LINE_WORDS     = 8;   // 8x32b words per line

	localparam int unsigned ICACHE_DATA_W         = 64;

	// Request -> tag address mapping (line index inside cache)
	localparam int unsigned ICACHE_TAG_REQ_LINE_L = 5;   // offset bits [4:0] are inside line
	localparam int unsigned ICACHE_TAG_REQ_LINE_H = 12;  // 8 bits line index -> [12:5]
	localparam int unsigned ICACHE_TAG_REQ_LINE_W = 8;

	`define ICACHE_TAG_REQ_RNG    ICACHE_TAG_REQ_LINE_H:ICACHE_TAG_REQ_LINE_L

	// Tag fields stored in tag RAM
	// We store: {valid, tag_addr_bits}
	`define CACHE_TAG_ADDR_RNG    18:0
	localparam int unsigned CACHE_TAG_ADDR_BITS   = 19;
	localparam int unsigned CACHE_TAG_VALID_BIT   = CACHE_TAG_ADDR_BITS;
	localparam int unsigned CACHE_TAG_DATA_W      = CACHE_TAG_VALID_BIT + 1;

	// Tag compare bits from PC: req_pc_tag_cmp_w == PC[31:13]
	localparam int unsigned ICACHE_TAG_CMP_ADDR_L = ICACHE_TAG_REQ_LINE_H + 1; // 13
	localparam int unsigned ICACHE_TAG_CMP_ADDR_H = 31;
	localparam int unsigned ICACHE_TAG_CMP_ADDR_W = ICACHE_TAG_CMP_ADDR_H - ICACHE_TAG_CMP_ADDR_L + 1;
	`define ICACHE_TAG_CMP_ADDR_RNG  31:13

	// Tag addressing and match value
	logic [ICACHE_TAG_REQ_LINE_W-1:0] req_line_addr_w;
	assign req_line_addr_w = req_pc_i[`ICACHE_TAG_REQ_RNG];

	// Data addressing: word select inside line (address >> 3 because data RAM is 64-bit)
	localparam int unsigned CACHE_DATA_ADDR_W = ICACHE_LINE_ADDR_W + ICACHE_LINE_SIZE_W - 3;
	logic [CACHE_DATA_ADDR_W-1:0] req_data_addr_w;
	assign req_data_addr_w = req_pc_i[CACHE_DATA_ADDR_W+3-1:3];

	//-----------------------------------------------------------------
	// FSM (states)
	//-----------------------------------------------------------------
	typedef enum logic [1:0] {
		STATE_FLUSH    = 2'd0,
		STATE_LOOKUP   = 2'd1,
		STATE_REFILL   = 2'd2,
		STATE_RELOOKUP = 2'd3
	} state_e;

	state_e state_q, next_state_r;

	//-----------------------------------------------------------------
	// Registers / Wires
	//-----------------------------------------------------------------
	logic        invalidate_q;
	logic [0:0]  replace_way_q;   // toggles 0/1 on each completed refill

	//-----------------------------------------------------------------
	// Lookup validation
	//-----------------------------------------------------------------
	logic lookup_valid_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			lookup_valid_q <= 1'b0;
		end
		else if (req_rd_i && req_accept_o) begin
			// Latch that we have an outstanding lookup request
			lookup_valid_q <= 1'b1;
		end
		else if (req_valid_o) begin
			// Clear when we successfully produce an instruction (hit)
			lookup_valid_q <= 1'b0;
		end
	end

	//-----------------------------------------------------------------
	// Lookup address
	//-----------------------------------------------------------------
	logic [31:0] lookup_addr_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			lookup_addr_q <= 32'b0;
		end
		else if (req_rd_i && req_accept_o) begin
			// Hold the PC of the accepted request (used through refill/relookup)
			lookup_addr_q <= req_pc_i;
		end
	end

	logic [ICACHE_TAG_CMP_ADDR_W-1:0] req_pc_tag_cmp_w;
	assign req_pc_tag_cmp_w = lookup_addr_q[`ICACHE_TAG_CMP_ADDR_RNG];

	//-----------------------------------------------------------------
	// TAG RAMS
	//-----------------------------------------------------------------
	logic [ICACHE_TAG_REQ_LINE_W-1:0] tag_addr_r;
	logic [CACHE_TAG_DATA_W-1:0]      tag_data_in_r;
	logic                             tag0_write_r, tag1_write_r;
	logic [CACHE_TAG_DATA_W-1:0]      tag0_data_out_w, tag1_data_out_w;

	// Flush counter (also used as tag RAM address in flush mode)
	logic [ICACHE_TAG_REQ_LINE_W-1:0] flush_addr_q;

	// Tag RAM address selection
	always_comb begin
		// Default
		tag_addr_r = flush_addr_q;

		if (state_q == STATE_FLUSH) begin
			// During FLUSH: sweep all lines (or single line invalidation)
			tag_addr_r = flush_addr_q;
		end
		else if (state_q == STATE_REFILL || state_q == STATE_RELOOKUP) begin
			// During REFILL/RELOOKUP: access the line of the original lookup_addr_q
			tag_addr_r = lookup_addr_q[`ICACHE_TAG_REQ_RNG];
		end
		else begin
			// During LOOKUP: use current request PC line index
			tag_addr_r = req_line_addr_w;
		end
	end

	// Tag RAM write data
	always_comb begin
		tag_data_in_r = '0;

		if (state_q == STATE_FLUSH) begin
			// FLUSH clears valid bits for all lines
			tag_data_in_r = '0;
		end
		else if (state_q == STATE_REFILL) begin
			// REFILL writes: mark valid and store the tag bits from lookup address
			tag_data_in_r[CACHE_TAG_VALID_BIT]   = 1'b1;
			tag_data_in_r[`CACHE_TAG_ADDR_RNG]   = lookup_addr_q[`ICACHE_TAG_CMP_ADDR_RNG];
		end
	end

	// Tag write enables (per way)
	always_comb begin
		tag0_write_r = 1'b0;

		if (state_q == STATE_FLUSH) begin
			// Write zeros to invalidate way0 tag lines
			tag0_write_r = 1'b1;
		end
		else if (state_q == STATE_REFILL) begin
			// Write tag only on last beat of AXI burst, and only for selected replacement way
			tag0_write_r = axi_rvalid_i && axi_rlast_i && (replace_way_q == 1'b0);
		end
	end

	always_comb begin
		tag1_write_r = 1'b0;

		if (state_q == STATE_FLUSH) begin
			// Write zeros to invalidate way1 tag lines
			tag1_write_r = 1'b1;
		end
		else if (state_q == STATE_REFILL) begin
			tag1_write_r = axi_rvalid_i && axi_rlast_i && (replace_way_q == 1'b1);
		end
	end

	// Tag RAM instances (external modules)
	icache_tag_ram u_tag0 (
		.clk_i (clk_i),
		.rst_i (rst_i),
		.addr_i(tag_addr_r),
		.data_i(tag_data_in_r),
		.wr_i  (tag0_write_r),
		.data_o(tag0_data_out_w)
	);

	icache_tag_ram u_tag1 (
		.clk_i (clk_i),
		.rst_i (rst_i),
		.addr_i(tag_addr_r),
		.data_i(tag_data_in_r),
		.wr_i  (tag1_write_r),
		.data_o(tag1_data_out_w)
	);

	// Extract tag fields and perform compare
	logic                           tag0_valid_w, tag1_valid_w;
	logic [CACHE_TAG_ADDR_BITS-1:0] tag0_addr_bits_w, tag1_addr_bits_w;

	assign tag0_valid_w     = tag0_data_out_w[CACHE_TAG_VALID_BIT];
	assign tag0_addr_bits_w = tag0_data_out_w[`CACHE_TAG_ADDR_RNG];

	assign tag1_valid_w     = tag1_data_out_w[CACHE_TAG_VALID_BIT];
	assign tag1_addr_bits_w = tag1_data_out_w[`CACHE_TAG_ADDR_RNG];

	// Tag hit? (valid && tag == PC_tag)
	logic tag0_hit_w, tag1_hit_w;
	assign tag0_hit_w = tag0_valid_w ? (tag0_addr_bits_w == req_pc_tag_cmp_w) : 1'b0;
	assign tag1_hit_w = tag1_valid_w ? (tag1_addr_bits_w == req_pc_tag_cmp_w) : 1'b0;

	logic tag_hit_any_w;
	assign tag_hit_any_w = tag0_hit_w | tag1_hit_w;

	//-----------------------------------------------------------------
	// DATA RAMS
	//-----------------------------------------------------------------
	logic [CACHE_DATA_ADDR_W-1:0] data_addr_r;
	logic [CACHE_DATA_ADDR_W-1:0] data_write_addr_q;
	logic [2:0]                   refill_word_idx_q;
	logic [31:0]                  refill_lower_q;

	// Track which 32b beat we are on during AXI burst
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			refill_word_idx_q <= 3'b0;
		end
		else if (axi_rvalid_i && axi_rlast_i) begin
			refill_word_idx_q <= 3'b0; // reset at end of burst
		end
		else if (axi_rvalid_i) begin
			refill_word_idx_q <= refill_word_idx_q + 3'd1;
		end
	end

	// Hold lower 32 bits to assemble 64-bit write data (two beats -> one 64b word)
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			refill_lower_q <= 32'b0;
		end
		else if (axi_rvalid_i) begin
			refill_lower_q <= axi_rdata_i;
		end
	end

	// Data RAM refill write address
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			data_write_addr_q <= '0;
		end
		else if (state_q == STATE_LOOKUP && next_state_r == STATE_REFILL) begin
			// Capture aligned line base for refill writes
			data_write_addr_q <= axi_araddr_o[CACHE_DATA_ADDR_W+3-1:3];
		end
		else if (state_q == STATE_REFILL && axi_rvalid_i && refill_word_idx_q[0]) begin
			// Increment address every 2 beats (since we pack 2x32b into 1x64b)
			data_write_addr_q <= data_write_addr_q + 1'b1;
		end
	end

	// Data RAM address selection
	always_comb begin
		data_addr_r = req_data_addr_w;

		if (state_q == STATE_REFILL) begin
			// During refill: write sequential 64b words into the line
			data_addr_r = data_write_addr_q;
		end
		else if (state_q == STATE_RELOOKUP) begin
			// After refill: read using the original lookup address
			data_addr_r = lookup_addr_q[CACHE_DATA_ADDR_W+3-1:3];
		end
		else begin
			// Normal lookup: address based on current req_pc_i
			data_addr_r = req_data_addr_w;
		end
	end

	logic                  data0_write_r, data1_write_r;
	logic [ICACHE_DATA_W-1:0] data0_data_out_w, data1_data_out_w;

	// Data RAM write enable (per way) - write on every valid beat
	always_comb begin
		data0_write_r = axi_rvalid_i && (replace_way_q == 1'b0);
		data1_write_r = axi_rvalid_i && (replace_way_q == 1'b1);
	end

	icache_data_ram u_data0 (
		.clk_i (clk_i),
		.rst_i (rst_i),
		.addr_i(data_addr_r),
		.data_i({axi_rdata_i, refill_lower_q}), // NOTE: packs current beat + previous beat into 64b
		.wr_i  (data0_write_r),
		.data_o(data0_data_out_w)
	);

	icache_data_ram u_data1 (
		.clk_i (clk_i),
		.rst_i (rst_i),
		.addr_i(data_addr_r),
		.data_i({axi_rdata_i, refill_lower_q}),
		.wr_i  (data1_write_r),
		.data_o(data1_data_out_w)
	);

	//-----------------------------------------------------------------
	// Flush counter / invalidate line selection
	//-----------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			flush_addr_q <= '0;
		end
		else if (state_q == STATE_FLUSH) begin
			// Sweep through all line indices during FLUSH
			flush_addr_q <= flush_addr_q + 1'b1;
		end
		else if (req_invalidate_i && req_accept_o) begin
			// Single-line invalidate: point flush address to that line
			flush_addr_q <= req_line_addr_w;
		end
		else begin
			flush_addr_q <= '0;
		end
	end

	//-----------------------------------------------------------------
	// Replacement Policy (toggle way after each completed refill)
	//-----------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			replace_way_q <= 1'b0;
		end
		else if (axi_rvalid_i && axi_rlast_i) begin
			// Toggle way at end of AXI burst refill
			replace_way_q <= replace_way_q + 1'b1;
		end
	end

	//-----------------------------------------------------------------
	// Instruction Output
	//-----------------------------------------------------------------
	// req_valid_o asserts ONLY on cache hit in LOOKUP state for the latched request
	assign req_valid_o = lookup_valid_q && ((state_q == STATE_LOOKUP) ? tag_hit_any_w : 1'b0);

	// Data output mux: select data from the way that hit
	logic [ICACHE_DATA_W-1:0] inst_r;

	always_comb begin
		inst_r = data0_data_out_w;

		// NOTE: If both hit (should not happen unless tag aliasing/bug), priority is way0 then way1
		unique case (1'b1)
			tag0_hit_w: inst_r = data0_data_out_w;
			tag1_hit_w: inst_r = data1_data_out_w;
			default:    inst_r = data0_data_out_w;
		endcase
	end

	assign req_inst_o = inst_r;

	//-----------------------------------------------------------------
	// Next State Logic
	//-----------------------------------------------------------------
	always_comb begin
		next_state_r = state_q;

		unique case (state_q)
			// ---------------------------------------------------------
			// STATE_FLUSH
			// ---------------------------------------------------------
			STATE_FLUSH: begin
				// NOTE: invalidate_q indicates a single-line invalidate request;
				// otherwise we sweep full cache and then return to LOOKUP.
				if (invalidate_q) begin
					next_state_r = STATE_LOOKUP;
				end
				else if (flush_addr_q == {ICACHE_TAG_REQ_LINE_W{1'b1}}) begin
					next_state_r = STATE_LOOKUP;
				end
			end

			// ---------------------------------------------------------
			// STATE_LOOKUP
			// ---------------------------------------------------------
			STATE_LOOKUP: begin
				// Miss for an accepted lookup -> go refill line via AXI
				if (lookup_valid_q && !tag_hit_any_w) begin
					next_state_r = STATE_REFILL;
				end
				// Flush or invalidate requests -> go to FLUSH state
				else if (req_invalidate_i || req_flush_i) begin
					next_state_r = STATE_FLUSH;
				end
			end

			// ---------------------------------------------------------
			// STATE_REFILL
			// ---------------------------------------------------------
			STATE_REFILL: begin
				// Wait for last beat of burst to complete refill
				if (axi_rvalid_i && axi_rlast_i) begin
					next_state_r = STATE_RELOOKUP;
				end
			end

			// ---------------------------------------------------------
			// STATE_RELOOKUP
			// ---------------------------------------------------------
			STATE_RELOOKUP: begin
				// One-cycle state to re-access SRAMs after refill
				next_state_r = STATE_LOOKUP;
			end

			default: begin
				next_state_r = STATE_FLUSH;
			end
		endcase
	end

	// Update state
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			state_q <= STATE_FLUSH; // NOTE: start by flushing tags (invalidating cache)
		end
		else begin
			state_q <= next_state_r;
		end
	end

	// Accept new request only when LOOKUP and not transitioning into REFILL
	// (i.e., ready when we won't start an AXI refill this cycle)
	assign req_accept_o = (state_q == STATE_LOOKUP) && (next_state_r != STATE_REFILL);

	//-----------------------------------------------------------------
	// Invalidate (one-cycle pulse remembered for FLUSH exit)
	//-----------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			invalidate_q <= 1'b0;
		end
		else if (req_invalidate_i && req_accept_o) begin
			// NOTE: latch "single line invalidate" intent; used in STATE_FLUSH
			invalidate_q <= 1'b1;
		end
		else begin
			invalidate_q <= 1'b0;
		end
	end

	//-----------------------------------------------------------------
	// AXI ARVALID hold (keep asserted until ARREADY handshake)
	//-----------------------------------------------------------------
	logic axi_arvalid_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			axi_arvalid_q <= 1'b0;
		end
		else if (axi_arvalid_o && !axi_arready_i) begin
			// NOTE: if we raised ARVALID but slave not ready, hold it for next cycles
			axi_arvalid_q <= 1'b1;
		end
		else begin
			axi_arvalid_q <= 1'b0;
		end
	end

	//-----------------------------------------------------------------
	// AXI Error Handling
	//-----------------------------------------------------------------
	logic axi_error_q;

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			axi_error_q <= 1'b0;
		end
		else if (axi_rvalid_i && axi_rready_o && (axi_rresp_i != 2'b00)) begin
			// NOTE: latch first AXI read error response until request completes
			axi_error_q <= 1'b1;
		end
		else if (req_valid_o) begin
			// Clear error when we return a valid instruction to core
			axi_error_q <= 1'b0;
		end
	end

	assign req_error_o = axi_error_q;

	//-----------------------------------------------------------------
	// AXI
	//-----------------------------------------------------------------
	// AXI Write channel (unused by I-cache)
	assign axi_awvalid_o = 1'b0;
	assign axi_awaddr_o  = 32'b0;
	assign axi_awid_o    = 4'b0;
	assign axi_awlen_o   = 8'b0;
	assign axi_awburst_o = 2'b0;
	assign axi_wvalid_o  = 1'b0;
	assign axi_wdata_o   = 32'b0;
	assign axi_wstrb_o   = 4'b0;
	assign axi_wlast_o   = 1'b0;
	assign axi_bready_o  = 1'b0;

	// AXI Read channel
	assign axi_arvalid_o = ((state_q == STATE_LOOKUP) && (next_state_r == STATE_REFILL)) || axi_arvalid_q;

	// NOTE: align address down to cache line boundary (zero out line offset bits)
	assign axi_araddr_o  = {lookup_addr_q[31:ICACHE_LINE_SIZE_W], {ICACHE_LINE_SIZE_W{1'b0}}};

	// INCR burst: 8 beats of 32-bit -> 32 bytes line
	assign axi_arburst_o = 2'd1;
	assign axi_arid_o    = AXI_ID[3:0];
	assign axi_arlen_o   = 8'd7;   // 8 beats (0..7)
	assign axi_rready_o  = 1'b1;   // Always ready to accept read data (simple design)

endmodule