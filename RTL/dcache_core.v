`timescale 1ns/1ps
module dcache_core
(
	// Inputs
	 input           clk_i
	,input           rst_i
	,input  [ 31:0]  mem_addr_i
	,input  [ 31:0]  mem_data_wr_i
	,input           mem_rd_i
	,input  [  3:0]  mem_wr_i
	,input           mem_cacheable_i
	,input  [ 10:0]  mem_req_tag_i
	,input           mem_invalidate_i
	,input           mem_writeback_i
	,input           mem_flush_i
	// L2 request interface
	,input           l2_req_ready_i
	,input           l2_resp_valid_i
	,input           l2_resp_hit_i
	,input           l2_resp_error_i
	,input  [255:0]  l2_resp_rdata_i

	// Snoop inputs
	,input           snoop_valid_i
	,input  [  1:0]  snoop_cmd_i
	,input  [ 31:0]  snoop_addr_i
	
	// Coherence request interface
	,input           coh_req_ready_i
	,input           coh_trans_done_i
	,input           coh_trans_shared_i
	,input           coh_trans_dirty_i
	,output          coh_req_valid_o
	,output [1:0]    coh_req_cmd_o
	,output [31:0]   coh_req_addr_o

	// Outputs
	,output [ 31:0]  mem_data_rd_o
	,output          mem_accept_o
	,output          mem_ack_o
	,output          mem_error_o
	,output [ 10:0]  mem_resp_tag_o
	,output          l2_req_valid_o
	,output          l2_req_we_o
	,output [31:0]   l2_req_addr_o
	,output [255:0]  l2_req_wdata_o
	,output [31:0]   l2_req_wmask_o

	// Snoop outputs
	,output          snoop_hit_o
	,output          snoop_dirty_o
	,output          snoop_ack_o
);

//-----------------------------------------------------------------
// Cache geometry
//-----------------------------------------------------------------
localparam DCACHE_NUM_WAYS           = 2;
localparam DCACHE_NUM_LINES          = 256;
localparam DCACHE_LINE_ADDR_W        = 8;
localparam DCACHE_LINE_SIZE_W        = 5;
localparam DCACHE_LINE_SIZE          = 32;
localparam DCACHE_LINE_WORDS         = 8;

// Request -> tag address mapping
localparam DCACHE_TAG_REQ_LINE_L     = 5;
localparam DCACHE_TAG_REQ_LINE_H     = 12;
localparam DCACHE_TAG_REQ_LINE_W     = 8;
`define DCACHE_TAG_REQ_RNG           DCACHE_TAG_REQ_LINE_H:DCACHE_TAG_REQ_LINE_L

// Tag fields
`define CACHE_TAG_ADDR_RNG           18:0
localparam CACHE_TAG_ADDR_BITS       = 19;
localparam CACHE_TAG_STATE_LSB       = CACHE_TAG_ADDR_BITS + 0;
localparam CACHE_TAG_STATE_MSB       = CACHE_TAG_ADDR_BITS + 1;
localparam CACHE_TAG_DATA_W          = CACHE_TAG_ADDR_BITS + 2;

localparam [1:0] MSI_I = 2'b00;
localparam [1:0] MSI_S = 2'b01;
localparam [1:0] MSI_M = 2'b10;

// Tag compare bits
localparam DCACHE_TAG_CMP_ADDR_L     = DCACHE_TAG_REQ_LINE_H + 1;
localparam DCACHE_TAG_CMP_ADDR_H     = 32-1;
localparam DCACHE_TAG_CMP_ADDR_W     = DCACHE_TAG_CMP_ADDR_H - DCACHE_TAG_CMP_ADDR_L + 1;
`define   DCACHE_TAG_CMP_ADDR_RNG    31:13

//-----------------------------------------------------------------
// States
//-----------------------------------------------------------------
localparam STATE_W           = 4;
localparam STATE_RESET       = 4'd0;
localparam STATE_FLUSH_ADDR  = 4'd1;
localparam STATE_FLUSH       = 4'd2;
localparam STATE_LOOKUP      = 4'd3;
localparam STATE_READ        = 4'd4;
localparam STATE_WRITE       = 4'd5;
localparam STATE_REFILL      = 4'd6;
localparam STATE_EVICT       = 4'd7;
localparam STATE_EVICT_WAIT  = 4'd8;
localparam STATE_INVALIDATE  = 4'd9;
localparam STATE_WRITEBACK   = 4'd10;
localparam STATE_SNOOP_REQ   = 4'd11;
localparam STATE_SNOOP_CHECK = 4'd12;
localparam STATE_REFILL_WAIT = 4'd13;
localparam STATE_READ_WAIT = 4'd14;
localparam STATE_READ_RESP = 4'd15;



// Snoop commands
localparam [1:0] SNOOP_BUSRD   = 2'd0;
localparam [1:0] SNOOP_BUSRDX  = 2'd1;
localparam [1:0] SNOOP_BUSUPGR = 2'd2;

reg [STATE_W-1:0] next_state_r;
reg [STATE_W-1:0] state_q;


reg        last_wr_valid_q;
reg [31:0] last_wr_addr_q;
reg [31:0] last_wr_data_q;
reg [3:0]  last_wr_strb_q;

reg [2:0]  evict_word_idx_q;


//-----------------------------------------------------------------
// Request buffer
//-----------------------------------------------------------------
reg [31:0] mem_addr_m_q;
reg [31:0] mem_data_m_q;
reg [3:0]  mem_wr_m_q;
reg        mem_rd_m_q;
reg [10:0] mem_tag_m_q;
reg        mem_inval_m_q;
reg        mem_writeback_m_q;
reg        mem_flush_m_q;

reg        mem_cacheable_m_q;
wire mem_req_i_w =
		mem_rd_i
	 || (mem_wr_i != 4'b0)
	 || mem_invalidate_i
	 || mem_writeback_i
	 || mem_flush_i;

//-----------------------------------------------------------------
// Snoop buffer
//-----------------------------------------------------------------
reg        snoop_pending_q;
reg [31:0] snoop_addr_q;
reg [1:0]  snoop_cmd_q;
reg        snoop_wait_drop_q;

reg        snoop_hit_q;
reg        snoop_dirty_q;
reg        snoop_ack_q;

wire snoop_tag0_hit_w;
wire snoop_tag1_hit_w;
wire snoop_hit_any_w;
wire snoop_dirty_any_w;
wire snoop_shared_any_w;
wire snoop_busrd_w;
wire snoop_busrdx_w;
wire snoop_busupgr_w;
wire snoop_do_invalidate_w;
wire snoop_do_downgrade_w;

wire req_pending_w =
		mem_rd_m_q
	 || (mem_wr_m_q != 4'b0)
	 || mem_inval_m_q
	 || mem_writeback_m_q
	 || mem_flush_m_q;

always @ (posedge clk_i or posedge rst_i)
	if (rst_i)
	begin
		mem_addr_m_q      <= 32'b0;
		mem_data_m_q      <= 32'b0;
		mem_wr_m_q        <= 4'b0;
		mem_rd_m_q        <= 1'b0;
		mem_tag_m_q       <= 11'b0;
		mem_inval_m_q     <= 1'b0;
		mem_writeback_m_q <= 1'b0;
		mem_flush_m_q     <= 1'b0;
		mem_cacheable_m_q <= 1'b0;
	end
	else if (mem_ack_o)
	begin
		mem_addr_m_q      <= 32'b0;
		mem_data_m_q      <= 32'b0;
		mem_wr_m_q        <= 4'b0;
		mem_rd_m_q        <= 1'b0;
		mem_tag_m_q       <= 11'b0;
		mem_inval_m_q     <= 1'b0;
		mem_writeback_m_q <= 1'b0;
		mem_flush_m_q     <= 1'b0;
		mem_cacheable_m_q <= 1'b0;
	end
	else if (mem_accept_o && mem_req_i_w)
	begin
		mem_addr_m_q      <= mem_addr_i;
		mem_data_m_q      <= mem_data_wr_i;
		mem_wr_m_q        <= mem_wr_i;
		mem_rd_m_q        <= mem_rd_i;
		mem_tag_m_q       <= mem_req_tag_i;
		mem_inval_m_q     <= mem_invalidate_i;
		mem_writeback_m_q <= mem_writeback_i;
		mem_flush_m_q     <= mem_flush_i;
		mem_cacheable_m_q <= mem_cacheable_i;
	end

//-----------------------------------------------------------------
// Compare addresses
//-----------------------------------------------------------------
wire [DCACHE_TAG_CMP_ADDR_W-1:0] req_addr_tag_cmp_m_w;
wire [DCACHE_TAG_CMP_ADDR_W-1:0] snoop_addr_tag_cmp_w;
wire [DCACHE_TAG_REQ_LINE_W-1:0] snoop_addr_line_w;

assign req_addr_tag_cmp_m_w  = mem_addr_m_q[`DCACHE_TAG_CMP_ADDR_RNG];
assign snoop_addr_tag_cmp_w  = snoop_addr_q[`DCACHE_TAG_CMP_ADDR_RNG];
assign snoop_addr_line_w     = snoop_addr_q[`DCACHE_TAG_REQ_RNG];



//-----------------------------------------------------------------
// Response holding registers
//-----------------------------------------------------------------
reg [31:0] mem_data_rd_q;
reg [10:0] mem_resp_tag_q;


//-----------------------------------------------------------------
// Registers / Wires
//-----------------------------------------------------------------
reg [0:0]  replace_way_q;
reg        flushing_q;
reg [DCACHE_TAG_REQ_LINE_W-1:0] flush_addr_q;
reg        flush_last_q;
reg        mem_accept_r;
reg        mem_ack_r;

wire           l2_req_fire_w;
reg            l2_req_valid_r;
reg            l2_req_we_r;
reg  [31:0]    l2_req_addr_r;
reg  [255:0]   l2_req_wdata_r;
reg  [31:0]    l2_req_wmask_r;

wire           l2_resp_valid_w;
wire           l2_resp_hit_w;
wire           l2_resp_error_w;
wire [255:0]   l2_resp_rdata_w;

reg            l2_wait_resp_q;
reg  [255:0]   refill_line_q;
reg            refill_line_valid_q;

wire           evict_way_w;
wire           tag_modified_any_m_w;
wire           tag_hit_and_modified_m_w;

reg        coh_req_valid_q;
reg [1:0]  coh_req_cmd_q;
reg [31:0] coh_req_addr_q;
reg        coh_wait_done_q;
reg        coh_upgrade_done_q;
reg        coh_done_q;

wire miss_w;
wire write_hit_shared_need_upgrade_w;
wire coh_need_busrd_w;
wire coh_need_busrdx_w;
wire coh_need_busupgr_w;
wire coh_needed_w;
wire coh_req_fire_w;



assign l2_req_fire_w   = l2_req_valid_r && l2_req_ready_i;

assign l2_resp_valid_w = l2_resp_valid_i;
assign l2_resp_hit_w   = l2_resp_hit_i;
assign l2_resp_error_w = l2_resp_error_i;
assign l2_resp_rdata_w = l2_resp_rdata_i;

assign l2_req_valid_o  = l2_req_valid_r;
assign l2_req_we_o     = l2_req_we_r;
assign l2_req_addr_o   = l2_req_addr_r;
assign l2_req_wdata_o  = l2_req_wdata_r;
assign l2_req_wmask_o  = l2_req_wmask_r;


always @ (posedge clk_i or posedge rst_i)
	if (rst_i)
	begin
		last_wr_valid_q <= 1'b0;
		last_wr_addr_q  <= 32'b0;
		last_wr_data_q  <= 32'b0;
		last_wr_strb_q  <= 4'b0;
	end
	else if (mem_ack_r && (mem_wr_m_q != 4'b0))
	begin
		last_wr_valid_q <= 1'b1;
		last_wr_addr_q  <= mem_addr_m_q;
		last_wr_data_q  <= mem_data_m_q;
		last_wr_strb_q  <= mem_wr_m_q;
	end
	else if (mem_ack_r && mem_rd_m_q)
	begin
		last_wr_valid_q <= 1'b0;
	end
//-----------------------------------------------------------------
// Data-path helper declarations (must appear before TAG RAM logic)
//-----------------------------------------------------------------
localparam CACHE_DATA_ADDR_W = DCACHE_LINE_ADDR_W + DCACHE_LINE_SIZE_W - 2;

reg  [CACHE_DATA_ADDR_W-1:0] data_write_addr_q;

wire [2:0] refill_word_idx_w =
		data_write_addr_q[2:0];

wire refill_word_last_w =
		(refill_word_idx_w == (DCACHE_LINE_WORDS-1));
//-----------------------------------------------------------------
// TAG RAMS
//-----------------------------------------------------------------
reg [DCACHE_TAG_REQ_LINE_W-1:0] tag_addr_x_r;
reg [DCACHE_TAG_REQ_LINE_W-1:0] tag_addr_m_r;

// Tag RAM write data
reg [CACHE_TAG_DATA_W-1:0] tag_data_in_m_r;
always @ *
begin
	tag_data_in_m_r = {(CACHE_TAG_DATA_W){1'b0}};

	if (state_q == STATE_FLUSH || state_q == STATE_RESET || flushing_q)
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = MSI_I;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = {CACHE_TAG_ADDR_BITS{1'b0}};
	end
	else if (state_q == STATE_REFILL)
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = (mem_wr_m_q != 4'b0) ? MSI_M : MSI_S;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = mem_addr_m_q[`DCACHE_TAG_CMP_ADDR_RNG];
	end
	else if (state_q == STATE_INVALIDATE)
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = MSI_I;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = mem_addr_m_q[`DCACHE_TAG_CMP_ADDR_RNG];
	end
	else if (state_q == STATE_EVICT_WAIT)
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = MSI_I;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = mem_addr_m_q[`DCACHE_TAG_CMP_ADDR_RNG];
	end
	else if (state_q == STATE_WRITE || (state_q == STATE_LOOKUP && (|mem_wr_m_q)))
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = MSI_M;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = mem_addr_m_q[`DCACHE_TAG_CMP_ADDR_RNG];
	end
	else if (state_q == STATE_SNOOP_CHECK && snoop_do_invalidate_w)
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = MSI_I;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = snoop_addr_q[`DCACHE_TAG_CMP_ADDR_RNG];
	end
	else if (state_q == STATE_SNOOP_CHECK && snoop_do_downgrade_w)
	begin
		tag_data_in_m_r[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB] = MSI_S;
		tag_data_in_m_r[`CACHE_TAG_ADDR_RNG]                     = snoop_addr_q[`DCACHE_TAG_CMP_ADDR_RNG];
	end
end

// Tag RAM address
always @ *
begin
	if (state_q == STATE_SNOOP_REQ || state_q == STATE_SNOOP_CHECK)
		tag_addr_x_r = snoop_addr_line_w;
	else if (flushing_q)
		tag_addr_x_r = flush_addr_q;
	else if (req_pending_w)
		tag_addr_x_r = mem_addr_m_q[`DCACHE_TAG_REQ_RNG];
	else
		tag_addr_x_r = mem_addr_i[`DCACHE_TAG_REQ_RNG];

	if (state_q == STATE_SNOOP_CHECK)
		tag_addr_m_r = snoop_addr_line_w;
	else if (flushing_q || state_q == STATE_RESET)
		tag_addr_m_r = flush_addr_q;
	else
		tag_addr_m_r = mem_addr_m_q[`DCACHE_TAG_REQ_RNG];
end

// Tag RAM write enable (way 0)
reg tag0_write_m_r;
wire [CACHE_TAG_DATA_W-1:0] tag0_data_out_m_w;
wire [1:0]                     tag0_state_m_w     = tag0_data_out_m_w[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB];
wire                           tag0_valid_m_w     = (tag0_state_m_w != MSI_I);
wire                           tag0_modified_m_w  = (tag0_state_m_w == MSI_M);
wire                           tag0_shared_m_w    = (tag0_state_m_w == MSI_S);
wire [CACHE_TAG_ADDR_BITS-1:0] tag0_addr_bits_m_w = tag0_data_out_m_w[`CACHE_TAG_ADDR_RNG];
wire                           tag0_hit_m_w       = tag0_valid_m_w &&
													(tag0_addr_bits_m_w == req_addr_tag_cmp_m_w);

always @ *
begin
	tag0_write_m_r = 1'b0;

	if (state_q == STATE_RESET)
		tag0_write_m_r = 1'b1;
	else if (state_q == STATE_FLUSH)
		tag0_write_m_r = !tag_modified_any_m_w;
	else if (state_q == STATE_LOOKUP && (|mem_wr_m_q))
		tag0_write_m_r = tag0_hit_m_w &&
						 (tag0_modified_m_w ||
						  (tag0_shared_m_w && coh_upgrade_done_q));
	else if (state_q == STATE_WRITE)
		tag0_write_m_r = (replace_way_q == 0);
	else if (state_q == STATE_EVICT_WAIT && l2_resp_valid_w)
		tag0_write_m_r = (replace_way_q == 0);
	else if (state_q == STATE_REFILL && refill_line_valid_q && refill_word_last_w)
		tag0_write_m_r = (replace_way_q == 0);
	else if (state_q == STATE_INVALIDATE)
		tag0_write_m_r = tag0_hit_m_w;
	else if (state_q == STATE_SNOOP_CHECK && snoop_tag0_hit_w &&
			 (snoop_do_invalidate_w || snoop_do_downgrade_w))
		tag0_write_m_r = 1'b1;
end

dcache_core_tag_ram
u_tag0
(
  .clk0_i(tag_clk_unused_fix(clk_i)),
  .rst0_i(rst_i),
  .clk1_i(clk_i),
  .rst1_i(rst_i),
  .addr0_i(tag_addr_x_r),
  .data0_o(tag0_data_out_m_w),
  .addr1_i(tag_addr_m_r),
  .data1_i(tag_data_in_m_r),
  .wr1_i(tag0_write_m_r)
);

// Tag RAM write enable (way 1)
reg tag1_write_m_r;
wire [CACHE_TAG_DATA_W-1:0] tag1_data_out_m_w;
wire [1:0]                     tag1_state_m_w     = tag1_data_out_m_w[CACHE_TAG_STATE_MSB:CACHE_TAG_STATE_LSB];
wire                           tag1_valid_m_w     = (tag1_state_m_w != MSI_I);
wire                           tag1_modified_m_w  = (tag1_state_m_w == MSI_M);
wire                           tag1_shared_m_w    = (tag1_state_m_w == MSI_S);
wire [CACHE_TAG_ADDR_BITS-1:0] tag1_addr_bits_m_w = tag1_data_out_m_w[`CACHE_TAG_ADDR_RNG];
wire                           tag1_hit_m_w       = tag1_valid_m_w &&
													(tag1_addr_bits_m_w == req_addr_tag_cmp_m_w);

always @ *
begin
	tag1_write_m_r = 1'b0;

	if (state_q == STATE_RESET)
		tag1_write_m_r = 1'b1;
	else if (state_q == STATE_FLUSH)
		tag1_write_m_r = !tag_modified_any_m_w;
	else if (state_q == STATE_LOOKUP && (|mem_wr_m_q))
		tag1_write_m_r = tag1_hit_m_w &&
						 (tag1_modified_m_w ||
						  (tag1_shared_m_w && coh_upgrade_done_q));
	else if (state_q == STATE_WRITE)
		tag1_write_m_r = (replace_way_q == 1);
	else if (state_q == STATE_EVICT_WAIT && l2_resp_valid_w)
		tag1_write_m_r = (replace_way_q == 1);
	else if (state_q == STATE_REFILL && refill_line_valid_q && refill_word_last_w)
		tag1_write_m_r = (replace_way_q == 1);
	else if (state_q == STATE_INVALIDATE)
		tag1_write_m_r = tag1_hit_m_w;
	else if (state_q == STATE_SNOOP_CHECK && snoop_tag1_hit_w &&
			 (snoop_do_invalidate_w || snoop_do_downgrade_w))
		tag1_write_m_r = 1'b1;
end

dcache_core_tag_ram
u_tag1
(
  .clk0_i(tag_clk_unused_fix(clk_i)),
  .rst0_i(rst_i),
  .clk1_i(clk_i),
  .rst1_i(rst_i),
  .addr0_i(tag_addr_x_r),
  .data0_o(tag1_data_out_m_w),
  .addr1_i(tag_addr_m_r),
  .data1_i(tag_data_in_m_r),
  .wr1_i(tag1_write_m_r)
);

//-----------------------------------------------------------------
// Snoop helper signals
//-----------------------------------------------------------------
assign snoop_tag0_hit_w =
		tag0_valid_m_w &&
		(tag0_addr_bits_m_w == snoop_addr_tag_cmp_w);

assign snoop_tag1_hit_w =
		tag1_valid_m_w &&
		(tag1_addr_bits_m_w == snoop_addr_tag_cmp_w);

assign snoop_hit_any_w =
		snoop_tag0_hit_w |
		snoop_tag1_hit_w;

assign snoop_dirty_any_w =
		(snoop_tag0_hit_w & tag0_modified_m_w) |
		(snoop_tag1_hit_w & tag1_modified_m_w);

assign snoop_shared_any_w =
		(snoop_tag0_hit_w & tag0_shared_m_w) |
		(snoop_tag1_hit_w & tag1_shared_m_w);

assign snoop_busrd_w =
		(snoop_cmd_q == SNOOP_BUSRD);

assign snoop_busrdx_w =
		(snoop_cmd_q == SNOOP_BUSRDX);

assign snoop_busupgr_w =
		(snoop_cmd_q == SNOOP_BUSUPGR);

assign snoop_do_invalidate_w =
		(snoop_busrdx_w && snoop_hit_any_w) ||
		(snoop_busupgr_w && snoop_shared_any_w);

assign snoop_do_downgrade_w =
		(snoop_busrd_w && snoop_dirty_any_w);

//-----------------------------------------------------------------
// Tag / MSI helper signals
//-----------------------------------------------------------------
wire tag_hit_any_m_w = 1'b0
		| tag0_hit_m_w
		| tag1_hit_m_w
		 ;

assign tag_hit_and_modified_m_w = 1'b0
					| (tag0_hit_m_w & tag0_modified_m_w)
					| (tag1_hit_m_w & tag1_modified_m_w);

assign tag_modified_any_m_w = 1'b0
				| (tag0_valid_m_w & tag0_modified_m_w)
				| (tag1_valid_m_w & tag1_modified_m_w);

assign miss_w =
		(mem_rd_m_q || (mem_wr_m_q != 4'b0)) &&
		!tag_hit_any_m_w;

wire write_hit_shared_m_w =
		(tag0_hit_m_w && tag0_shared_m_w) ||
		(tag1_hit_m_w && tag1_shared_m_w);

wire write_hit_modified_m_w =
		(tag0_hit_m_w && tag0_modified_m_w) ||
		(tag1_hit_m_w && tag1_modified_m_w);

wire read_hit_m_w =
		mem_rd_m_q && tag_hit_any_m_w;

assign write_hit_shared_need_upgrade_w =
		(mem_wr_m_q != 4'b0) &&
		write_hit_shared_m_w &&
		!coh_upgrade_done_q;

wire write_hit_ok_m_w =
		(mem_wr_m_q != 4'b0) &&
		(write_hit_modified_m_w ||
		 (write_hit_shared_m_w && coh_upgrade_done_q));

assign coh_need_busrd_w =
		mem_cacheable_m_q &&
		mem_rd_m_q &&
		!tag_hit_any_m_w &&
		!coh_done_q;

assign coh_need_busrdx_w =
		mem_cacheable_m_q &&
		(mem_wr_m_q != 4'b0) &&
		!tag_hit_any_m_w &&
		!coh_done_q;

assign coh_need_busupgr_w =
		mem_cacheable_m_q &&
		write_hit_shared_need_upgrade_w &&
		!coh_done_q;

assign coh_needed_w =
		coh_need_busrd_w ||
		coh_need_busrdx_w ||
		coh_need_busupgr_w;

assign coh_req_fire_w =
		coh_req_valid_q && coh_req_ready_i;

//-----------------------------------------------------------------
// Snoop state
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
	if (rst_i)
	begin
		snoop_pending_q   <= 1'b0;
		snoop_addr_q      <= 32'b0;
		snoop_cmd_q       <= 2'b0;
		snoop_hit_q       <= 1'b0;
		snoop_dirty_q     <= 1'b0;
		snoop_ack_q       <= 1'b0;
		snoop_wait_drop_q <= 1'b0;
	end
	else
	begin
		snoop_ack_q <= 1'b0;

		if (snoop_wait_drop_q && !snoop_valid_i)
			snoop_wait_drop_q <= 1'b0;

		if (!snoop_pending_q && !snoop_wait_drop_q && snoop_valid_i)
		begin
			snoop_pending_q <= 1'b1;
			snoop_addr_q    <= snoop_addr_i;
			snoop_cmd_q     <= snoop_cmd_i;
		end
		else if (state_q == STATE_SNOOP_CHECK)
		begin
			snoop_pending_q   <= 1'b0;
			snoop_hit_q       <= snoop_hit_any_w;
			snoop_dirty_q     <= snoop_dirty_any_w;
			snoop_ack_q       <= 1'b1;
			snoop_wait_drop_q <= 1'b1;
		end
	end
assign snoop_hit_o   = snoop_hit_q;
assign snoop_dirty_o = snoop_dirty_q;
assign snoop_ack_o   = snoop_ack_q;

always @ (posedge clk_i or posedge rst_i)
	if (rst_i)
	begin
		coh_req_valid_q    <= 1'b0;
		coh_req_cmd_q      <= 2'b11;
		coh_req_addr_q     <= 32'b0;
		coh_wait_done_q    <= 1'b0;
		coh_upgrade_done_q <= 1'b0;
		coh_done_q         <= 1'b0;
	end
	else
	begin
		if (mem_accept_o)
		begin
			coh_upgrade_done_q <= 1'b0;
			coh_done_q         <= 1'b0;
		end

		if (mem_ack_o)
		begin
			coh_req_valid_q    <= 1'b0;
			coh_req_cmd_q      <= 2'b11;
			coh_req_addr_q     <= 32'b0;
			coh_wait_done_q    <= 1'b0;
			coh_upgrade_done_q <= 1'b0;
			coh_done_q         <= 1'b0;
		end
		else if (coh_wait_done_q && coh_trans_done_i)
		begin
			coh_wait_done_q <= 1'b0;
			coh_done_q      <= 1'b1;

			if (coh_req_cmd_q == SNOOP_BUSUPGR)
				coh_upgrade_done_q <= 1'b1;
		end
		else if (coh_req_fire_w)
		begin
			coh_req_valid_q <= 1'b0;
			coh_wait_done_q <= 1'b1;
		end
		else if (!coh_req_valid_q &&
				 !coh_wait_done_q &&
				 !coh_done_q &&
				 coh_needed_w)
		begin
			coh_req_valid_q <= 1'b1;
			coh_req_addr_q  <= mem_addr_m_q;

			if (coh_need_busrd_w)
				coh_req_cmd_q <= SNOOP_BUSRD;
			else if (coh_need_busrdx_w)
				coh_req_cmd_q <= SNOOP_BUSRDX;
			else
				coh_req_cmd_q <= SNOOP_BUSUPGR;
		end
	end

assign coh_req_valid_o = coh_req_valid_q;
assign coh_req_cmd_o   = coh_req_cmd_q;
assign coh_req_addr_o  = coh_req_addr_q;

//-----------------------------------------------------------------
// mem_accept logic
//-----------------------------------------------------------------
always @ *
begin
	mem_accept_r = 1'b0;

	if (state_q == STATE_LOOKUP && mem_req_i_w)
	begin
		if (snoop_pending_q || coh_req_valid_q || coh_wait_done_q)
			mem_accept_r = 1'b0;
		else if (req_pending_w)
			mem_accept_r = 1'b0;
		else
			mem_accept_r = 1'b1;
	end
end
assign mem_accept_o = mem_accept_r;

//-----------------------------------------------------------------
// DATA RAMS
//-----------------------------------------------------------------


reg [CACHE_DATA_ADDR_W-1:0] data_addr_x_r;
reg [CACHE_DATA_ADDR_W-1:0] data_addr_m_r;


wire [31:0] data0_data_out_m_w;
wire [31:0] data1_data_out_m_w;

wire [CACHE_DATA_ADDR_W-1:0] line_base_addr_w =
		{mem_addr_m_q[`DCACHE_TAG_REQ_RNG], {(DCACHE_LINE_SIZE_W-2){1'b0}}};


wire [31:0] refill_word_data_w =
		refill_line_q[(refill_word_idx_w * 32) +: 32];

// Data RAM refill write address
always @ (posedge clk_i or posedge rst_i)
	if (rst_i)
	begin
		data_write_addr_q <= {(CACHE_DATA_ADDR_W){1'b0}};
		evict_word_idx_q  <= 3'b000;
	end
	else if (state_q != STATE_REFILL && next_state_r == STATE_REFILL)
	begin
		data_write_addr_q <= line_base_addr_w;
		evict_word_idx_q  <= 3'b000;
	end
	else if (state_q != STATE_EVICT && next_state_r == STATE_EVICT)
	begin
		// word0 is already primed by the pre-EVICT address selection
		data_write_addr_q <= line_base_addr_w + 1'b1;
		evict_word_idx_q  <= 3'b000;
	end
	else if (state_q == STATE_REFILL && refill_line_valid_q && !refill_word_last_w)
	begin
		data_write_addr_q <= data_write_addr_q + 1'b1;
	end
	else if (state_q == STATE_EVICT && evict_word_idx_q != 3'd7)
	begin
		data_write_addr_q <= data_write_addr_q + 1'b1;
		evict_word_idx_q  <= evict_word_idx_q + 1'b1;
	end

// Data RAM address
always @ *
begin
	if (state_q == STATE_REFILL || state_q == STATE_EVICT)
	begin
		data_addr_x_r = data_write_addr_q;
		data_addr_m_r = data_write_addr_q;
	end
	else if (state_q == STATE_FLUSH || state_q == STATE_RESET)
	begin
		data_addr_x_r = {flush_addr_q, {(DCACHE_LINE_SIZE_W-2){1'b0}}};
		data_addr_m_r = data_addr_x_r;
	end
	else if (state_q != STATE_EVICT && next_state_r == STATE_EVICT)
	begin
		data_addr_x_r = {mem_addr_m_q[`DCACHE_TAG_REQ_RNG], {(DCACHE_LINE_SIZE_W-2){1'b0}}};
		data_addr_m_r = data_addr_x_r;
	end
	else if (req_pending_w)
	begin
		data_addr_x_r = mem_addr_m_q[CACHE_DATA_ADDR_W+2-1:2];
		data_addr_m_r = mem_addr_m_q[CACHE_DATA_ADDR_W+2-1:2];
	end
	else
	begin
		data_addr_x_r = mem_addr_i[CACHE_DATA_ADDR_W+2-1:2];
		data_addr_m_r = mem_addr_i[CACHE_DATA_ADDR_W+2-1:2];
	end
end

// Data RAM write enable (way 0)
reg [3:0] data0_write_m_r;
always @ *
begin
	data0_write_m_r = 4'b0;

	if (state_q == STATE_REFILL)
		data0_write_m_r = (refill_line_valid_q && replace_way_q == 0) ? 4'b1111 : 4'b0000;
	else if (state_q == STATE_WRITE)
		data0_write_m_r = mem_wr_m_q & {4{replace_way_q == 0}};
	else if (state_q == STATE_LOOKUP)
		data0_write_m_r = mem_wr_m_q &
						  {4{tag0_hit_m_w &&
							 (tag0_modified_m_w ||
							  (tag0_shared_m_w && coh_upgrade_done_q))}};
end

wire [31:0] data0_data_in_m_w = (state_q == STATE_REFILL) ? refill_word_data_w : mem_data_m_q;

dcache_core_data_ram
u_data0
(
  .clk0_i(clk_i),
  .rst0_i(rst_i),
  .clk1_i(clk_i),
  .rst1_i(rst_i),
  .addr0_i(data_addr_x_r),
  .data0_i(32'b0),
  .wr0_i(4'b0),
  .data0_o(data0_data_out_m_w),
  .addr1_i(data_addr_m_r),
  .data1_i(data0_data_in_m_w),
  .wr1_i(data0_write_m_r),
  .data1_o()
);

// Data RAM write enable (way 1)
reg [3:0] data1_write_m_r;
always @ *
begin
	data1_write_m_r = 4'b0;

	if (state_q == STATE_REFILL)
		data1_write_m_r = (refill_line_valid_q && replace_way_q == 1) ? 4'b1111 : 4'b0000;
	else if (state_q == STATE_WRITE)
		data1_write_m_r = mem_wr_m_q & {4{replace_way_q == 1}};
	else if (state_q == STATE_LOOKUP)
		data1_write_m_r = mem_wr_m_q &
						  {4{tag1_hit_m_w &&
							 (tag1_modified_m_w ||
							  (tag1_shared_m_w && coh_upgrade_done_q))}};
end

wire [31:0] data1_data_in_m_w = (state_q == STATE_REFILL) ? refill_word_data_w : mem_data_m_q;

dcache_core_data_ram
u_data1
(
  .clk0_i(clk_i),
  .rst0_i(rst_i),
  .clk1_i(clk_i),
  .rst1_i(rst_i),
  .addr0_i(data_addr_x_r),
  .data0_i(32'b0),
  .wr0_i(4'b0),
  .data0_o(data1_data_out_m_w),
  .addr1_i(data_addr_m_r),
  .data1_i(data1_data_in_m_w),
  .wr1_i(data1_write_m_r),
  .data1_o()
);
//-----------------------------------------------------------------
// Eviction selection
//-----------------------------------------------------------------
localparam EVICT_ADDR_W = 32 - DCACHE_LINE_SIZE_W;
reg [31:0] evict_data_r;
reg [EVICT_ADDR_W-1:0] evict_addr_r;
reg evict_way_r;

always @ *
begin
	evict_way_r  = 1'b0;
	evict_addr_r = flushing_q ? {tag0_addr_bits_m_w, flush_addr_q} :
								{tag0_addr_bits_m_w, mem_addr_m_q[`DCACHE_TAG_REQ_RNG]};
	evict_data_r = data0_data_out_m_w;

	case (replace_way_q)
		1'd0:
		begin
			evict_way_r  = tag0_valid_m_w && tag0_modified_m_w;
			evict_addr_r = flushing_q ? {tag0_addr_bits_m_w, flush_addr_q} :
										{tag0_addr_bits_m_w, mem_addr_m_q[`DCACHE_TAG_REQ_RNG]};
			evict_data_r = data0_data_out_m_w;
		end
		1'd1:
		begin
			evict_way_r  = tag1_valid_m_w && tag1_modified_m_w;
			evict_addr_r = flushing_q ? {tag1_addr_bits_m_w, flush_addr_q} :
										{tag1_addr_bits_m_w, mem_addr_m_q[`DCACHE_TAG_REQ_RNG]};
			evict_data_r = data1_data_out_m_w;
		end
	endcase
end

assign                  evict_way_w  = (flushing_q || !tag_hit_any_m_w) && evict_way_r;
wire [EVICT_ADDR_W-1:0] evict_addr_w = evict_addr_r;
wire [31:0]             evict_data_w = evict_data_r;

//-----------------------------------------------------------------
// Flush counter
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
	flush_addr_q <= {(DCACHE_TAG_REQ_LINE_W){1'b0}};
else if ((state_q == STATE_RESET) || (state_q == STATE_FLUSH && next_state_r == STATE_FLUSH_ADDR))
	flush_addr_q <= flush_addr_q + 1;
else if (state_q == STATE_LOOKUP)
	flush_addr_q <= {(DCACHE_TAG_REQ_LINE_W){1'b0}};

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
	flushing_q <= 1'b0;
else if (state_q == STATE_LOOKUP && next_state_r == STATE_FLUSH_ADDR)
	flushing_q <= 1'b1;
else if (state_q == STATE_FLUSH && next_state_r == STATE_LOOKUP)
	flushing_q <= 1'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
	flush_last_q <= 1'b0;
else if (state_q == STATE_LOOKUP)
	flush_last_q <= 1'b0;
else if (flush_addr_q == {(DCACHE_TAG_REQ_LINE_W){1'b1}})
	flush_last_q <= 1'b1;

//-----------------------------------------------------------------
// Replacement Policy
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
	if (rst_i)
		replace_way_q <= 0;
	else if (state_q == STATE_WRITE || state_q == STATE_READ_RESP)
		replace_way_q <= replace_way_q + 1'b1;
	else if (flushing_q && tag_modified_any_m_w && !evict_way_w && state_q != STATE_FLUSH_ADDR)
		replace_way_q <= replace_way_q + 1'b1;
	else if (state_q == STATE_EVICT_WAIT && next_state_r == STATE_FLUSH_ADDR)
		replace_way_q <= 0;
	else if (state_q == STATE_FLUSH && next_state_r == STATE_LOOKUP)
		replace_way_q <= 0;
	else if (state_q == STATE_LOOKUP && next_state_r == STATE_FLUSH_ADDR)
		replace_way_q <= 0;
	else if (state_q == STATE_WRITEBACK)
	begin
		case (1'b1)
		tag0_hit_m_w: replace_way_q <= 0;
		tag1_hit_m_w: replace_way_q <= 1;
		endcase
	end

//-----------------------------------------------------------------
// Output result mux
//-----------------------------------------------------------------
reg [31:0] data_r;
reg [31:0] data_r_raw;
reg [31:0] read_resp_data_r;

always @ *
begin
	data_r_raw = 32'b0;

	if (state_q == STATE_REFILL_WAIT ||
		state_q == STATE_READ_WAIT   ||
		state_q == STATE_READ        ||
		state_q == STATE_READ_RESP)
	begin
		data_r_raw = (replace_way_q == 0) ? data0_data_out_m_w : data1_data_out_m_w;
	end
	else
	begin
		case (1'b1)
			tag0_hit_m_w: data_r_raw = data0_data_out_m_w;
			tag1_hit_m_w: data_r_raw = data1_data_out_m_w;
			default:      data_r_raw = data0_data_out_m_w;
		endcase
	end

	data_r = data_r_raw;
	

	// Forward last completed write into an immediate following read of same word
	if (mem_rd_m_q &&
		last_wr_valid_q &&
		(last_wr_addr_q[31:2] == mem_addr_m_q[31:2]))
	begin
		if (last_wr_strb_q[0]) data_r[7:0]   = last_wr_data_q[7:0];
		if (last_wr_strb_q[1]) data_r[15:8]  = last_wr_data_q[15:8];
		if (last_wr_strb_q[2]) data_r[23:16] = last_wr_data_q[23:16];
		if (last_wr_strb_q[3]) data_r[31:24] = last_wr_data_q[31:24];
	end
end

always @ *
begin
	read_resp_data_r = data_r;

	if (last_wr_valid_q &&
		(last_wr_addr_q[31:2] == mem_addr_m_q[31:2]))
	begin
		if (last_wr_strb_q[0]) read_resp_data_r[7:0]   = last_wr_data_q[7:0];
		if (last_wr_strb_q[1]) read_resp_data_r[15:8]  = last_wr_data_q[15:8];
		if (last_wr_strb_q[2]) read_resp_data_r[23:16] = last_wr_data_q[23:16];
		if (last_wr_strb_q[3]) read_resp_data_r[31:24] = last_wr_data_q[31:24];
	end
end
//-----------------------------------------------------------------
// Read-miss refill capture
//-----------------------------------------------------------------
reg read_from_refill_q;
reg refill_data_valid_q;

wire [2:0] refill_req_word_idx_w  = mem_addr_m_q[4:2];
wire [2:0] refill_cur_word_idx_w  = data_write_addr_q[2:0];
wire [31:0] refill_req_word_data_w =
		refill_line_q[(refill_req_word_idx_w * 32) +: 32];
wire [31:0] l2_resp_req_word_data_w =
		l2_resp_rdata_w[(refill_req_word_idx_w * 32) +: 32];

wire use_refill_data_w = read_from_refill_q || refill_data_valid_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
	read_from_refill_q  <= 1'b0;
	refill_data_valid_q <= 1'b0;
	mem_data_rd_q       <= 32'b0;
	mem_resp_tag_q      <= 11'b0;
end
else
begin
	// Mark that this request will return data from refill
	if (state_q != STATE_REFILL && next_state_r == STATE_REFILL && mem_rd_m_q)
	begin
		read_from_refill_q  <= 1'b1;
		refill_data_valid_q <= 1'b0;
	end

	// Capture requested word immediately when full line returns from L2
	if (l2_resp_valid_w && read_from_refill_q)
	begin
		mem_data_rd_q       <= l2_resp_req_word_data_w;
		refill_data_valid_q <= 1'b1;
	end

	// Also allow capture from refill_line_q while refill is being written
	if (state_q == STATE_REFILL &&
		refill_line_valid_q &&
		read_from_refill_q &&
		(refill_cur_word_idx_w == refill_req_word_idx_w))
	begin
		mem_data_rd_q       <= refill_req_word_data_w;
		refill_data_valid_q <= 1'b1;
	end

	// Capture tag on every response
	if (mem_ack_r)
	begin
		mem_resp_tag_q <= mem_tag_m_q;

		if (mem_rd_m_q && !use_refill_data_w)
			mem_data_rd_q <= read_resp_data_r;

		read_from_refill_q  <= 1'b0;
		refill_data_valid_q <= 1'b0;
	end
end

assign mem_data_rd_o = mem_data_rd_q;

assign mem_resp_tag_o =
		mem_ack_o ? mem_tag_m_q : mem_resp_tag_q;

//-----------------------------------------------------------------
// Next State Logic
//-----------------------------------------------------------------
always @ *
begin
	next_state_r = state_q;

	case (state_q)
	STATE_RESET :
	begin
		if (flush_last_q)
			next_state_r = STATE_LOOKUP;
	end

	STATE_FLUSH_ADDR :
		next_state_r = STATE_FLUSH;

	STATE_FLUSH :
	begin
		if (tag_modified_any_m_w)
		begin
			if (evict_way_w)
				next_state_r = STATE_EVICT;
		end
		else if (flush_last_q)
			next_state_r = STATE_LOOKUP;
		else
			next_state_r = STATE_FLUSH_ADDR;
	end

	STATE_LOOKUP :
	begin
		if (snoop_pending_q)
			next_state_r = STATE_SNOOP_REQ;

		else if (coh_req_valid_q || coh_wait_done_q)
			next_state_r = STATE_LOOKUP;

		// After coherence completed for a miss, continue normal miss path
		else if (coh_done_q && miss_w)
		begin
			if (evict_way_w)
				next_state_r = STATE_EVICT;
			else
				next_state_r = STATE_REFILL;
		end

		// Upgrade case stays in LOOKUP
		else if (coh_done_q && write_hit_shared_m_w)
			next_state_r = STATE_LOOKUP;

		else if ((mem_rd_m_q || (mem_wr_m_q != 4'b0)) && !tag_hit_any_m_w)
			next_state_r = STATE_LOOKUP;

		else if (mem_writeback_i && mem_accept_o)
			next_state_r = STATE_WRITEBACK;
		else if (mem_flush_i && mem_accept_o)
			next_state_r = STATE_FLUSH_ADDR;
		else if (mem_invalidate_i && mem_accept_o)
			next_state_r = STATE_INVALIDATE;
	end

	STATE_SNOOP_REQ :
		next_state_r = STATE_SNOOP_CHECK;

	STATE_SNOOP_CHECK :
		next_state_r = STATE_LOOKUP;

	// Wait for L2 line response, then walk through 8 words of refill_line_q
	STATE_REFILL :
	begin
		if (refill_line_valid_q && refill_word_last_w)
			next_state_r = STATE_REFILL_WAIT;
	end

	STATE_REFILL_WAIT :
	begin
		if (mem_wr_m_q != 4'b0)
			next_state_r = STATE_WRITE;
		else
			next_state_r = STATE_READ_WAIT;
	end

	STATE_READ_WAIT :
	begin
		next_state_r = STATE_READ;
	end

	STATE_READ :
	begin
		next_state_r = STATE_READ_RESP;
	end

	STATE_WRITE,
	STATE_READ_RESP :
		next_state_r = STATE_LOOKUP;

	// EVICT issues one line request to L2
	STATE_EVICT :
	begin
		if (l2_req_fire_w)
			next_state_r = STATE_EVICT_WAIT;
	end

	// Wait for writeback response from L2
	STATE_EVICT_WAIT :
	begin
		if (l2_resp_valid_w && mem_writeback_m_q)
			next_state_r = STATE_LOOKUP;
		else if (l2_resp_valid_w && flushing_q)
			next_state_r = STATE_FLUSH_ADDR;
		else if (l2_resp_valid_w)
			next_state_r = STATE_REFILL;
	end

	STATE_WRITEBACK :
	begin
		if (tag_hit_and_modified_m_w)
			next_state_r = STATE_EVICT;
		else
			next_state_r = STATE_LOOKUP;
	end

	STATE_INVALIDATE :
		next_state_r = STATE_LOOKUP;

	default:
		;
	endcase
end

// Update state
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
	state_q <= STATE_RESET;
else
	state_q <= next_state_r;

// mem_ack
always @ *
begin
	mem_ack_r = 1'b0;

	case (state_q)
	STATE_LOOKUP :
	begin
		if (read_hit_m_w || write_hit_ok_m_w)
			mem_ack_r = 1'b1;
		else if (mem_flush_m_q || mem_inval_m_q || mem_writeback_m_q)
			mem_ack_r = 1'b1;
	end

	// Read miss completes here after line refill
	STATE_READ_RESP :
	begin
		mem_ack_r = 1'b1;
	end

	// Write miss / upgrade completes here
	STATE_WRITE :
	begin
		mem_ack_r = 1'b1;
	end

	// Maintenance requests can complete here
	STATE_INVALIDATE :
	begin
		mem_ack_r = 1'b1;
	end

	// Writeback request that actually evicted a modified line
	STATE_EVICT_WAIT :
	begin
		if (l2_resp_valid_w && mem_writeback_m_q)
			mem_ack_r = 1'b1;
	end

	default :
	begin
		mem_ack_r = 1'b0;
	end
	endcase
end

assign mem_ack_o =
		(mem_ack_r && !(read_from_refill_q && !refill_data_valid_q));
//-----------------------------------------------------------------
// L2 request / response handling
//-----------------------------------------------------------------
reg [255:0] evict_line_q;

wire [31:0] evict_word_data_w =
		(replace_way_q == 0) ? data0_data_out_m_w : data1_data_out_m_w;

wire [255:0] evict_line_next_w =
		(evict_line_q & ~(256'hFFFF_FFFF << (evict_word_idx_q * 32))) |
		({224'b0, evict_word_data_w} << (evict_word_idx_q * 32));

wire refill_request_w = (state_q != STATE_REFILL && next_state_r == STATE_REFILL);
wire evict_request_w  = (state_q == STATE_EVICT) && (evict_word_idx_q == 3'd7);

// L2 request launch / response capture
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
	l2_req_valid_r      <= 1'b0;
	l2_req_we_r         <= 1'b0;
	l2_req_addr_r       <= 32'b0;
	l2_req_wdata_r      <= 256'b0;
	l2_req_wmask_r      <= 32'b0;
	l2_wait_resp_q      <= 1'b0;
	refill_line_q       <= 256'b0;
	refill_line_valid_q <= 1'b0;
	evict_line_q        <= 256'b0;
end
else
begin
	// When refill writing completes, drop refill_line_valid_q
	if (state_q == STATE_REFILL && refill_line_valid_q && refill_word_last_w)
		refill_line_valid_q <= 1'b0;

	// Collect dirty line word-by-word during EVICT
	if (state_q == STATE_EVICT)
		evict_line_q <= evict_line_next_w;

	// Launch refill read request once
	if (refill_request_w && !l2_req_valid_r && !l2_wait_resp_q)
	begin
		l2_req_valid_r <= 1'b1;
		l2_req_we_r    <= 1'b0;
		l2_req_addr_r  <= {mem_addr_m_q[31:DCACHE_LINE_SIZE_W], {(DCACHE_LINE_SIZE_W){1'b0}}};
		l2_req_wdata_r <= 256'b0;
		l2_req_wmask_r <= 32'b0;
	end
	// Launch evict / writeback request after the last word was assembled
	else if (evict_request_w && !l2_req_valid_r && !l2_wait_resp_q)
	begin
		l2_req_valid_r <= 1'b1;
		l2_req_we_r    <= 1'b1;
		l2_req_addr_r  <= {evict_addr_w, {(DCACHE_LINE_SIZE_W){1'b0}}};
		l2_req_wdata_r <= evict_line_next_w;
		l2_req_wmask_r <= 32'hFFFF_FFFF;
	end

	// Request accepted by L2
	if (l2_req_fire_w)
	begin
		l2_req_valid_r <= 1'b0;
		l2_wait_resp_q <= 1'b1;
	end

	// L2 response received
	if (l2_wait_resp_q && l2_resp_valid_w)
	begin
		l2_wait_resp_q <= 1'b0;

		// For refill: store full line, then STATE_REFILL writes it word-by-word to data RAM
		if (state_q == STATE_REFILL || next_state_r == STATE_REFILL)
		begin
			refill_line_q       <= l2_resp_rdata_w;
			refill_line_valid_q <= 1'b1;
		end
	end
end

//-----------------------------------------------------------------
// Error handling
//-----------------------------------------------------------------
reg error_q;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
	error_q <= 1'b0;
else if (l2_wait_resp_q && l2_resp_valid_w && l2_resp_error_w)
	error_q <= 1'b1;
else if (mem_ack_o)
	error_q <= 1'b0;

assign mem_error_o = error_q;

//-------------------------------------------------------------------
// Debug
//-------------------------------------------------------------------
`ifdef verilator
/* verilator lint_off WIDTH */
reg [79:0] dbg_state;
always @ *
begin
	dbg_state = "-";

	case (state_q)
	STATE_RESET:       dbg_state = "RESET";
	STATE_FLUSH_ADDR:  dbg_state = "FLUSH_ADDR";
	STATE_FLUSH:       dbg_state = "FLUSH";
	STATE_LOOKUP:      dbg_state = "LOOKUP";
	STATE_READ:        dbg_state = "READ";
	STATE_WRITE:       dbg_state = "WRITE";
	STATE_REFILL:      dbg_state = "REFILL";
	STATE_EVICT:       dbg_state = "EVICT";
	STATE_EVICT_WAIT:  dbg_state = "EVICT_WAIT";
	STATE_INVALIDATE:  dbg_state = "INVAL";
	STATE_WRITEBACK:   dbg_state = "WRITEBACK";
	STATE_SNOOP_REQ:   dbg_state = "SNOOP_REQ";
	STATE_SNOOP_CHECK: dbg_state = "SNOOP_CHECK";
	STATE_REFILL_WAIT: dbg_state = "REFILL_WAIT";
	STATE_READ_WAIT:   dbg_state = "READ_WAIT";
	STATE_READ_RESP:   dbg_state = "READ_RESP";
	default:           ;
	endcase
end
/* verilator lint_on WIDTH */
`endif

function automatic tag_clk_unused_fix(input logic x);
	tag_clk_unused_fix = x;
endfunction

endmodule