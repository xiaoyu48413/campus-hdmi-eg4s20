module overlay_v5(input clk,rst,frame_tick,in_hs,in_vs,in_de,input[23:0] in_rgb,
 input visible,loading_async,auto_async,transition,menu_open,input[1:0] selection,
 input[3:0] volume,input[2:0] contrast,input[1:0] brightness,
 input[111:0] bars,peaks,
 output reg out_hs,out_vs,out_de,output reg[23:0] out_rgb);
reg[9:0] x,y;reg vsd,ded;
reg[10:0] scroll;reg half;
reg[1:0] loads,autos;
reg[111:0] bars_frame,peaks_frame;
reg light_style;reg[2:0] confirmation;reg[23:0] luminance_sum;
wire[9:0] luminance={2'b0,in_rgb[23:16]}+{1'b0,in_rgb[15:8],1'b0}+{2'b0,in_rgb[7:0]};
always @(posedge clk) begin
 if(rst) begin x<=0;y<=0;vsd<=0;ded<=0;scroll<=0;half<=0;loads<=3;autos<=0;bars_frame<=0;peaks_frame<=0;light_style<=0;confirmation<=0;luminance_sum<=0;end
 else begin
  vsd<=in_vs;ded<=in_de;loads<={loads[0],loading_async};autos<={autos[0],auto_async};
  if(vsd!=in_vs) begin x<=0;y<=0;end
  else begin if(in_de) x<=x==639?0:x+1'b1;else x<=0;if(ded&&!in_de) y<=y+1'b1;end
  if(in_de && y>=448 && y<480) luminance_sum<=luminance_sum+luminance[9:2];
  if(frame_tick) begin
   half<=~half;if(half) scroll<=scroll==1503?0:scroll+1'b1;
   bars_frame<=bars;peaks_frame<=peaks;luminance_sum<=0;
   if(transition) confirmation<=0;
   else if((!light_style && luminance_sum>2867200)||(light_style && luminance_sum<2293760)) begin
    if(confirmation==3) begin light_style<=!light_style;confirmation<=0;end
    else confirmation<=confirmation+1'b1;
   end else confirmation<=0;
  end
 end
end
function [7:0] subtitle(input [5:0] pos);begin case(pos)

0: subtitle=8'd0;
1: subtitle=8'd1;
2: subtitle=8'd2;
3: subtitle=8'd3;
4: subtitle=8'd4;
5: subtitle=8'd5;
6: subtitle=8'd6;
7: subtitle=8'd7;
8: subtitle=8'd8;
9: subtitle=8'd9;
10: subtitle=8'd10;
11: subtitle=8'd11;
12: subtitle=8'd12;
13: subtitle=8'd13;
14: subtitle=8'd14;
15: subtitle=8'd15;
16: subtitle=8'd16;
17: subtitle=8'd17;
18: subtitle=8'd18;
19: subtitle=8'd19;
20: subtitle=8'd20;
21: subtitle=8'd11;
22: subtitle=8'd21;
23: subtitle=8'd22;
24: subtitle=8'd23;
25: subtitle=8'd24;
26: subtitle=8'd25;
27: subtitle=8'd26;
28: subtitle=8'd14;
29: subtitle=8'd27;
30: subtitle=8'd28;
31: subtitle=8'd29;
32: subtitle=8'd30;
33: subtitle=8'd11;
34: subtitle=8'd31;
35: subtitle=8'd2;
36: subtitle=8'd3;
37: subtitle=8'd32;
38: subtitle=8'd33;
39: subtitle=8'd0;
40: subtitle=8'd1;
41: subtitle=8'd34;
42: subtitle=8'd12;
43: subtitle=8'd13;
44: subtitle=8'd35;
45: subtitle=8'd36;
46: subtitle=8'd37;
47: subtitle=8'd38;
48: subtitle=8'd11;
49: subtitle=8'd21;
50: subtitle=8'd22;
51: subtitle=8'd39;
52: subtitle=8'd40;
53: subtitle=8'd41;

default:subtitle=8'd53;endcase end endfunction

function[7:0] ascii_glyph(input[7:0] c);begin ascii_glyph=c-8'd32+8'd66;end endfunction
function[7:0] label_char(input[2:0] label,input[4:0] pos);
begin
 label_char=32;
 case(label)
 0:case(pos)
0:label_char=8'd86;
1:label_char=8'd79;
2:label_char=8'd76;
3:label_char=8'd85;
4:label_char=8'd77;
5:label_char=8'd69;
default:label_char=32;endcase
1:case(pos)
0:label_char=8'd67;
1:label_char=8'd79;
2:label_char=8'd78;
3:label_char=8'd84;
4:label_char=8'd82;
5:label_char=8'd65;
6:label_char=8'd83;
7:label_char=8'd84;
default:label_char=32;endcase
2:case(pos)
0:label_char=8'd66;
1:label_char=8'd82;
2:label_char=8'd73;
3:label_char=8'd71;
4:label_char=8'd72;
5:label_char=8'd84;
6:label_char=8'd78;
7:label_char=8'd69;
8:label_char=8'd83;
9:label_char=8'd83;
default:label_char=32;endcase
3:case(pos)
0:label_char=8'd77;
1:label_char=8'd65;
2:label_char=8'd78;
3:label_char=8'd85;
4:label_char=8'd65;
5:label_char=8'd76;
default:label_char=32;endcase
4:case(pos)
0:label_char=8'd65;
1:label_char=8'd85;
2:label_char=8'd84;
3:label_char=8'd79;
default:label_char=32;endcase
5:case(pos)
0:label_char=8'd76;
1:label_char=8'd79;
2:label_char=8'd65;
3:label_char=8'd68;
4:label_char=8'd73;
5:label_char=8'd78;
6:label_char=8'd71;
default:label_char=32;endcase
6:case(pos)
0:label_char=8'd66;
1:label_char=8'd82;
2:label_char=8'd84;
default:label_char=32;endcase
 endcase
end endfunction
function[7:0] percent_char(input[7:0] value,input[2:0] pos);begin
 case(pos)
 0:percent_char=value>=100?49:32;
 1:percent_char=value>=10 ? 48+(value%100)/10:32;
 2:percent_char=48+value%10;
 3:percent_char=37;
 default:percent_char=32;
 endcase
end endfunction
wire[11:0] sx={2'b0,x}+{1'b0,scroll};
wire[11:0] tx=sx-640;
reg text_region,sub_region;reg[7:0] gid,ch,value;reg[3:0] row,col;reg[4:0] pos;reg[2:0] label;
reg[1:0] menu_row;
always @* begin
 text_region=0;sub_region=0;gid=53;row=0;col=0;pos=0;ch=32;label=0;value=0;menu_row=0;
 if(y>=456 && y<472 && sx>=640 && sx<1504) begin
  text_region=1;sub_region=1;gid=subtitle(tx[9:4]);row=y-456;col=tx[3:0];
 end
 if(x>=16 && x<160 && ((y>=16&&y<32)||(y>=40&&y<56))) begin
  text_region=1;sub_region=0;pos=(x-16)>>4;col=x[3:0];row=y>=40?y-40:y-16;
  if(y<32) begin
   ch=label_char(6,pos);value=(brightness+8'd1)*25;
   if(pos>=4) ch=percent_char(value,pos-4);
  end else ch=label_char(autos[1]?4:3,pos);
  gid=ascii_glyph(ch);
 end
 if((!visible || loads[1]) && x>=16 && x<160 && y>=72 && y<88) begin
  text_region=1;sub_region=0;col=x[3:0];row=y-72;gid=ascii_glyph(label_char(5,(x-16)>>4));
 end
 if(menu_open && x>=176 && x<464 && y>=176 && y<272) begin
  menu_row=(y-176)>>5;pos=(x-176)>>4;
  if(y[4] && menu_row<3) begin
   text_region=1;sub_region=0;row=y[3:0];col=x[3:0];ch=label_char({1'b0,menu_row},pos);
   case(menu_row) 0:value=volume*10;1:value=(contrast+8'd2)*25;default:value=(brightness+8'd1)*25;endcase
   if(pos>=11) ch=percent_char(value,pos-11);
   gid=ascii_glyph(ch);
  end
 end
end
wire[31:0] font;
v5_font rom(clk,{gid,row},font);
reg hs1,vs1,de1,text1,sub1,band1,osd1,menu1,selected1,spectrum1;
reg[23:0] rgb1;reg[3:0] col1;reg[7:0] wx1;reg[6:0] wy1,bh1,pk1;
wire[7:0] wx=x-496;
wire[3:0] bar_index=wx[6:3];
function[23:0] panel(input[23:0] rgb,input light);integer c;begin
 for(c=0;c<3;c=c+1) panel[c*8+:8]={1'b0,rgb[c*8+1+:7]}+(light?8'd127:8'd0);
end endfunction
always @(posedge clk) begin
 if(rst) begin
  hs1<=0;vs1<=0;de1<=0;text1<=0;sub1<=0;band1<=0;osd1<=0;menu1<=0;selected1<=0;spectrum1<=0;
  rgb1<=0;col1<=0;wx1<=0;wy1<=0;bh1<=0;pk1<=0;out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;
 end else begin
  hs1<=in_hs;vs1<=in_vs;de1<=in_de;rgb1<=in_rgb;text1<=text_region;sub1<=sub_region;col1<=col;
  band1<=y>=448&&y<480;osd1<=x>=8&&x<168&&y>=8&&y<(loads[1]?96:64);
  menu1<=menu_open&&x>=160&&x<480&&y>=160&&y<288;
  selected1<=menu_open&&x>=168&&x<472&&y>=176+selection*32&&y<200+selection*32;
  spectrum1<=x>=496&&x<624&&y>=16&&y<80;
  wx1<=wx;wy1<=y-16;bh1<=bars_frame[bar_index*7+:7]>>1;pk1<=peaks_frame[bar_index*7+:7]>>1;
  out_hs<=hs1;out_vs<=vs1;out_de<=de1;out_rgb<=rgb1;
  if(band1) out_rgb<=panel(rgb1,light_style);
  if(osd1||menu1) out_rgb<=24'h142438;
  if(selected1) out_rgb<=24'h245578;
  if(spectrum1) begin
   out_rgb<=24'h081820;
   if(wx1[2:0]<6 && bh1!=0 && wy1>=60-bh1 && wy1<60) out_rgb<=wy1<32?24'hffb040:24'h40e0a0;
   if(wx1[2:0]<6 && pk1!=0 && wy1==60-pk1) out_rgb<=24'hffffff;
   if(wy1==60) out_rgb<=24'h506070;
  end
  if(text1) begin
   if(sub1 && font[15-col1]) out_rgb<=light_style?24'hffffff:24'h000000;
   if(font[31-col1]) out_rgb<=sub1&&light_style?24'h101010:24'hffffff;
  end
  if(!de1) out_rgb<=0;
 end
end
endmodule
