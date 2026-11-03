`timescale 1ns/1ps
module tb_pcm_bridge;
reg sd=0,vid=0;always #10 sd=~sd;always #20 vid=~vid;
reg rst=1;reg valid=0;reg[31:0] data=0;
wire capacity,av,ov;wire[23:0] l,r;wire[31:0] underruns;
pcm_hdmi_bridge dut(sd,vid,rst,1'b1,valid,data,capacity,av,l,r,underruns,ov);
integer sent=0,got=0,t=0,vc=0,strobes=0,prev=0;
reg live=0;
always @(negedge sd) begin
 t=t+1;
 valid=!rst && capacity && (t%8==0);
 data=((32'h4000+(sent&8191))<<16) | (32'h2000+(sent&8191));
end
always @(posedge sd) if(valid) sent=sent+1;
always @(posedge vid) begin
 #1;
 if(!rst) begin
  vc=vc+1;
  if(av) begin
   strobes=strobes+1;
   if(prev && vc-prev!=520 && vc-prev!=521) $fatal(1,"Sample cadence");
   prev=vc;
   if(l!=0 || live) begin
    live=1;
    if(l!==((24'h200000+((got&8191)<<8))) || r!==((24'h400000+((got&8191)<<8)))) $fatal(1,"Mailbox sample %d got %h %h",got,l,r);
    got=got+1;
   end
  end
  if(ov || underruns) $fatal(1,"FIFO failure");
  if(got==2200) begin $display("PASS PCM FIFO wrapping, cross-clock mailbox, 48 kHz cadence and exact HDMI samples");$finish;end
 end
end
initial begin repeat(5) @(negedge vid);rst=0;end
initial begin #100000000;$fatal(1,"Timeout");end
endmodule

