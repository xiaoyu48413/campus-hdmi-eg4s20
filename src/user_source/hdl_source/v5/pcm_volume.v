// PCM-boundary gain updates. Q12 gain slews by 9/4096 per sample:
// a full-scale change takes <=456 samples (9.5 ms at 48 kHz).
module pcm_volume(input clk,rst,input [3:0] volume,
 input in_valid,input signed [23:0] left_in,right_in,
 output reg out_valid,output reg signed [23:0] left_out,right_out);
reg[12:0] gain;
function [12:0] gain_target(input [3:0] level); begin
case(level)
 0:gain_target=0;1:gain_target=410;2:gain_target=819;3:gain_target=1229;4:gain_target=1638;
 5:gain_target=2048;6:gain_target=2458;7:gain_target=2867;8:gain_target=3277;9:gain_target=3686;
 default:gain_target=4096;
endcase end endfunction
wire [12:0] target=gain_target(volume);
wire[12:0] next_gain=gain<target ? ((target-gain>9)?gain+13'd9:target) :
                                  ((gain-target>9)?gain-13'd9:target);
reg signed[37:0] lp,rp;
reg v;
always @(posedge clk) begin
 if(rst) begin gain<=2048;lp<=0;rp<=0;v<=0;out_valid<=0;left_out<=0;right_out<=0;end
 else begin
  v<=in_valid;out_valid<=v;
  if(in_valid) begin
   gain<=next_gain;
   lp<=left_in*$signed({1'b0,next_gain});
   rp<=right_in*$signed({1'b0,next_gain});
  end
  if(v) begin left_out<=lp>>>12;right_out<=rp>>>12;end
 end
end
endmodule

