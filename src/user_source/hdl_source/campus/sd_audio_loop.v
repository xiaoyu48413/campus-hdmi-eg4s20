// Independent FAT32 reader for canonical 01.WAV; sector-level arbitration is external.
module sd_audio_loop(input clk,rst,sd_init_done,input can_read,
 output sec_req,output [31:0] sec_addr,input [7:0] sec_data,input sec_valid,sec_end,
 output pcm_valid,output [31:0] pcm_data,output [3:0] status);
reg [1:0] control;
reg scan_start,load_start;
wire ready,scan_done,write_req;
wire [3:0] count;
always @(posedge clk or posedge rst) begin
 if(rst) begin control<=0;scan_start<=0;load_start<=0;end
 else begin
  scan_start<=0;load_start<=0;
  case(control)
   0:if(sd_init_done) begin scan_start<=1;control<=1;end
   1:if(scan_done && count!=0 && ready) begin load_start<=1;control<=2;end
   2:if(!ready) control<=3;
   3:if(ready) begin load_start<=1;control<=2;end
  endcase
 end
end
bmp_read #(.AUDIO_MODE(1)) reader(.clk(clk),.rst(rst),.ready(ready),
 .scan_start(scan_start),.scan_resume(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),
 .scan_target_count(4'd1),.scan_done(scan_done),.scan_found_valid(),.scan_found_sector(),.scan_found_total(count),
 .load_start(load_start),.load_sector(32'd0),.sd_init_done(sd_init_done),.state_code(status),
 .bmp_width(16'd0),.bmp_height(16'd0),.write_req(write_req),.write_req_ack(write_req),
 .sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),.sd_sec_read_data(sec_data),
 .sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),.bmp_data_wr_en(),.bmp_data(),
 .audio_can_read(can_read),.pcm_valid(pcm_valid),.pcm_data(pcm_data));
endmodule

module sd_sector_arbiter(input clk,rst,
 input image_req,input [31:0] image_addr,output image_valid,image_end,
 input audio_req,input [31:0] audio_addr,output audio_valid,audio_end,
 output req,output reg [31:0] addr,input valid,finish);
reg [1:0] state;
reg owner;
assign req=(state==1) && !finish;
assign image_valid=state==1 && !owner && valid;
assign audio_valid=state==1 && owner && valid;
assign image_end=state==1 && !owner && finish;
assign audio_end=state==1 && owner && finish;
always @(posedge clk or posedge rst) begin
 if(rst) begin state<=0;owner<=0;addr<=0;end
 else case(state)
  0:if(audio_req || image_req) begin
   owner<=audio_req;addr<=audio_req ? audio_addr:image_addr;state<=1;
  end
  1:if(finish) state<=2;
  2:state<=3;
  3:state<=0;
 endcase
end
endmodule
