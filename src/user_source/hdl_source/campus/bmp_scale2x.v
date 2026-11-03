// 320x240 -> 640x480 nearest-neighbour, 24-bit pixels in BMP bottom-up order.
// Two line banks absorb the remainder of an in-flight 512-byte SD sector.
// The reader starts another sector only while can_read_sector is high.
module bmp_scale2x(
 input clk,rst,frame_start,enable,
 input in_valid,input [23:0] in_pixel,
 output reg out_valid,output reg [23:0] out_pixel,
 output can_read_sector,output reg overflow
);
reg [23:0] rows[0:1023];
reg wr_bank,rd_bank,busy;
reg [8:0] wr_x;
reg [1:0] full;
reg [9:0] out_x;
reg second_row;
reg [2:0] pace;
reg [23:0] ram_q;
wire [9:0] rd_addr={rd_bank,out_x[9:1]};
assign can_read_sector=!busy && full==0;
always @(posedge clk) begin
 if(enable && in_valid) rows[{wr_bank,wr_x}]<=in_pixel;
 ram_q<=rows[rd_addr];
end
always @(posedge clk or posedge rst) begin
 if(rst) begin
  wr_bank<=0;rd_bank<=0;wr_x<=0;full<=0;busy<=0;out_x<=0;
  second_row<=0;pace<=0;out_valid<=0;out_pixel<=0;overflow<=0;
 end else if(frame_start) begin
  wr_bank<=0;rd_bank<=0;wr_x<=0;full<=0;busy<=0;out_x<=0;
  second_row<=0;pace<=0;out_valid<=0;overflow<=0;
 end else begin
  out_valid<=0;
  if(!enable) begin out_valid<=in_valid;out_pixel<=in_pixel;end
  else begin
   if(in_valid) begin
    if(full[wr_bank] || (busy && rd_bank==wr_bank)) overflow<=1;
    if(wr_x==319) begin wr_x<=0;full[wr_bank]<=1;wr_bank<=~wr_bank;end
    else wr_x<=wr_x+1'b1;
   end
   if(!busy && full[rd_bank]) begin
    busy<=1;out_x<=0;second_row<=0;pace<=0;
   end else if(busy) begin
    pace<=pace+1'b1;
    // RAM address has been stable for at least two clocks before this beat.
    if(pace==7) begin
     out_valid<=1;out_pixel<=ram_q;
     if(out_x==639) begin
      out_x<=0;
      if(second_row) begin busy<=0;full[rd_bank]<=0;rd_bank<=~rd_bank;end
      else second_row<=1;
     end else out_x<=out_x+1'b1;
    end
   end
  end
 end
end
endmodule
