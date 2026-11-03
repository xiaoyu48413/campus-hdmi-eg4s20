// KEY2/3/4 are active-low. All short actions occur on release.
module campus_menu #(parameter CLK_HZ=25000000,DEBOUNCE_MS=20,LONG_MS=800)(
 input clk,rst,frame_tick,input [2:0] keys_n,
 output reg menu_open,output reg [1:0] selection,
 output reg next_pulse,auto_pulse,
 output reg [3:0] volume,
 output reg [2:0] contrast,
 output reg [1:0] brightness);
localparam DB=(CLK_HZ/1000)*DEBOUNCE_MS;
localparam HOLD=(CLK_HZ/1000)*LONG_MS;
reg [2:0] meta,sync,stable,released;
reg [31:0] db_count[0:2];
reg [31:0] hold_count;
reg long_sent,long_event;
reg [2:0] contrast_req;
reg [1:0] brightness_req;
integer k;
always @(posedge clk) begin
 if(rst) begin
  meta<=7;sync<=7;stable<=7;released<=0;
  hold_count<=0;long_sent<=0;long_event<=0;
  for(k=0;k<3;k=k+1) db_count[k]<=0;
 end else begin
  meta<=keys_n;sync<=meta;released<=0;long_event<=0;
  for(k=0;k<3;k=k+1) begin
   if(sync[k]==stable[k]) db_count[k]<=0;
   else if(db_count[k]>=DB-1) begin
    stable[k]<=sync[k];db_count[k]<=0;
    if(sync[k] && !(k==1 && long_sent)) released[k]<=1;
   end else db_count[k]<=db_count[k]+1'b1;
  end
  if(stable[1]) begin hold_count<=0;long_sent<=0;end
  else if(!long_sent) begin
   if(hold_count>=HOLD-1) begin long_event<=1;long_sent<=1;end
   else hold_count<=hold_count+1'b1;
  end
 end
end
always @(posedge clk) begin
 if(rst) begin
  menu_open<=0;selection<=0;volume<=5;contrast_req<=2;brightness_req<=3;
  contrast<=2;brightness<=3;next_pulse<=0;auto_pulse<=0;
 end else begin
  next_pulse<=0;auto_pulse<=0;
  if(frame_tick) begin contrast<=contrast_req;brightness<=brightness_req;end
  if(long_event) begin menu_open<=!menu_open;selection<=0;end
  else if(menu_open) begin
   if(released[0]) selection<=selection==2 ? 0:selection+1'b1;
   else if(released[1] || released[2]) case(selection)
    0:if(released[2]) begin if(volume<10) volume<=volume+1'b1;end
      else if(volume>0) volume<=volume-1'b1;
    1:if(released[2]) begin if(contrast_req<4) contrast_req<=contrast_req+1'b1;end
      else if(contrast_req>0) contrast_req<=contrast_req-1'b1;
    2:if(released[2]) begin if(brightness_req<3) brightness_req<=brightness_req+1'b1;end
      else if(brightness_req>0) brightness_req<=brightness_req-1'b1;
   endcase
  end else begin
   next_pulse<=released[0];auto_pulse<=released[2];
   if(released[1]) brightness_req<=brightness_req+1'b1;
  end
 end
end
endmodule
