`timescale 1ns/1ps
module tb_ten_catalog;
parameter QUICK_MULTI=0;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,resume_scan=0,load=0;
reg [31:0] handle=0;
wire ready,done,found,wreq,sec_req,pvalid;wire[31:0] found_handle,sec_addr;
wire[3:0] count;wire[3:0] code;wire[23:0] pixel;
reg ack=0;reg[7:0] data=0;reg dv=0,se=0;
bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(start),.scan_resume(resume_scan),
 .scan_start_sector(32'd0),.scan_max_sector(32'd131071),.scan_target_count(4'd10),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_handle),.scan_found_total(count),
 .load_start(load),.load_sector(handle),.sd_init_done(1'b1),.state_code(code),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(wreq),.write_req_ack(ack),
 .sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(dv),.sd_sec_read_end(se),.bmp_data_wr_en(pvalid),.bmp_data(pixel));
integer mode=0,vol_base=2048,data_base=4128,fat_base=2080;
integer spc_test=1,vol_total=100000;
integer reads=0,bidx=0,cool=0,pixels=0,which=0,xx,yy,expected;
integer deleted_reads=0,dir_fat_reads=0,file_fat_reads=0;
reg active=0;reg[31:0] request_addr;
reg check_pixels=0;
function [7:0] b32(input integer value,input integer pos);b32=(value>>(8*pos))&255;endfunction

function [31:0] fat_entry(input integer cl);
 begin
  fat_entry=32'h0;
  if(cl==2) fat_entry=7;
  else if(cl==7) fat_entry=32'h0fffffff;
  else if(cl>=1000 && cl<=1900 && (cl-1000)%2==0) begin
   if(mode==4) fat_entry=32'h0fffffff;
   else if(mode==5) fat_entry=32'h0ffffff7;
   else fat_entry=(cl==1900)?32'h0fffffff:cl+2;
  end else if(cl>=3000 && cl<=8400 && (cl-3000)%3==0)
   fat_entry=(cl==8400)?32'h0fffffff:cl+3;
 end
endfunction

// Root cluster 2 ends with the first valid image; root continues at non-adjacent cluster 7.
function [7:0] dir_byte(input integer cluster,input integer off);
 integer e,b;
 begin
 e=off/32;b=off%32;dir_byte=0;
 if(cluster==2 && e<10) case(b)
  0:dir_byte="P";1:dir_byte="0"+e;
  2,3,4,5,6,7:dir_byte=" ";8:dir_byte="B";9:dir_byte="M";10:dir_byte="P";11:dir_byte=32;
  20:dir_byte=0;21:dir_byte=0;26:dir_byte=8'he8;27:dir_byte=3;
  28,29,30,31:dir_byte=b32(230470,b-28);
 endcase
 end
endfunction

function [7:0] bmp_byte(input integer n,input integer b);
 integer w,h,offset,len,pi,x,y,channel;
 begin
  w=(n==0)?320:640;h=(n==0)?240:480;offset=(n==0)?70:54;len=offset+w*h*3;
  bmp_byte=0;
  case(b)
   0:bmp_byte="B";1:bmp_byte="M";
   2,3,4,5:bmp_byte=b32(len,b-2);
   10,11,12,13:bmp_byte=b32(offset,b-10);
   14:bmp_byte=40;18,19,20,21:bmp_byte=b32(w,b-18);
   22,23,24,25:bmp_byte=b32(h,b-22);26:bmp_byte=1;28:bmp_byte=24;
   default:if(b>=offset && b<len) begin
    pi=(b-offset)/3;channel=(b-offset)%3;x=pi%w;y=pi/w;
    case(channel) 0:bmp_byte=(x^y)&255;1:bmp_byte=y&255;2:bmp_byte=x&255;endcase
   end
  endcase
 end
endfunction

function [7:0] disk_byte(input integer sector,input integer off);
 integer cl,fe,entry_base,sector_in_cluster;
 begin
  disk_byte=0;
  if(mode==3) disk_byte=bmp_byte(0,(sector*512+off)); // raw BMP remnants; no valid filesystem
  else if(mode!=1 && sector==0) begin
   entry_base=(mode==6)?462:446; // mode6 FAT32 is SECOND primary partition
   if(off==entry_base+4) disk_byte=8'h0c;
   if(off>=entry_base+8 && off<entry_base+12) disk_byte=b32(vol_base,off-entry_base-8);
   if(off>=entry_base+12 && off<entry_base+16) disk_byte=b32(vol_total,off-entry_base-12);
   if(off==510) disk_byte=8'h55;if(off==511) disk_byte=8'haa;
  end else if(sector==vol_base) begin
   case(off)
    0:disk_byte=8'heb;11,12:disk_byte=b32(512,off-11);13:disk_byte=spc_test;
    14:disk_byte=32;16:disk_byte=2;
    32,33,34,35:disk_byte=b32(vol_total,off-32);
    36,37,38,39:disk_byte=b32(mode==7 ? 32'hffffffff : 1024,off-36);
    40:disk_byte=(mode==1)?8'h81:0;
    44:disk_byte=2;510:disk_byte=8'h55;511:disk_byte=8'haa;
   endcase
  end else if(sector>=fat_base && sector<fat_base+1024) begin
   fe=(sector-fat_base)*128+off/4;disk_byte=b32(fat_entry(fe),off%4);
  end else if(sector>=data_base) begin
   cl=(sector-data_base)/spc_test+2;sector_in_cluster=(sector-data_base)%spc_test;
   if(cl==2 || cl==7) disk_byte=dir_byte(cl,off);
   else if(cl==3 || cl==4) disk_byte=bmp_byte(0,off); // stale/hidden BMP contents
   else if(cl==5) disk_byte=8'hff;
   else if(cl>=1000 && cl<=1900 && (cl-1000)%2==0) disk_byte=bmp_byte(0,(((cl-1000)/2)*spc_test+sector_in_cluster)*512+off);
   else if(cl>=3000 && cl<=8400 && (cl-3000)%3==0) disk_byte=bmp_byte(1,(((cl-3000)/3)*spc_test+sector_in_cluster)*512+off);
   else disk_byte=8'hde; // poison the gaps so linear reads cannot accidentally pass
  end
 end
endfunction

always @(negedge clk) begin
 ack=wreq;
 if(rst) begin active=0;bidx=0;cool=0;dv=0;se=0;reads=0;deleted_reads=0;dir_fat_reads=0;file_fat_reads=0;end
 else begin
  dv=0;se=0;
  if(active) begin
   if(bidx<512) begin data=disk_byte(request_addr,bidx);dv=1;bidx=bidx+1;end
   else begin se=1;active=0;cool=3;end
  end else if(cool>0) cool=cool-1;
  else if(sec_req) begin
   request_addr=sec_addr;bidx=0;active=1;reads=reads+1;
   if(sec_addr==data_base+spc_test || sec_addr==data_base+2*spc_test) deleted_reads=deleted_reads+1;
   if(sec_addr==fat_base) dir_fat_reads=dir_fat_reads+1;
   if(sec_addr>fat_base && sec_addr<fat_base+1024) file_fat_reads=file_fat_reads+1;
   if(reads>10000) $fatal(1,"Read runaway");
  end
 end
end
always @(posedge clk) begin
 #1;
 if(check_pixels && pvalid) begin
  xx=(pixels%640)/(which==0?2:1);yy=(pixels/640)/(which==0?2:1);
  expected=((xx&255)<<16)|((yy&255)<<8)|((xx^yy)&255);
  if(pixel!==expected[23:0]) $fatal(1,"Fragmented BMP mismatch mode %0d pixel %0d got %h wanted %h",which,pixels,pixel,expected);
  pixels=pixels+1;if(pixels>307200) $fatal(1,"Too many pixels");
 end
 if(!rst && dut.scale_error) $fatal(1,"Scaler overflow");
end

integer hits=0;
always @(posedge clk) if(found) begin
 if(found_handle!=hits) $fatal(1,"Catalogue handle %d expected %d",found_handle,hits);
 hits=hits+1;
end
initial begin
 repeat(5) @(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 while(!done) begin
  @(negedge clk);resume_scan=ready && hits>0;
 end
 resume_scan=0;repeat(3) @(negedge clk);
 if(count!=10 || hits!=10) $fatal(1,"Ten file enumeration failed");
 handle=9;which=0;check_pixels=1;load=1;@(negedge clk);load=0;
 wait(!ready);wait(ready);repeat(4) @(negedge clk);
 if(pixels!=307200) $fatal(1,"Tenth image read failed %d",pixels);
 $display("PASS ten FAT32 BMP directory entries, handles 0..9, tenth image exact 307200 pixels");$finish;
end
initial begin #100000000;$fatal(1,"Timeout");end
endmodule
