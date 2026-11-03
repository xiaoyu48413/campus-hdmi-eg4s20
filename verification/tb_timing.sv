`timescale 1ns/1ps
module tb_timing;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ack=0;
 wire ft,req,hs,vs,de;
 video_timing_data dut(.video_clk(clk),.rst(rst),.frame_tick(ft),.read_req(req),.read_req_ack(ack),.hs(hs),.vs(vs),.de(de));
 integer tick_cycle=-1,cycle=0,frames=0,ack_count=0;
 reg old_req=0;
 always @(posedge clk) begin
  if(!rst) begin
   if(ft) begin tick_cycle=cycle;frames=frames+1;end
   #1;
   if(req && !old_req) begin
    if(cycle-tick_cycle!=8 || de) $fatal(1,"Read request must follow blank frame tick by 8 clocks");
    ack_count=4;
   end
   old_req=req;
   if(ack_count>0) begin ack_count=ack_count-1;if(ack_count==0) ack=1;end
   if(!req) ack=0;
   cycle=cycle+1;
   if(frames==3 && cycle-tick_cycle==20) begin
    if(req) $fatal(1,"Read request not cleared by synchronized ack");
    $display("PASS actual VGA timing: frame-tick blanking, eight-clock index settling, read handshake");$finish;
   end
  end
 end
 initial begin repeat(5) @(negedge clk);rst=0;#20000000;$fatal(1,"Timeout");end
endmodule
