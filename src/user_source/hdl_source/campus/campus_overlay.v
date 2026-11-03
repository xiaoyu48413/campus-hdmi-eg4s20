module campus_overlay #(
 parameter KEY_CLK_HZ=25000000,
 parameter KEY_DEBOUNCE_MS=20
)(
 input clk,rst,frame_tick,key_brightness,auto_mode_async,loading_async,visible,
 input [5:0] fade_level,
 input audio_valid,
 input signed [23:0] audio_sample,
 input in_hs,in_vs,in_de,
 input [23:0] in_rgb,
 output reg out_hs,out_vs,out_de,
 output reg [23:0] out_rgb
);
wire key_press;
key_press_debounce #(.CLK_FREQ_HZ(KEY_CLK_HZ),.DEBOUNCE_MS(KEY_DEBOUNCE_MS)) u_brightness_key
 (.clk(clk),.rst(rst),.button_in(key_brightness),.press_pulse(key_press));
reg [1:0] requested_brightness,brightness;
reg [1:0] auto_sync,loading_sync;
reg auto_mode,loading;
reg vs_d,de_d;
reg [9:0] x,y;
reg [10:0] scroll;
reg scroll_half;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  requested_brightness<=3;brightness<=3;auto_sync<=0;loading_sync<=3;
  auto_mode<=0;loading<=1;vs_d<=0;de_d<=0;x<=0;y<=0;scroll<=0;scroll_half<=0;
 end else begin
  auto_sync<={auto_sync[0],auto_mode_async};loading_sync<={loading_sync[0],loading_async};
  if(key_press) requested_brightness<=requested_brightness+1'b1;
  if(frame_tick) begin
   brightness<=requested_brightness;auto_mode<=auto_sync[1];loading<=loading_sync[1];
   scroll_half<=~scroll_half;
   if(scroll_half) scroll <= (scroll==1503) ? 0 : scroll+1'b1;
  end
  vs_d<=in_vs;de_d<=in_de;
  if(vs_d!=in_vs) begin x<=0;y<=0;end
  else begin
   if(in_de) x <= (x==639) ? 0 : x+1'b1;
   else x<=0;
   if(de_d && !in_de) y<=y+1'b1;
  end
 end
end

// One bank is displayed, the other frozen on completion until frame-boundary exchange.
// Each entry contains two adjacent amplitudes, allowing one RAM read per pixel.
reg [13:0] wave_mem [0:511];
reg [8:0] clear_addr;
reg clearing;
reg write_bank,display_bank,wave_ready,wave_valid;
reg [7:0] sample_index;
reg [1:0] decimate;
reg [6:0] previous_y;
wire signed [7:0] amplitude = audio_sample[23:16];
wire [6:0] sample_y = (amplitude>44) ? 7'd4 :
                           (amplitude < -44) ? 7'd92 : (8'sd48-amplitude);
always @(posedge clk or posedge rst) begin
 if(rst) begin
  clear_addr<=0;clearing<=1;write_bank<=1;display_bank<=0;
  wave_ready<=0;wave_valid<=0;sample_index<=0;decimate<=0;previous_y<=48;
 end else if(clearing) begin
  if(clear_addr==511) clearing<=0;
  clear_addr<=clear_addr+1'b1;
 end else if(wave_ready) begin
  if(frame_tick) begin
   display_bank<=write_bank;write_bank<=~write_bank;
   wave_ready<=0;wave_valid<=1;sample_index<=0;decimate<=0;previous_y<=48;
  end
 end else if(audio_valid) begin
  decimate<=decimate+1'b1;
  if(decimate==3) begin
   previous_y<=sample_y;
   if(sample_index==255) wave_ready<=1;
   else sample_index<=sample_index+1'b1;
  end
 end
end
// No asynchronous reset on RAM: sequential initialization retains BRAM inference.
always @(posedge clk) begin
 if(clearing) wave_mem[clear_addr]<={7'd48,7'd48};
 else if(!rst && !wave_ready && audio_valid && decimate==3)
  wave_mem[{write_bank,sample_index}] <= {sample_y,(sample_index==0 ? sample_y : previous_y)};
end
wire [7:0] wave_x=x-368;
reg [13:0] wave_pair;
always @(posedge clk) wave_pair <= wave_mem[{display_bank,wave_x}];

// Generated preset lookup function, embedded by build script.
function [6:0] glyph; input [2:0] message; input [5:0] pos; begin glyph=0; case(message)
0: case(pos)
0: glyph=7'd0;
1: glyph=7'd1;
2: glyph=7'd2;
3: glyph=7'd3;
4: glyph=7'd4;
5: glyph=7'd5;
6: glyph=7'd6;
7: glyph=7'd7;
8: glyph=7'd8;
9: glyph=7'd9;
10: glyph=7'd10;
11: glyph=7'd11;
12: glyph=7'd12;
13: glyph=7'd13;
14: glyph=7'd14;
15: glyph=7'd15;
16: glyph=7'd16;
17: glyph=7'd17;
18: glyph=7'd18;
19: glyph=7'd19;
20: glyph=7'd20;
21: glyph=7'd11;
22: glyph=7'd21;
23: glyph=7'd22;
24: glyph=7'd23;
25: glyph=7'd24;
26: glyph=7'd25;
27: glyph=7'd26;
28: glyph=7'd14;
29: glyph=7'd27;
30: glyph=7'd28;
31: glyph=7'd29;
32: glyph=7'd30;
33: glyph=7'd11;
34: glyph=7'd31;
35: glyph=7'd2;
36: glyph=7'd3;
37: glyph=7'd32;
38: glyph=7'd33;
39: glyph=7'd0;
40: glyph=7'd1;
41: glyph=7'd34;
42: glyph=7'd12;
43: glyph=7'd13;
44: glyph=7'd35;
45: glyph=7'd36;
46: glyph=7'd37;
47: glyph=7'd38;
48: glyph=7'd11;
49: glyph=7'd21;
50: glyph=7'd22;
51: glyph=7'd39;
52: glyph=7'd40;
53: glyph=7'd41;
default: glyph=7'd53; endcase
1: case(pos)
0: glyph=7'd42;
1: glyph=7'd17;
2: glyph=7'd43;
3: glyph=7'd44;
4: glyph=7'd45;
5: glyph=7'd46;
default: glyph=7'd53; endcase
2: case(pos)
0: glyph=7'd47;
1: glyph=7'd48;
2: glyph=7'd49;
3: glyph=7'd50;
4: glyph=7'd51;
5: glyph=7'd52;
6: glyph=7'd53;
7: glyph=7'd54;
8: glyph=7'd55;
9: glyph=7'd56;
default: glyph=7'd53; endcase
3: case(pos)
0: glyph=7'd47;
1: glyph=7'd48;
2: glyph=7'd49;
3: glyph=7'd50;
4: glyph=7'd51;
5: glyph=7'd52;
6: glyph=7'd53;
7: glyph=7'd55;
8: glyph=7'd57;
9: glyph=7'd56;
default: glyph=7'd53; endcase
4: case(pos)
0: glyph=7'd47;
1: glyph=7'd48;
2: glyph=7'd49;
3: glyph=7'd50;
4: glyph=7'd51;
5: glyph=7'd52;
6: glyph=7'd53;
7: glyph=7'd58;
8: glyph=7'd55;
9: glyph=7'd56;
default: glyph=7'd53; endcase
5: case(pos)
0: glyph=7'd47;
1: glyph=7'd48;
2: glyph=7'd49;
3: glyph=7'd50;
4: glyph=7'd51;
5: glyph=7'd52;
6: glyph=7'd53;
7: glyph=7'd59;
8: glyph=7'd57;
9: glyph=7'd57;
10: glyph=7'd56;
default: glyph=7'd53; endcase
6: case(pos)
0: glyph=7'd60;
1: glyph=7'd61;
2: glyph=7'd62;
3: glyph=7'd63;
4: glyph=7'd61;
5: glyph=7'd64;
default: glyph=7'd53; endcase
7: case(pos)
0: glyph=7'd61;
1: glyph=7'd63;
2: glyph=7'd52;
3: glyph=7'd65;
default: glyph=7'd53; endcase
endcase end endfunction

reg [2:0] message;
reg [5:0] char_pos;
reg [3:0] glyph_row,glyph_col;
reg text_region;
wire [11:0] scroll_x={2'b0,x}+{1'b0,scroll};
wire [11:0] text_x=scroll_x-640;
always @* begin
 message=0;char_pos=0;glyph_row=0;glyph_col=0;text_region=0;
 if(y>=456 && y<472 && scroll_x>=640 && scroll_x<1504) begin
  text_region=1;message=0;char_pos=text_x[9:4];glyph_row=y-456;glyph_col=text_x[3:0];
 end
 if(x>=16 && x<192 && y>=16 && y<32) begin
  text_region=1;message=2+brightness;char_pos=(x-16)>>4;glyph_row=y-16;glyph_col=x[3:0];
 end
 if(x>=16 && x<112 && y>=40 && y<56) begin
  text_region=1;message=auto_mode ? 7 : 6;char_pos=(x-16)>>4;glyph_row=y-40;glyph_col=x[3:0];
 end
 if(!visible && x>=256 && x<384 && y>=224 && y<240) begin
  text_region=1;message=1;char_pos=(x-256)>>4;glyph_row=y-224;glyph_col=x[3:0];
 end
 if(visible && loading && x>=16 && x<144 && y>=72 && y<88) begin
  text_region=1;message=1;char_pos=(x-16)>>4;glyph_row=y-72;glyph_col=x[3:0];
 end
end
wire [10:0] font_addr={glyph(message,char_pos),glyph_row};
wire [15:0] font_bits;
campus_font u_font(.clk(clk),.addr(font_addr),.bits(font_bits));
function [7:0] scale_brightness;
 input [7:0] value;input [1:0] level;
 reg [9:0] wide;
 begin
  case(level)
   0:wide={2'b0,value};
   1:wide={1'b0,value,1'b0};
   2:wide={1'b0,value,1'b0}+{2'b0,value};
   default:wide={value,2'b0};
  endcase
  scale_brightness=wide[9:2];
 end
endfunction
reg [23:0] rgb1;
reg hs1,vs1,de1,text1,band1,osd1,wave1,border1,valid1;
reg [3:0] col1;
reg [6:0] wy1;
reg [5:0] fade1;
wire [13:0] fade_r=rgb1[23:16]*fade1;
wire [13:0] fade_g=rgb1[15:8]*fade1;
wire [13:0] fade_b=rgb1[7:0]*fade1;
wire [6:0] ymin=(wave_pair[13:7]<wave_pair[6:0]) ? wave_pair[13:7] : wave_pair[6:0];
wire [6:0] ymax=(wave_pair[13:7]>wave_pair[6:0]) ? wave_pair[13:7] : wave_pair[6:0];
always @(posedge clk or posedge rst) begin
 if(rst) begin
  rgb1<=0;hs1<=0;vs1<=0;de1<=0;text1<=0;band1<=0;osd1<=0;wave1<=0;border1<=0;
  col1<=0;wy1<=0;fade1<=0;valid1<=0;
  out_rgb<=0;out_hs<=0;out_vs<=0;out_de<=0;
 end else begin
  rgb1<={scale_brightness(in_rgb[23:16],brightness),scale_brightness(in_rgb[15:8],brightness),scale_brightness(in_rgb[7:0],brightness)};
  fade1<=fade_level;hs1<=in_hs;vs1<=in_vs;de1<=in_de;
  text1<=text_region;col1<=glyph_col;valid1<=wave_valid;
  band1<=(y>=448 && y<480);
  osd1<=((x>=8 && x<200 && y>=8 && y<64) || (!visible && x>=248 && x<392 && y>=216 && y<248)
          || (visible && loading && x>=8 && x<152 && y>=64 && y<96));
  wave1<=(x>=368 && x<624 && y>=16 && y<112);
  border1<=(x==368 || x==623 || y==16 || y==111);
  wy1<=y-16;
  out_hs<=hs1;out_vs<=vs1;out_de<=de1;
  out_rgb<={fade_r[12:5],fade_g[12:5],fade_b[12:5]};
  if(band1 || osd1) out_rgb<=24'h102030;
  if(wave1) begin
   out_rgb<=24'h081820;
   if(wy1==48) out_rgb<=24'h405060;
   if(valid1 && wy1>=ymin && wy1<=ymax) out_rgb<=24'h40ff80;
   if(border1) out_rgb<=24'h7090a0;
  end
  if(text1 && font_bits[15-col1]) out_rgb<=24'hffffff;
  if(!de1) out_rgb<=0;
 end
end
endmodule
