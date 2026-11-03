from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
H=ROOT/'src/user_source/hdl_source'
p=H/'SD/bmp_read.v'
s=p.read_text(encoding='utf-8-sig')
assert 'AUDIO_MODE' not in s
s=s.replace('module bmp_read(', 'module bmp_read #(parameter AUDIO_MODE=0)(')
s=s.replace('output [23:0]               bmp_data','output [23:0]               bmp_data,\n    input audio_can_read, output reg pcm_valid, output reg [31:0] pcm_data')
s=s.replace('// Stream capture for the boot sector', '''reg wav_bad;
reg [31:0] wav_length;
always @(posedge clk or posedge rst) begin
 if(rst) begin wav_bad<=0;wav_length<=0;end
 else if(state==HEADER_READ && sd_sec_read_data_valid) begin
  if(byte_index==0) wav_bad <= sd_sec_read_data!="R";
  else case(byte_index)
   1:if(sd_sec_read_data!="I") wav_bad<=1;
   2,3:if(sd_sec_read_data!="F") wav_bad<=1;
   8:if(sd_sec_read_data!="W") wav_bad<=1;
   9:if(sd_sec_read_data!="A") wav_bad<=1;
   10:if(sd_sec_read_data!="V") wav_bad<=1;
   11:if(sd_sec_read_data!="E") wav_bad<=1;
   12:if(sd_sec_read_data!="f") wav_bad<=1;
   13:if(sd_sec_read_data!="m") wav_bad<=1;
   14:if(sd_sec_read_data!="t") wav_bad<=1;
   15:if(sd_sec_read_data!=" ") wav_bad<=1;
   16:if(sd_sec_read_data!=16) wav_bad<=1;
   20:if(sd_sec_read_data!=1) wav_bad<=1;
   22:if(sd_sec_read_data!=2) wav_bad<=1;
   24:if(sd_sec_read_data!=8'h80) wav_bad<=1;
   25:if(sd_sec_read_data!=8'hbb) wav_bad<=1;
   28:if(sd_sec_read_data!=0) wav_bad<=1;
   29:if(sd_sec_read_data!=8'hee) wav_bad<=1;
   30:if(sd_sec_read_data!=2) wav_bad<=1;
   32:if(sd_sec_read_data!=4) wav_bad<=1;
   34:if(sd_sec_read_data!=16) wav_bad<=1;
   17,18,19,21,23,26,27,31,33,35:if(sd_sec_read_data!=0) wav_bad<=1;
   36:if(sd_sec_read_data!="d") wav_bad<=1;
   37:if(sd_sec_read_data!="a") wav_bad<=1;
   38:if(sd_sec_read_data!="t") wav_bad<=1;
   39:if(sd_sec_read_data!="a") wav_bad<=1;
   40:wav_length[7:0]<=sd_sec_read_data;
   41:wav_length[15:8]<=sd_sec_read_data;
   42:wav_length[23:16]<=sd_sec_read_data;
   43:wav_length[31:24]<=sd_sec_read_data;
  endcase
 end
end
// Stream capture for the boot sector''')
s=s.replace('pixel_bytes<=(width==320)?230400:921600;', 'pixel_bytes<=AUDIO_MODE ? wav_length : ((width==320)?230400:921600);')
s=s.replace("pixel_end_q<={1'b0,pixel_offset}+{1'b0,pixel_bytes};", "pixel_end_q<=(AUDIO_MODE ? 33'd44 : {1'b0,pixel_offset})+{1'b0,pixel_bytes};")
s=s.replace('header_ok<=header0=="B"', "header_ok<=AUDIO_MODE ? (!wav_bad && wav_length!=0 && wav_length[1:0]==0 && !pixel_end_q[32] && candidate_size>=pixel_end_q[31:0]) : header0==\"B\"")
s=s.replace('reg [7:0] entry_first,entry_attr,ext0,ext1,ext2;', 'reg [7:0] entry_first,entry_attr,ext0,ext1,ext2;\nreg [63:0] entry_name;')
s=s.replace('entry_byte<=0;directory_addr', 'entry_byte<=0;entry_name<=0;directory_addr')
s=s.replace('ENTRY_BYTE: begin\n    case(entry_byte)', 'ENTRY_BYTE: begin\n    if(entry_byte<8) entry_name<={entry_name[55:0],directory_q};\n    case(entry_byte)')
s=s.replace('(ext0 & 8\'hdf)!="B" || (ext1 & 8\'hdf)!="M" || (ext2 & 8\'hdf)!="P" ||', '''(AUDIO_MODE ? (entry_name!="01      " || (ext0 & 8'hdf)!="W" || (ext1 & 8'hdf)!="A" || (ext2 & 8'hdf)!="V") :
      ((ext0 & 8'hdf)!="B" || (ext1 & 8'hdf)!="M" || (ext2 & 8'hdf)!="P")) ||''')
s=s.replace('file_byte_count>=pixel_offset', "file_byte_count>=(AUDIO_MODE ? 32'd44 : pixel_offset)")
s=s.replace('bmp_scale2x u_scaler', 'generate if(!AUDIO_MODE) begin: image_scaler\nbmp_scale2x u_scaler')
s=s.replace('.overflow(scale_error));', '''.overflow(scale_error));
end else begin: audio_capacity
 assign scale_idle=audio_can_read;assign scale_error=0;
 assign bmp_data_wr_en=0;assign bmp_data=0;
end endgenerate
reg [1:0] pcm_phase;
reg [23:0] pcm_pack;
always @(posedge clk or posedge rst) begin
 if(rst) begin pcm_valid<=0;pcm_data<=0;pcm_phase<=0;pcm_pack<=0;end
 else begin
  pcm_valid<=0;
  if(write_req && write_req_ack) pcm_phase<=0;
  if(AUDIO_MODE && pixel_input) begin
   pcm_phase<=pcm_phase+1'b1;
   case(pcm_phase)
    0:pcm_pack[7:0]<=sd_sec_read_data;
    1:pcm_pack[15:8]<=sd_sec_read_data;
    2:pcm_pack[23:16]<=sd_sec_read_data;
    3:begin pcm_data<={sd_sec_read_data,pcm_pack};pcm_valid<=1;end
   endcase
  end
 end
end''')
s=s.replace('sd_sec_read<=!scale2x || scale_idle;', 'sd_sec_read<=AUDIO_MODE ? audio_can_read : (!scale2x || scale_idle);')
s=s.replace('scale2x<=(width==320)', 'scale2x<=!AUDIO_MODE && (width==320)')
p.write_text(s,encoding='utf-8')
