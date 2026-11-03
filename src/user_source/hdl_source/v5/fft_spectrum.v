// 512-point radix-2 DIT FFT. Bit-reversed input, natural-order output.
// Each butterfly divides by two, so transform gain is 1/512.
// No backpressure is ever applied to the HDMI audio stream.
module fft_spectrum(input clk,rst,audio_valid,input signed[23:0] audio_sample,
 output reg[111:0] bars,peaks,output reg update,
 output reg bin_valid,output reg[7:0] bin_index,output reg[35:0] bin_power);
reg [35:0] complex_mem[0:511];
reg [35:0] ram_q;
reg[4:0] state;
reg[8:0] sample_index,base,j,half_size;
reg[3:0] stage;
reg[7:0] twaddr;
reg signed[15:0] sample_hold;
wire signed[15:0] hann;
wire signed[17:0] co,si;
fft_hann ht(clk,sample_index,hann);
fft_cos ct(clk,twaddr,co);fft_sin st(clk,twaddr,si);
reg signed[31:0] windowed;
reg signed[17:0] ar,ai,br,bi;
reg signed[35:0] p0,p1,p2,p3;
reg signed[36:0] tr,ti;
reg[8:0] addr_a,addr_b;
reg[7:0] k;
reg[3:0] band;
reg[43:0] sum_power;
reg[35:0] power;
reg[51:0] normalized;
reg[6:0] heights[0:15],peak[0:15];
reg[3:0] hold[0:15];
reg[6:0] target;
reg[10:0] skip_samples;
integer z;
function[8:0] rev(input[8:0] n);integer b;begin for(b=0;b<9;b=b+1) rev[b]=n[8-b];end endfunction
function[8:0] band_end(input[3:0] b);begin case(b)
0:band_end=2;1:band_end=3;2:band_end=4;3:band_end=6;
4:band_end=8;5:band_end=12;6:band_end=16;7:band_end=24;
8:band_end=32;9:band_end=48;10:band_end=64;11:band_end=96;
12:band_end=128;13:band_end=176;14:band_end=224;15:band_end=256;
endcase end endfunction
// Reciprocal group widths in Q16, for mean power rather than sum power.
function[16:0] reciprocal(input[3:0] b);begin case(b)
0,1,2:reciprocal=65536;3,4:reciprocal=32768;5,6:reciprocal=16384;
7,8:reciprocal=8192;9,10:reciprocal=4096;11,12,15:reciprocal=2048;
13,14:reciprocal=1365;endcase end endfunction
function[6:0] logheight(input[35:0] p);integer b,h;begin
h=0;for(b=2;b<36;b=b+1) if(p[b]) h=(b-1)*3;
logheight=h>88?88:h;end endfunction
// Explicit single read/single write RAM ports retain BRAM inference in TD.
reg[8:0] ram_rd,ram_wr;
reg[35:0] ram_data;
reg ram_we;
reg signed[17:0] wr_real,wr_imag;
always @* begin
 ram_rd=0;ram_wr=0;ram_data=0;ram_we=0;wr_real=0;wr_imag=0;
 case(state)
  4:ram_rd=addr_a;
  5:ram_rd=addr_b;
  10:ram_rd={1'b0,k};
  default:ram_rd=0;
 endcase
 if(!rst) case(state)
  2:begin ram_we=1;ram_wr=rev(sample_index);wr_real=windowed>>>15;wr_imag=0;end
  8:begin ram_we=1;ram_wr=addr_a;wr_real=($signed(ar)+(tr>>>16))>>>1;wr_imag=($signed(ai)+(ti>>>16))>>>1;end
  9:begin ram_we=1;ram_wr=addr_b;wr_real=($signed(ar)-(tr>>>16))>>>1;wr_imag=($signed(ai)-(ti>>>16))>>>1;end
  default:ram_we=0;
 endcase
 ram_data={wr_imag,wr_real};
end
always @(posedge clk) begin
 if(ram_we) complex_mem[ram_wr]<=ram_data;
 ram_q<=complex_mem[ram_rd];
end
always @(posedge clk) begin
 if(rst) begin
  state<=0;sample_index<=0;base<=0;j<=0;half_size<=1;stage<=0;twaddr<=0;
  sample_hold<=0;windowed<=0;ar<=0;ai<=0;br<=0;bi<=0;p0<=0;p1<=0;p2<=0;p3<=0;
  tr<=0;ti<=0;addr_a<=0;addr_b<=0;k<=1;band<=0;sum_power<=0;power<=0;
  normalized<=0;target<=0;skip_samples<=0;bars<=0;peaks<=0;update<=0;bin_valid<=0;bin_index<=0;bin_power<=0;
  for(z=0;z<16;z=z+1) begin heights[z]<=0;peak[z]<=0;hold[z]<=0;end
 end else begin
  update<=0;bin_valid<=0;
  case(state)
   0:if(audio_valid) begin sample_hold<=audio_sample[23:8];state<=1;end
   1:begin windowed<=sample_hold*hann;state<=2;end
   2:begin
    if(sample_index==511) begin stage<=0;half_size<=1;base<=0;j<=0;state<=3;end
    else begin sample_index<=sample_index+1'b1;state<=0;end
   end
   3:begin addr_a<=base+j;addr_b<=base+j+half_size;twaddr<=j<<(8-stage);state<=4;end
   4:state<=5;
   5:begin ar<=ram_q[17:0];ai<=ram_q[35:18];state<=6;end
   6:begin br<=ram_q[17:0];bi<=ram_q[35:18];state<=19;end
   19:begin p0<=br*co;p1<=bi*si;p2<=br*si;p3<=bi*co;state<=7;end
   7:begin tr<=($signed(p0)-$signed({p1[35],p1}));ti<=($signed({p2[35],p2})+$signed({p3[35],p3}));state<=8;end
   8:begin
    state<=9;
   end
   9:begin
    if(j+1<half_size) begin j<=j+1'b1;state<=3;end
    else if({1'b0,base}+({1'b0,half_size}<<1)<512) begin base<=base+(half_size<<1);j<=0;state<=3;end
    else if(stage<8) begin stage<=stage+1'b1;half_size<=half_size<<1;base<=0;j<=0;state<=3;end
    else begin k<=1;band<=0;sum_power<=0;state<=10;end
   end
   10:state<=11;
   11:begin ar<=ram_q[17:0];ai<=ram_q[35:18];state<=20;end
   20:begin p0<=ar*ar;p1<=ai*ai;state<=12;end
   12:begin power<=p0+p1;state<=13;end
   13:begin
    bin_valid<=1;bin_index<=k;bin_power<=power;
    sum_power<=sum_power+power;
    if({1'b0,k}+1==band_end(band)) state<=14;
    else begin k<=k+1'b1;state<=10;end
   end
   14:begin normalized<=sum_power*reciprocal(band);state<=15;end
   15:begin target<=logheight(normalized[51:16]);state<=16;end
   16:begin
    if(target>=heights[band]) heights[band]<=target;
    else heights[band]<=heights[band]>3?heights[band]-7'd3:0;
    if(target>=peak[band]) begin peak[band]<=target;hold[band]<=15;end
    else if(hold[band]!=0) hold[band]<=hold[band]-1'b1;
    else peak[band]<=peak[band]>2?peak[band]-7'd2:0;
    if(band==15) state<=17;
    else begin band<=band+1'b1;k<=k+1'b1;sum_power<=0;state<=10;end
   end
   17:begin
    for(z=0;z<16;z=z+1) begin bars[z*7+:7]<=heights[z];peaks[z*7+:7]<=peak[z];end
    update<=1;skip_samples<=0;state<=18;
   end
   18:if(audio_valid) begin
    if(skip_samples==1023) begin sample_index<=0;state<=0;end
    else skip_samples<=skip_samples+1'b1;
   end
   default:state<=0;
  endcase
 end
end
endmodule
