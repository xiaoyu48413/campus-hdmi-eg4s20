module image_adjust(input clk,rst,in_hs,in_vs,in_de,input[23:0] in_rgb,
 input[2:0] contrast,input[1:0] brightness,
 output reg out_hs,out_vs,out_de,output reg[23:0] out_rgb);
reg signed[12:0] cr,cg,cb;
reg[23:0] clipped;
reg[1:0] hs,vs,de;
reg[1:0] b1,b2;
wire signed[4:0] factor=$signed({2'b0,contrast})+5'sd2;
function[7:0] clip(input signed[12:0] v);reg signed[12:0] t;begin
 t=(v>>>2)+13'sd128;clip=t<0?0:(t>255?255:t[7:0]);end endfunction
function[7:0] bright(input[7:0] v,input[1:0] b);reg[9:0] t;begin
 case(b) 0:t=v;1:t={v,1'b0};2:t={v,1'b0}+{2'b0,v};3:t={v,2'b0};endcase
 bright=t[9:2];end endfunction
always @(posedge clk) begin
 if(rst) begin cr<=0;cg<=0;cb<=0;clipped<=0;hs<=0;vs<=0;de<=0;b1<=3;b2<=3;out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;end
 else begin
  cr<=($signed({1'b0,in_rgb[23:16]})-9'sd128)*factor;
  cg<=($signed({1'b0,in_rgb[15:8]})-9'sd128)*factor;
  cb<=($signed({1'b0,in_rgb[7:0]})-9'sd128)*factor;
  clipped<={clip(cr),clip(cg),clip(cb)};b1<=brightness;b2<=b1;
  hs<={hs[0],in_hs};vs<={vs[0],in_vs};de<={de[0],in_de};
  out_hs<=hs[1];out_vs<=vs[1];out_de<=de[1];
  out_rgb<={bright(clipped[23:16],b2),bright(clipped[15:8],b2),bright(clipped[7:0],b2)};
 end
end
endmodule
