`timescale 1ns/1ps
module tb_wav;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,bv=0,sr=0;reg[7:0] bd;
wire br,sv,done,error;wire[23:0] l,r;
reg[7:0] mem[0:5767883];integer fd,n,idx=0,count=0,cycles=0;
wav_pcm_stream dut(clk,rst,start,bv,bd,br,sv,sr,l,r,done,error);
always @(negedge clk) begin
 cycles=cycles+1;
 sr=(cycles%7!=0);
 if(!rst && br && idx<n) begin bv=1;bd=mem[idx];end else bv=0;
end
always @(posedge clk) if(!rst) begin
 if(bv && br) idx=idx+1;
 if(error) $fatal(1,"WAV rejected");
 if(sv && sr) begin
  if(l!=={mem[44+count*4+1],mem[44+count*4],8'b0} || r!=={mem[44+count*4+3],mem[44+count*4+2],8'b0}) $fatal(1,"PCM mismatch %d",count);
  count=count+1;
 end
 if(done) begin if(count!=1441960) $fatal(1,"Sample count mismatch");$display("PASS actual 30-second WAV: %d stereo samples, byte order, 16-to-24 scaling, backpressure, EOF",count);$finish;end
end
initial begin fd=$fopen("test_audio.wav","rb");n=$fread(mem,fd);$fclose(fd);repeat(3) @(negedge clk);rst=0;end
initial begin #200000000;$fatal(1,"Timeout");end
endmodule
