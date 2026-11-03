// FIFO in SD clock domain. Toggle mailbox returns one stable sample per video request.
// Video domain generates exactly 48000 strobes per 25000000 clocks; no music-clock drift.
module pcm_hdmi_bridge(input sd_clk,video_clk,rst,enable,
 input pcm_valid,input [31:0] pcm_data,output can_read,
 output reg audio_valid,output reg [23:0] audio_left,audio_right,
 output reg [31:0] underruns,output reg overflow);
reg [31:0] mem[0:1023];
reg [9:0] wr,rd;
reg [10:0] used;
reg primed;
reg request;
reg [2:0] req_sync;
reg req_seen,reply,read_pending,read_token;
reg [31:0] ram_q,mail_data;
wire new_request=req_sync[2]!=req_seen;
wire pop=new_request && primed && used!=0;
wire push=pcm_valid && used<1024;
assign can_read=used<=768;
always @(posedge sd_clk) begin
 if(push) mem[wr]<=pcm_data;
 ram_q<=mem[rd];
end
always @(posedge sd_clk or posedge rst) begin
 if(rst) begin
  wr<=0;rd<=0;used<=0;primed<=0;req_sync<=0;req_seen<=0;
  reply<=0;read_pending<=0;read_token<=0;mail_data<=0;underruns<=0;overflow<=0;
 end else begin
  req_sync<={req_sync[1:0],request};
  if(used>=512) primed<=1;
  if(pcm_valid && !push) overflow<=1;
  case({push,pop}) 2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
  if(push) wr<=wr+1'b1;
  if(pop) rd<=rd+1'b1;
  if(new_request) begin
   req_seen<=req_sync[2];read_token<=req_sync[2];
   if(pop) read_pending<=1;
   else begin
    mail_data<=0;reply<=req_sync[2];
    if(primed) underruns<=underruns+1'b1;
   end
  end
  if(read_pending) begin mail_data<=ram_q;reply<=read_token;read_pending<=0;end
 end
end
reg [24:0] phase;
reg [2:0] reply_sync;
reg reply_seen,pending_valid;
reg [31:0] pending_data;
always @(posedge video_clk or posedge rst) begin
 if(rst) begin
  phase<=0;request<=0;reply_sync<=0;reply_seen<=0;pending_valid<=0;pending_data<=0;
  audio_valid<=0;audio_left<=0;audio_right<=0;
 end else begin
  reply_sync<={reply_sync[1:0],reply};audio_valid<=0;
  if(reply_sync[2]!=reply_seen) begin
   reply_seen<=reply_sync[2];pending_data<=mail_data;pending_valid<=1;
  end
  if(phase>=25000000-48000) begin
   phase<=phase-(25000000-48000);audio_valid<=1;
   if(enable && pending_valid) begin
    audio_left<={pending_data[15:0],8'd0};audio_right<={pending_data[31:16],8'd0};
   end else begin audio_left<=0;audio_right<=0;end
   pending_valid<=0;
   if(enable) request<=~request;
  end else phase<=phase+48000;
 end
end
endmodule
