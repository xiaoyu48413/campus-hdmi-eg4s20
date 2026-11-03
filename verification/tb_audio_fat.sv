`timescale 1ns/1ps
module tb_audio_fat;
reg clk=0;always #5 clk=~clk;
reg rst=1;
wire req,valid,end_sector,pcm_valid;wire[31:0] addr,pcm;
wire[3:0] status;
reg [7:0] data;reg dv=0,fin=0;
wire phy_req;wire [31:0] phy_addr;wire img_valid,img_end;
integer tick=0;wire capacity=(tick%2000)<1500;
sd_audio_loop dut(clk,rst,1'b1,capacity,req,addr,data,valid,end_sector,pcm_valid,pcm,status);
sd_sector_arbiter arb(clk,rst,1'b1,32'hdeadbeef,img_valid,img_end,req,addr,valid,end_sector,phy_req,phy_addr,dv,fin);
reg[7:0] wav[0:5767883];integer fd,n;
integer count=0,idx=0,gap=0,image_reads=0,cycles=0;
reg active=0;reg [31:0] sector;
function [7:0] byte32(input integer v,input integer b);byte32=(v>>(b*8))&255;endfunction
function [7:0] disk(input integer sec,input integer off);
 integer cl,fe,fileoff,ent;
 begin
  disk=0;
  if(sec==0) begin
   case(off)
    0:disk=8'heb;11,12:disk=byte32(512,off-11);13:disk=8;
    14:disk=32;16:disk=1;32,33,34,35:disk=byte32(800000,off-32);
    36,37,38,39:disk=byte32(1024,off-36);44:disk=2;510:disk=8'h55;511:disk=8'haa;
   endcase
  end else if(sec>=32 && sec<1056) begin
   fe=(sec-32)*128+off/4;
   if(fe>=100 && ((fe-100)%2)==0) disk=byte32(fe+2,off%4);
  end else if(sec==1056) begin
   // deleted matching name must not be used; second entry is live 01.WAV.
   ent=off/32;
   if(ent<2) case(off%32)
    0:disk=ent==0?8'he5:"0";1:disk="1";
    2,3,4,5,6,7:disk=" ";8:disk="W";9:disk="A";10:disk="V";11:disk=32;
    26:disk=ent==0?8'd50:8'd100;
    28,29,30,31:disk=byte32(n,off%32-28);
   endcase
  end else if(sec>=1056 && sec!=32'hdeadbeef) begin
   cl=(sec-1056)/8+2;
   if(cl>=100 && (cl-100)%2==0) begin
    fileoff=((cl-100)/2*8+(sec-1056)%8)*512+off;
    disk=fileoff<n ? wav[fileoff] : 8'hde;
   end else disk=8'hde;
  end
 end
endfunction
always @(negedge clk) begin
 tick=tick+1;dv=0;fin=0;
 if(active) begin
  if(idx<512) begin data=disk(sector,idx);dv=1;idx=idx+1;end
  else begin fin=1;active=0;gap=3;end
 end else if(gap>0) gap=gap-1;
 else if(phy_req && !rst) begin
  sector=phy_addr;idx=0;active=1;
  if(phy_addr==32'hdeadbeef) image_reads=image_reads+1;
 end
end
always @(posedge clk) begin
 #1;
 if(status==14) $fatal(1,"Audio FAT error state %d",dut.reader.state);
 if(pcm_valid) begin
  if(pcm!=={wav[44+(count%1441960)*4+3],wav[44+(count%1441960)*4+2],wav[44+(count%1441960)*4+1],wav[44+(count%1441960)*4]}) $fatal(1,"Audio data mismatch %d",count);
  count=count+1;
  if(count==1441960+1024) begin
   if(image_reads<10) $fatal(1,"Images starved");
   $display("PASS actual WAV FAT32 fragmented clusters, deleted entry, exact loop samples, capacity stalls and concurrent image sectors (%d)",image_reads);$finish;
  end
 end
end
initial begin fd=$fopen("test_audio.wav","rb");n=$fread(wav,fd);$fclose(fd);repeat(5) @(negedge clk);rst=0;end
initial begin #500000000;$fatal(1,"Timeout %d %d",count,dut.reader.state);end
endmodule
