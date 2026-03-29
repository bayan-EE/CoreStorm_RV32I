`timescale 1ns/1ps

module shared_l2_cache_single
#(
	parameter int ADDR_W  = 32,
	parameter int LINE_W  = 256,
	parameter int SETS    = 64,
	parameter int OFFSET_W = 5,
	parameter int IDX_W    = (SETS <= 1) ? 1 : $clog2(SETS),
	parameter int TAG_W    = ADDR_W - OFFSET_W - IDX_W,
	parameter int BE_W     = LINE_W / 8
)
(
	input  logic                 clk_i,
	input  logic                 rst_i,

	input  logic                 req_valid_i,
	output logic                 req_ready_o,
	input  logic                 req_we_i,
	input  logic [ADDR_W-1:0]    req_addr_i,
	input  logic [LINE_W-1:0]    req_wdata_i,
	input  logic [BE_W-1:0]      req_wmask_i,

	output logic                 resp_valid_o,
	output logic                 resp_hit_o,
	output logic [LINE_W-1:0]    resp_rdata_o
);

	typedef enum logic [0:0] {
		ST_IDLE   = 1'b0,
		ST_LOOKUP = 1'b1
	} state_t;

	state_t state_q, state_d;

	logic [ADDR_W-1:0] req_addr_q;
	logic              req_we_q;
	logic [LINE_W-1:0] req_wdata_q;
	logic [BE_W-1:0]   req_wmask_q;

	logic [IDX_W-1:0] req_idx_q;
	logic [TAG_W-1:0] req_tag_q;

	logic                 data_en_w;
	logic                 data_wr_w;
	logic [IDX_W-1:0]     data_addr_w;
	logic [LINE_W-1:0]    data_wdata_w;
	logic [BE_W-1:0]      data_wstrb_w;
	logic [LINE_W-1:0]    data_rdata_w;

	logic                 tag_en_w;
	logic                 tag_wr_w;
	logic [IDX_W-1:0]     tag_addr_w;
	logic [TAG_W-1:0]     tag_wtag_w;
	logic                 tag_wvalid_w;
	logic                 tag_wdirty_w;
	logic [TAG_W-1:0]     tag_rtag_w;
	logic                 tag_rvalid_w;
	logic                 tag_rdirty_w;

	logic                 lookup_hit_w;
	logic [LINE_W-1:0]    write_line_w;

	function automatic [LINE_W-1:0] apply_wmask(
		input [LINE_W-1:0] old_line,
		input [LINE_W-1:0] new_line,
		input [BE_W-1:0]   wmask
	);
		automatic logic [LINE_W-1:0] tmp;
		int i;
		begin
			tmp = old_line;
			for (i = 0; i < BE_W; i++) begin
				if (wmask[i]) begin
					tmp[8*i +: 8] = new_line[8*i +: 8];
				end
			end
			return tmp;
		end
	endfunction

	assign lookup_hit_w  = tag_rvalid_w && (tag_rtag_w == req_tag_q);
	assign write_line_w  = apply_wmask(lookup_hit_w ? data_rdata_w : '0, req_wdata_q, req_wmask_q);

	assign req_ready_o = (state_q == ST_IDLE);

	always_comb begin
		state_d = state_q;

		data_en_w    = 1'b0;
		data_wr_w    = 1'b0;
		data_addr_w  = '0;
		data_wdata_w = '0;
		data_wstrb_w = '0;

		tag_en_w     = 1'b0;
		tag_wr_w     = 1'b0;
		tag_addr_w   = '0;
		tag_wtag_w   = '0;
		tag_wvalid_w = 1'b0;
		tag_wdirty_w = 1'b0;

		case (state_q)
			ST_IDLE: begin
				if (req_valid_i) begin
					data_en_w   = 1'b1;
					data_wr_w   = 1'b0;
					data_addr_w = req_addr_i[OFFSET_W + IDX_W - 1 : OFFSET_W];

					tag_en_w    = 1'b1;
					tag_wr_w    = 1'b0;
					tag_addr_w  = req_addr_i[OFFSET_W + IDX_W - 1 : OFFSET_W];

					state_d     = ST_LOOKUP;
				end
			end

			ST_LOOKUP: begin
				if (req_we_q) begin
					data_en_w    = 1'b1;
					data_wr_w    = 1'b1;
					data_addr_w  = req_idx_q;
					data_wdata_w = write_line_w;
					data_wstrb_w = {BE_W{1'b1}};

					tag_en_w     = 1'b1;
					tag_wr_w     = 1'b1;
					tag_addr_w   = req_idx_q;
					tag_wtag_w   = req_tag_q;
					tag_wvalid_w = 1'b1;
					tag_wdirty_w = 1'b1;
				end

				state_d = ST_IDLE;
			end

			default: begin
				state_d = ST_IDLE;
			end
		endcase
	end

	l2_data_ram #(
		.DATA_W (LINE_W),
		.DEPTH  (SETS)
	) u_data_ram (
		.clk_i   (clk_i),
		.rst_i   (rst_i),
		.en_i    (data_en_w),
		.wr_i    (data_wr_w),
		.addr_i  (data_addr_w),
		.wdata_i (data_wdata_w),
		.wstrb_i (data_wstrb_w),
		.rdata_o (data_rdata_w)
	);

	l2_tag_ram #(
		.TAG_W (TAG_W),
		.DEPTH (SETS)
	) u_tag_ram (
		.clk_i   (clk_i),
		.rst_i   (rst_i),
		.en_i    (tag_en_w),
		.wr_i    (tag_wr_w),
		.addr_i  (tag_addr_w),
		.tag_i   (tag_wtag_w),
		.valid_i (tag_wvalid_w),
		.dirty_i (tag_wdirty_w),
		.tag_o   (tag_rtag_w),
		.valid_o (tag_rvalid_w),
		.dirty_o (tag_rdirty_w)
	);

	always_ff @(posedge clk_i) begin
		if (rst_i) begin
			state_q      <= ST_IDLE;
			req_addr_q   <= '0;
			req_we_q     <= 1'b0;
			req_wdata_q  <= '0;
			req_wmask_q  <= '0;
			req_idx_q    <= '0;
			req_tag_q    <= '0;

			resp_valid_o <= 1'b0;
			resp_hit_o   <= 1'b0;
			resp_rdata_o <= '0;
		end
		else begin
			state_q <= state_d;

			resp_valid_o <= 1'b0;

			if (state_q == ST_IDLE && req_valid_i) begin
				req_addr_q  <= req_addr_i;
				req_we_q    <= req_we_i;
				req_wdata_q <= req_wdata_i;
				req_wmask_q <= req_wmask_i;
				req_idx_q   <= req_addr_i[OFFSET_W + IDX_W - 1 : OFFSET_W];
				req_tag_q   <= req_addr_i[ADDR_W-1 : OFFSET_W + IDX_W];
			end

			if (state_q == ST_LOOKUP) begin
				resp_valid_o <= 1'b1;
				resp_hit_o   <= lookup_hit_w;
				resp_rdata_o <= lookup_hit_w ? data_rdata_w : '0;
			end
		end
	end

endmodule