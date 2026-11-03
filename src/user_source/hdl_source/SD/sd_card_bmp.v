
module sd_card_bmp #(
    parameter MENU_CONTROL=0,
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [3:0]   SCAN_TARGET_COUNT = 4'd10
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       next_event,auto_event,menu_pause,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    input                       display_ack_toggle,
    output reg                  image_ready_toggle,
    output [1:0]                image_ready_index,
    output                      auto_mode,
    output                      image_loading,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input music_can_read, output music_pcm_valid, output [31:0] music_pcm_data, output [3:0] music_status,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [3:0]       scan_found_total;

reg scan_resume_pulse;
reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [3:0]        img_found_count;
reg [3:0]        img_idx;              // 当前真正显示中的图片编号
reg [3:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0] img_sectors[0:9];
reg              next_req_pending;
reg              load_busy;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg source_done_seen;
reg source_started, mem_done_seen, awaiting_display;
reg [2:0] display_ack_sync;
assign image_ready_index = pending_buf_idx;
assign auto_mode = auto_play_en;
assign image_loading = !display_valid || load_busy;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [3:0] next_from_current;

assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ * 5 - 1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

generate if(MENU_CONTROL) begin
 assign key_next_press=next_event;
 assign key_auto_press=auto_event;
end else begin
key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);
end endgenerate

function [3:0] next_index_limited;
 input [3:0] cur; input [3:0] count;
 begin next_index_limited = (count<=1 || cur+1>=count) ? 4'd0 : cur+4'd1; end
endfunction
function [31:0] sector_lut;
 input [3:0] idx;
 begin sector_lut = idx<10 ? img_sectors[idx] : img_sectors[0]; end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync <= 0;
        display_ack_sync <= 0;
        image_ready_toggle <= 0;
        source_started <= 0; mem_done_seen <= 0; awaiting_display <= 0;
        scan_start_pulse<=0;scan_resume_pulse<=0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        for(integer i=0;i<10;i=i+1) img_sectors[i]<=0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        display_ack_sync <= {display_ack_sync[1:0], display_ack_toggle};
        scan_start_pulse<=0;scan_resume_pulse<=0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            for(integer i=0;i<10;i=i+1) img_sectors[i]<=0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                if(img_found_count<10) img_sectors[img_found_count]<=scan_found_sector;

                if (img_found_count < 4'd10)
                    img_found_count <= img_found_count + 3'd1;
            end

            // Remember completion events independently; ready is initially high.
            if (load_busy && !bmp_ready) source_started <= 1;
            if (load_busy && source_started && bmp_ready) source_done_seen <= 1;
            if (load_busy && write_finish_pulse) mem_done_seen <= 1;
            if (load_busy && source_done_seen && mem_done_seen && !awaiting_display) begin
                image_ready_toggle <= ~image_ready_toggle;
                awaiting_display <= 1;
            end
            // Release old buffer only after video switched, read acknowledged, fade ended.
            if (awaiting_display && display_ack_sync[2] == image_ready_toggle) begin
                load_busy <= 0;
                awaiting_display <= 0;
                disp_buf_idx <= pending_buf_idx;
                img_idx <= load_idx;
                display_valid <= 1;
                first_image_committed <= 1;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (key_next_press && scan_kicked && (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;

                // 自动播放开/关
                if (key_auto_press && scan_kicked && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (key_auto_press || (MENU_CONTROL && menu_pause)) begin
                    auto_cnt <= 0;
                end else if (scan_kicked && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= auto_cnt; // Hold due request until reader accepts it.
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (!first_image_committed && bmp_ready && !load_busy && (img_found_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sectors[0];
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy <= 1'b1;
                    source_started <= 0; mem_done_seen <= 0;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_kicked && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 3'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy <= 1'b1;
                    source_started <= 0; mem_done_seen <= 0;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_kicked && bmp_ready && display_valid && !load_busy && auto_play_en && !key_auto_press && !(MENU_CONTROL && menu_pause) && auto_tick && (img_found_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy <= 1'b1;
                    source_started <= 0; mem_done_seen <= 0;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end else if(first_image_committed && !load_busy && bmp_ready && !scan_done) begin
                    scan_resume_pulse<=1;
                end
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_resume            (scan_resume_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

wire phy_req,phy_valid,phy_end,audio_req,audio_valid_sd,audio_end_sd;
wire [31:0] phy_addr,audio_addr;
sd_audio_loop music(.clk(clk),.rst(rst),.sd_init_done(sd_init_done),.can_read(music_can_read),
 .sec_req(audio_req),.sec_addr(audio_addr),.sec_data(sd_sec_read_data),
 .sec_valid(audio_valid_sd),.sec_end(audio_end_sd),.pcm_valid(music_pcm_valid),.pcm_data(music_pcm_data),.status(music_status));
sd_sector_arbiter arb(.clk(clk),.rst(rst),.image_req(sd_sec_read),.image_addr(sd_sec_read_addr),
 .image_valid(sd_sec_read_data_valid),.image_end(sd_sec_read_end),
 .audio_req(audio_req),.audio_addr(audio_addr),.audio_valid(audio_valid_sd),.audio_end(audio_end_sd),
 .req(phy_req),.addr(phy_addr),.valid(phy_valid),.finish(phy_end));
sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (phy_req),
    .sd_sec_read_addr       (phy_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (phy_valid),
    .sd_sec_read_end        (phy_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
