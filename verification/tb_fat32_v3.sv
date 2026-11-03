`timescale 1ns/1ps
module tb_fat32_v3;
parameter QUICK_MULTI=0;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,resume_scan=0,load=0;
reg [31:0] handle=0;
wire ready,done,found,wreq,sec_req,pvalid;wire[31:0] found_handle,sec_addr;
wire[3:0] count;wire[3:0] code;wire[23:0] pixel;
reg ack=0;reg[7:0] data=0;reg dv=0,se=0;
bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(start),.scan_resume(resume_scan),
 .scan_start_sector(32'd0),.scan_max_sector(32'd131071),.scan_target_count(4'd4),
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
 integer e,b,cl,size,attr,first,ex0,ex1,ex2;
 begin
  e=off/32;b=off%32;cl=3;size=230470;attr=32;first=8'he5;ex0="B";ex1="M";ex2="P";
  if(cluster==2) begin
   case(e)
    0:begin first=8'he5;cl=3;end // deleted OLD.BMP: pixels still present
    1:begin first=8'h41;attr=8'h0f;cl=4;end // LFN helper
    2:begin first="D";attr=8'h10;cl=4;end // subdirectory
    3:begin first="T";ex0="T";ex1="X";ex2="T";cl=4;end
    4:begin first="H";attr=8'h22;cl=4;end // hidden file
    15:begin first="N";cl=1000;end // actual NEW320.BMP
   endcase
   if(mode==2 && e==1) first=0;
  end else begin
   case(e)
    0:begin first="B";cl=5;end // BMP extension but invalid BMP header
    1:begin first="N";cl=3000;size=921654;ex0="b";ex1="m";ex2="p";end
    default:first=0;
   endcase
  end
  dir_byte=0;
  case(b)
   0:dir_byte=first;
   1,2,3,4,5,6,7:dir_byte=8'h20;
   8:dir_byte=ex0;9:dir_byte=ex1;10:dir_byte=ex2;11:dir_byte=attr;
   20:dir_byte=b32(cl,2);21:dir_byte=b32(cl,3);
   26:dir_byte=b32(cl,0);27:dir_byte=b32(cl,1);
   28,29,30,31:dir_byte=b32(size,b-28);
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
task cycles(input integer n);repeat(n) @(posedge clk);#2;endtask
task boot(input integer m);
 begin
  mode=m;spc_test=(m==8)?8:1;vol_total=(m==8)?1000000:100000;vol_base=(m==1)?0:2048;data_base=vol_base+2080;fat_base=vol_base+32+((m==1)?1024:0);
  rst=1;start=0;resume_scan=0;load=0;check_pixels=0;cycles(5);rst=0;cycles(5);
  start=1;cycles(1);start=0;
 end
endtask
task first_image;
 begin
  wait(found || code==14 || done);cycles(2);
  if(code==14 || done || !ready || count!=1 || found_handle!=0 || deleted_reads!=0) $fatal(1,"Root enumeration failed mode=%0d",mode);
 end
endtask
task load_image(input integer n);
 begin
  which=n;pixels=0;check_pixels=1;handle=n;load=1;cycles(1);load=0;
  wait(!ready);wait(ready || code==14);cycles(5);
  if(code==14 || pixels!=307200) $fatal(1,"Incomplete frame mode=%0d pixels=%0d",mode,pixels);
  check_pixels=0;
 end
endtask
initial begin
 if(QUICK_MULTI) begin
  boot(8);first_image();load_image(0);
  if(file_fat_reads!=56) $fatal(1,"Eight-sector cluster traversal count %0d",file_fat_reads);
  $display("PASS 8-sector clusters: fragmented 320x240, internal sector increments, partial last cluster");$finish;
 end else begin
 boot(0);first_image();
 load_image(0);if(file_fat_reads<450) $fatal(1,"File chain not traversed");
 $display("PASS stale BMP bytes/deleted/LFN/hidden/directory/non-BMP entries ignored; fragmented 320x240 expanded exactly");
 resume_scan=1;cycles(1);resume_scan=0;wait(found || code==14);cycles(2);
 if(count!=2 || found_handle!=1 || dir_fat_reads<1 || deleted_reads!=0) $fatal(1,"Root directory chain/resume failed");
 load_image(1);
 $display("PASS fragmented root directory, invalid BMP skipped, fragmented 640x480 exact 307200 pixels");
 resume_scan=1;cycles(1);resume_scan=0;wait(done);cycles(2);
 if(count!=2 || code==14) $fatal(1,"Directory terminator not respected");
 boot(1);first_image();load_image(0);
 $display("PASS FAT32 superfloppy and active FAT #1 with FAT #0 poisoned");
 boot(2);wait(done || code==14);cycles(2);
 if(count!=0 || code!=12 || deleted_reads!=0) $fatal(1,"Deleted-only directory must be empty");
 $display("PASS deleted-only root: no image and no stale-sector fallback");
 boot(3);wait(code==14);if(reads!=1) $fatal(1,"Invalid volume raw-scanned");
 $display("PASS unrecognized volume fails closed (no raw fallback)");
 boot(4);first_image();handle=0;load=1;cycles(1);load=0;wait(code==14);
 $display("PASS premature FAT end-of-chain rejected");
 boot(5);first_image();handle=0;load=1;cycles(1);load=0;wait(code==14);
 $display("PASS bad-cluster marker rejected");
 boot(6);first_image();$display("PASS FAT32 in second MBR primary partition");
 boot(7);wait(code==14);if(reads!=2) $fatal(1,"Overflowing geometry followed");
 $display("PASS overflowing FAT32 geometry rejected");
 $finish;
 end
end
initial begin #200000000;$fatal(1,"Timeout mode=%0d state=%0d code=%0d",mode,dut.state,code);end
endmodule
