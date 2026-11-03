`timescale 1ns/1ps
module tb_campus;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ft=0,key=1,auto_mode=0,loading=0,visible=1;
 reg [5:0] fade=32;
 reg av=0;reg signed [23:0] sample=0;
 reg hs=0,vs=1,de=0;reg [23:0] rgb=24'hc08040;
 wire oh,ov,od;wire[23:0] pixel;
 campus_overlay #(.KEY_CLK_HZ(1000),.KEY_DEBOUNCE_MS(2)) dut
 (.clk(clk),.rst(rst),.frame_tick(ft),.key_brightness(key),.auto_mode_async(auto_mode),
 .loading_async(loading),.visible(visible),.fade_level(fade),.audio_valid(av),.audio_sample(sample),
 .in_hs(hs),.in_vs(vs),.in_de(de),.in_rgb(rgb),.out_hs(oh),.out_vs(ov),.out_de(od),.out_rgb(pixel));
 wire axis_user,axis_valid,axis_last;wire[23:0] axis_data;
 video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(ov),.I_de(od),.I_rgb(pixel),
 .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_data));
 integer i,j,k,expected,f,cols=0,lines=0,sofs=0,pixels=0;
 reg capture=0;
 reg [2:0] de_expect=0;
 reg [1:0] hs_expect=0,vs_expect=0;
 always @(posedge clk) begin
  if(rst) begin de_expect<=0;hs_expect<=0;vs_expect<=0;end
  else begin de_expect<={de_expect[1:0],de};
   hs_expect<={hs_expect[0],hs};vs_expect<={vs_expect[0],vs};end
  #1;
  if(!rst && od!==de_expect[1]) $fatal(1,"Overlay DE latency mismatch");
  if(!rst && (oh!==hs_expect[1] || ov!==vs_expect[1])) $fatal(1,"HS/VS not aligned");
  if(capture && axis_valid) begin
   if(axis_user) sofs=sofs+1;
   if(axis_last !== (cols==639)) $fatal(1,"Line last mismatch x=%0d",cols);
   if(cols==320 && lines==200 && axis_data!==24'hc08040) $fatal(1,"Background RGB pipeline mismatch");
   cols=cols+1;pixels=pixels+1;
   if(axis_last) begin lines=lines+1;cols=0;end
   $fwrite(f,"%0d %0d %0d\n",axis_data[23:16],axis_data[15:8],axis_data[7:0]);
  end
 end
 task cycles(input integer n);repeat(n) @(negedge clk);endtask
 task tick;begin ft=1;cycles(1);ft=0;cycles(2);end endtask
 task press;begin key=0;cycles(10);key=1;cycles(10);end endtask
 task capture_audio(input signed [23:0] value);
 begin
  sample=value;av=1;cycles(1024);av=0;cycles(2);
  if(!dut.wave_ready) $fatal(1,"Wave not complete after 1024 samples");
 end endtask
 initial begin
  cycles(5);rst=0;cycles(520);
  for(i=0;i<4;i=i+1) for(j=0;j<256;j=j+1) begin
   expected=(j*(i+1))/4;
   if(dut.scale_brightness(j,i)!==expected[7:0]) $fatal(1,"Brightness math");
  end
  // Brief bounce cannot be accepted; one held press changes only once.
  key=0;cycles(1);key=1;cycles(8);tick();
  if(dut.brightness!=3) $fatal(1,"Bounce accepted");
  key=0;cycles(30);
  if(dut.brightness!=3) $fatal(1,"Brightness changed mid-frame");
  tick();if(dut.brightness!=0) $fatal(1,"First press must select 25 percent");
  cycles(30);tick();if(dut.brightness!=0) $fatal(1,"Held key repeated");
  key=1;cycles(10);
  for(i=1;i<4;i=i+1) begin press();tick();if(dut.brightness!=i) $fatal(1,"Brightness cycle");end
  $display("PASS brightness 1024 values, debounce, frame commit");
  capture_audio(0);
  for(i=256;i<512;i=i+1) if(dut.wave_mem[i]!={7'd48,7'd48}) $fatal(1,"Zero waveform");
  sample=24'sh7fffff;av=1;cycles(1024);av=0;
  if(dut.wave_mem[256]!={7'd48,7'd48}) $fatal(1,"Completed bank overwritten");
  tick();if(!dut.wave_valid || dut.display_bank!=1) $fatal(1,"Wave swap");
  capture_audio(24'sh7fffff);
  for(i=0;i<256;i=i+1) if(dut.wave_mem[i]!={7'd4,7'd4}) $fatal(1,"Positive clipping");
  tick();capture_audio(24'sh800000);
  for(i=256;i<512;i=i+1) if(dut.wave_mem[i]!={7'd92,7'd92}) $fatal(1,"Negative clipping");
  tick();
  for(i=0;i<1024;i=i+1) begin
   sample=((i/32)%2) ? -24'sd2000000 : 24'sd2000000;
   av=1;cycles(1);
  end
  av=0;cycles(2);tick();
  if(dut.wave_mem[0][13:7]!=18 || dut.wave_mem[8][13:7]!=79) $fatal(1,"Signed square wave mapping");
  if(dut.wave_mem[8][6:0]!=18) $fatal(1,"Adjacent point connection");
  $display("PASS audio zero, full scales, decimation, frozen bank, square wave");
  for(i=0;i<800;i=i+1) tick();
  if(dut.scroll==0) $fatal(1,"Subtitle did not scroll");
  f=$fopen("preview.ppm","w");$fwrite(f,"P3\n640 480\n255\n");
  capture=1;vs=0;cycles(10);vs=1;cycles(10);
  for(j=0;j<480;j=j+1) begin
   de=1;cycles(640);de=0;cycles(160);
  end
  cycles(10);capture=0;$fclose(f);
  if(pixels!=307200 || lines!=480 || sofs!=1) $fatal(1,"Frame totals %0d %0d %0d",pixels,lines,sofs);
  $display("PASS 640x480, one SOF, 480 EOL, aligned two-stage pipeline; preview.ppm");
  $finish;
 end
 initial begin #10000000;$fatal(1,"Timeout");end
endmodule
