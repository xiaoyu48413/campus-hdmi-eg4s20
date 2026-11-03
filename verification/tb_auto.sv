`timescale 1ns/1ps
// Isolate the original SD/sector engine; stimulate its documented completion interface.
// -i permits those unused engines to be absent; every consumed output is forced below.
module tb_auto;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,wr_done=0,ack=0;
 wire token,valid,loading;wire[1:0] index,write_index,display_index;
 sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_finish_toggle(wr_done),.display_ack_toggle(ack),.image_ready_toggle(token),
 .image_ready_index(index),.display_valid(valid),.image_loading(loading),
 .write_buf_idx(write_index),.disp_buf_idx(display_index),.write_req_ack(1'b0),.SD_MISO(1'b1));
 task cycles(input integer n);repeat(n) @(negedge clk);endtask
 integer i;
 initial begin
  force dut.sd_init_done=0;force dut.bmp_ready=1;force dut.scan_done=0;
  force dut.scan_found_valid=0;force dut.scan_found_sector=32'd100;
  force dut.key_next_press=0;force dut.key_auto_press=0;
  force dut.bmp_data_wr_en=0;force dut.bmp_data=0;
  cycles(4);rst=0;cycles(3);force dut.sd_init_done=1;cycles(4);
  for(i=0;i<10;i=i+1) begin force dut.scan_found_valid=1;cycles(1);force dut.scan_found_valid=0;cycles(2);end
  if(dut.img_found_count!=10) $fatal(1,"Ten entries not retained");
  for(i=0;i<10;i=i+1) if(dut.next_index_limited(i,10)!=((i+1)%10)) $fatal(1,"Ten-item wrap failure");
  cycles(4); // First image must start while scan_done is still low.
  if(!dut.load_busy || write_index!=0) $fatal(1,"Initial load missing");
  cycles(5);if(dut.source_done_seen) $fatal(1,"Initial ready incorrectly treated as done");
  force dut.bmp_ready=0;cycles(5);wr_done=1;cycles(5);
  if(token) $fatal(1,"Published before source completion");
  force dut.bmp_ready=1;cycles(5);
  if(token!=1 || !dut.load_busy || valid) $fatal(1,"Completion order or ownership");
  force dut.key_next_press=1;cycles(1);force dut.key_next_press=0;cycles(2);
  if(dut.next_req_pending) $fatal(1,"Busy next request queued");
  ack=1;cycles(6);force dut.scan_done=1;
  if(!valid || dut.load_busy || display_index!=0) $fatal(1,"First ack");
  force dut.key_next_press=1;cycles(1);force dut.key_next_press=0;cycles(4);
  if(write_index!=1 || !dut.load_busy) $fatal(1,"Did not select inactive buffer");
  force dut.bmp_ready=0;cycles(5);force dut.bmp_ready=1;cycles(5);
  if(token!=1) $fatal(1,"Published before SDRAM completion");
  wr_done=0;cycles(6);
  if(token!=0 || !dut.load_busy || display_index!=0) $fatal(1,"Second completion");
  ack=0;cycles(6);
  if(display_index!=1 || dut.load_busy) $fatal(1,"Second ack");
  force dut.key_auto_press=1;cycles(1);force dut.key_auto_press=0;
  force dut.bmp_ready=0;cycles(5010);
  if(!dut.auto_play_en || !dut.auto_tick) $fatal(1,"Auto due request lost while reader busy");
  force dut.bmp_ready=1;cycles(3);
  if(!dut.load_busy || dut.load_idx!=2) $fatal(1,"Auto did not advance to third picture");
  $display("PASS AUTO expiry retained through busy reader, next image starts on ready");$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
