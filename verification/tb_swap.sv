`timescale 1ns/1ps
module tb_swap;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ft=0,ready=0,read_ack=0;
 reg[1:0] idx=0;
 wire ack,visible;wire[1:0] display_idx;wire[5:0] fade;
 campus_swap dut(clk,rst,ft,ready,read_ack,idx,ack,visible,display_idx,fade);
 task cycles(input integer n);repeat(n) @(negedge clk);endtask
 task tick;begin ft=1;cycles(1);ft=0;cycles(20);end endtask
 integer i;
 initial begin
  cycles(4);rst=0;cycles(5);idx=0;#3;ready=1;cycles(5);
  if(visible || ack) $fatal(1,"Premature first display");
  tick();repeat(3) tick();
  if(ack || visible) $fatal(1,"No read acknowledgement, cannot show or release");
  read_ack=1;cycles(5);read_ack=0;tick();
  if(!visible) $fatal(1,"First frame missing");
  if(fade!=32) $fatal(1,"First image must appear without fade delay");
  if(ack!=ready) $fatal(1,"First release ack");
  idx=1;ready=0;cycles(8);
  if(display_idx!=0 || fade!=32) $fatal(1,"Changed between frames");
  tick();
  for(i=31;i>=0;i=i-1) begin
   tick();if(fade!=i || display_idx!=0 || ack!=1) $fatal(1,"Fade out/buffer ownership");
  end
  tick();if(display_idx!=1 || fade!=0) $fatal(1,"Black frame swap");
  repeat(3) tick();if(ack!=1) $fatal(1,"Released without new read ack");
  read_ack=1;cycles(5);read_ack=0;tick();
  repeat(32) tick();
  if(fade!=32 || ack!=0 || display_idx!=1) $fatal(1,"Second frame incomplete");
  $display("PASS immediate first image, frame-only swap, subsequent 32+32 fade, delayed old-buffer release");$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
