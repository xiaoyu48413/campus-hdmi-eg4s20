// Canonical 44-byte PCM WAV stream. Producer must obey byte_ready.
// start resets at each file loop; sample output remains held until accepted.
module wav_pcm_stream(input clk,rst,start,input byte_valid,input [7:0] byte_data,
 output byte_ready,output reg sample_valid,input sample_ready,
 output reg [23:0] left_sample,right_sample,output reg done,error);
reg [7:0] header[0:43];
reg [5:0] pos;
reg [31:0] remaining;
reg [1:0] phase;
reg [23:0] pack;
reg [1:0] state;
assign byte_ready=(state==0 || state==2) && !error && !done && (!sample_valid || sample_ready);
always @(posedge clk) begin
 if(rst || start) begin
  pos<=0;remaining<=0;phase<=0;pack<=0;state<=0;
  sample_valid<=0;left_sample<=0;right_sample<=0;done<=0;error<=0;
 end else begin
  if(sample_valid && sample_ready) sample_valid<=0;
  if(state==1) begin
   if({header[0],header[1],header[2],header[3]}!=32'h52494646 ||
      {header[8],header[9],header[10],header[11]}!=32'h57415645 ||
      {header[12],header[13],header[14],header[15]}!=32'h666d7420 ||
      {header[19],header[18],header[17],header[16]}!=16 ||
      {header[21],header[20]}!=1 || {header[23],header[22]}!=2 ||
      {header[27],header[26],header[25],header[24]}!=48000 ||
      {header[31],header[30],header[29],header[28]}!=192000 ||
      {header[33],header[32]}!=4 || {header[35],header[34]}!=16 ||
      {header[36],header[37],header[38],header[39]}!=32'h64617461 ||
      header[40][1:0]!=0 || {header[43],header[42],header[41],header[40]}==0)
       begin error<=1;state<=3;end
   else begin remaining<={header[43],header[42],header[41],header[40]};state<=2;end
  end
  if(byte_valid && byte_ready) begin
   if(state==0) begin header[pos]<=byte_data;if(pos==43) state<=1;else pos<=pos+1'b1;end
   else begin
    remaining<=remaining-1'b1;phase<=phase+1'b1;
    case(phase)
     0:pack[7:0]<=byte_data;
     1:pack[15:8]<=byte_data;
     2:pack[23:16]<=byte_data;
     3:begin left_sample<={pack[15:0],8'b0};right_sample<={byte_data,pack[23:16],8'b0};sample_valid<=1;end
    endcase
    if(remaining==1) state<=3;
   end
  end
  if(state==3 && !error && sample_valid && sample_ready) done<=1;
 end
end
endmodule
