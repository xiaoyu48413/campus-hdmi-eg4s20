// Bundled-data toggle mailbox. SD producer holds index until ack_toggle returns.
// Read requests are delayed eight video cycles from frame_tick in video_timing_data.
module campus_swap # (parameter FADE_ENABLE=1) (
 input clk,rst,frame_tick,ready_toggle,read_ack,
 input [1:0] ready_index,
 output reg ack_toggle,visible,
 output reg [1:0] display_index,
 output reg [5:0] fade_level
);
reg [2:0] ready_sync;
reg [1:0] index_meta,index_sync,ack_sync;
reg pending_token,ack_armed,read_seen;
reg [2:0] state;
localparam IDLE=0, DOWN=1, SWAP=2, WAIT_READ=3, UP=4;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  ready_sync<=0;index_meta<=0;index_sync<=0;ack_sync<=0;
  ack_toggle<=0;pending_token<=0;visible<=0;display_index<=0;
  fade_level<=0;state<=IDLE;ack_armed<=0;read_seen<=0;
 end else begin
  ready_sync<={ready_sync[1:0],ready_toggle};
  index_meta<=ready_index;index_sync<=index_meta;
  ack_sync<={ack_sync[0],read_ack};
  if(state==WAIT_READ) begin
   if(!ack_sync[1]) ack_armed<=1;
   if(ack_armed && ack_sync[1]) read_seen<=1;
  end
  if(frame_tick) case(state)
   IDLE: if(ready_sync[2]!=ack_toggle) begin
    pending_token<=ready_sync[2];
    if(visible && FADE_ENABLE) state<=DOWN;
    else begin
     display_index<=index_sync;fade_level<=0;
     ack_armed<=0;read_seen<=0;state<=WAIT_READ;
    end
   end
   DOWN: begin
    if(fade_level!=0) fade_level<=fade_level-1'b1;
    if(fade_level==1) state<=SWAP;
   end
   SWAP: begin
    display_index<=index_sync;ack_armed<=0;read_seen<=0;state<=WAIT_READ;
   end
   WAIT_READ: if(read_seen) begin
    visible<=1;
    if(FADE_ENABLE && visible) state<=UP; // First image is shown immediately.
    else begin fade_level<=32;ack_toggle<=pending_token;state<=IDLE;end
   end
   UP: begin
    if(fade_level<32) fade_level<=fade_level+1'b1;
    if(fade_level==31) begin ack_toggle<=pending_token;state<=IDLE;end
   end
   default: state<=IDLE;
  endcase
 end
end
endmodule
