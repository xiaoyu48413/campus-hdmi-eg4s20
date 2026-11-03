module bmp_read #(parameter AUDIO_MODE=0)(
    input                       clk,
    input                       rst,
    output                      ready,

    // Enumerate existing FAT32 root-directory BMP files; never raw-sector scan.
    input                       scan_start,
    input                       scan_resume,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [3:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [3:0]            scan_found_total,

    // load_sector is now a catalogue handle (0..9), NOT a physical sector.
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output                      bmp_data_wr_en,
    output [23:0]               bmp_data,
    input audio_can_read, output reg pcm_valid, output reg [31:0] pcm_data
);

// FAT32 read-only root-directory reader, 512-byte sectors, at most four images.
// Root and file cluster chains are followed; deleted bytes are never enumerated.
localparam IDLE=0, BOOT_READ=1, VBR_READ=2, BOOT_CHECK=3,
 MAP_WAIT=4, DIR_READ=5, ENTRY_INIT=6, ENTRY_WAIT=7, ENTRY_BYTE=8,
 ENTRY_CHECK=9, NEXT_ENTRY=10, HEADER_READ=11, HEADER_CHECK=12,
 WRITE_WAIT=13, DATA_READ=14, DATA_NEXT=15, FAT_ADDR=16,
 FAT_READ=17, FAT_CHECK=18, DRAIN=19, FATAL=20;
localparam MAP_DIR=0, MAP_HEADER=1, MAP_DATA=2;
reg [4:0] state;
reg [3:0] settle;
reg mounted,boot_is_mbr,opening_file;
reg [8:0] byte_index;
reg [31:0] volume_base,partition_size;
reg [7:0] jump,signature0,signature1,spc,num_fats;
reg [15:0] bytes_per_sector,reserved_sectors,root_entries,fat16,ext_flags,fs_version;
reg [31:0] total_sectors,fat_sectors,root_cluster;
reg [7:0] partition_type[0:3];
reg [31:0] partition_lba[0:3],partition_len[0:3];
reg [2:0] cluster_shift;
reg [33:0] metadata_q,data_base_q,fat_base_q,volume_end_q;
reg [31:0] cluster_count_q,last_cluster_q;
reg fields_ok,geometry_ok,volume_ok;
integer i;
assign ready=(state==IDLE);

// All geometry settles before BOOT_CHECK consumes it; split arithmetic for 100 MHz.
always @(posedge clk or posedge rst) begin
 if(rst) begin
  metadata_q<=0;data_base_q<=0;fat_base_q<=0;volume_end_q<=0;
  cluster_count_q<=0;last_cluster_q<=0;cluster_shift<=0;
  fields_ok<=0;geometry_ok<=0;volume_ok<=0;
 end else begin
  case(spc)
   1:cluster_shift<=0;2:cluster_shift<=1;4:cluster_shift<=2;8:cluster_shift<=3;
   16:cluster_shift<=4;32:cluster_shift<=5;64:cluster_shift<=6;128:cluster_shift<=7;
   default:cluster_shift<=0;
  endcase
  metadata_q<={18'd0,reserved_sectors}+(num_fats==2 ? {1'b0,fat_sectors,1'b0}:{2'b0,fat_sectors});
  data_base_q<={2'b0,volume_base}+metadata_q;
  fat_base_q<={2'b0,volume_base}+{18'd0,reserved_sectors}+
              ((ext_flags[7] && ext_flags[3:0]==1) ? {2'b0,fat_sectors}:34'd0);
  volume_end_q<={2'b0,volume_base}+{2'b0,total_sectors};
  cluster_count_q<=(total_sectors-metadata_q[31:0])>>cluster_shift;
  last_cluster_q<=cluster_count_q+1'b1;
  fields_ok<=(jump==8'heb || jump==8'he9) && signature0==8'h55 && signature1==8'haa &&
   bytes_per_sector==512 && reserved_sectors!=0 && (num_fats==1 || num_fats==2) &&
   root_entries==0 && fat16==0 && fat_sectors!=0 && fs_version==0 &&
   spc!=0 && spc<=128 && ((spc & (spc-1'b1))==0) &&
   (!ext_flags[7] || ext_flags[3:0]<num_fats);
  geometry_ok<=fields_ok && metadata_q<{2'b0,total_sectors} &&
   !(|data_base_q[33:32]) && !(|volume_end_q[33:32]) &&
   (partition_size==0 || total_sectors<=partition_size);
  volume_ok<=geometry_ok && cluster_count_q>=65525 && last_cluster_q<32'h0ffffff0 &&
   root_cluster>=2 && root_cluster<=last_cluster_q &&
   {fat_sectors,7'd0}>={7'd0,last_cluster_q}+39'd1;
 end
end

reg wav_bad;
reg [31:0] wav_length;
always @(posedge clk or posedge rst) begin
 if(rst) begin wav_bad<=0;wav_length<=0;end
 else if(state==HEADER_READ && sd_sec_read_data_valid) begin
  if(byte_index==0) wav_bad <= sd_sec_read_data!="R";
  else case(byte_index)
   1:if(sd_sec_read_data!="I") wav_bad<=1;
   2,3:if(sd_sec_read_data!="F") wav_bad<=1;
   8:if(sd_sec_read_data!="W") wav_bad<=1;
   9:if(sd_sec_read_data!="A") wav_bad<=1;
   10:if(sd_sec_read_data!="V") wav_bad<=1;
   11:if(sd_sec_read_data!="E") wav_bad<=1;
   12:if(sd_sec_read_data!="f") wav_bad<=1;
   13:if(sd_sec_read_data!="m") wav_bad<=1;
   14:if(sd_sec_read_data!="t") wav_bad<=1;
   15:if(sd_sec_read_data!=" ") wav_bad<=1;
   16:if(sd_sec_read_data!=16) wav_bad<=1;
   20:if(sd_sec_read_data!=1) wav_bad<=1;
   22:if(sd_sec_read_data!=2) wav_bad<=1;
   24:if(sd_sec_read_data!=8'h80) wav_bad<=1;
   25:if(sd_sec_read_data!=8'hbb) wav_bad<=1;
   28:if(sd_sec_read_data!=0) wav_bad<=1;
   29:if(sd_sec_read_data!=8'hee) wav_bad<=1;
   30:if(sd_sec_read_data!=2) wav_bad<=1;
   32:if(sd_sec_read_data!=4) wav_bad<=1;
   34:if(sd_sec_read_data!=16) wav_bad<=1;
   17,18,19,21,23,26,27,31,33,35:if(sd_sec_read_data!=0) wav_bad<=1;
   36:if(sd_sec_read_data!="d") wav_bad<=1;
   37:if(sd_sec_read_data!="a") wav_bad<=1;
   38:if(sd_sec_read_data!="t") wav_bad<=1;
   39:if(sd_sec_read_data!="a") wav_bad<=1;
   40:wav_length[7:0]<=sd_sec_read_data;
   41:wav_length[15:8]<=sd_sec_read_data;
   42:wav_length[23:16]<=sd_sec_read_data;
   43:wav_length[31:24]<=sd_sec_read_data;
  endcase
 end
end
// Stream capture for the boot sector and BMP header, intentionally separate.
reg [7:0] header0,header1;
reg [31:0] bmp_file_size,pixel_offset,dib_size,width,height,compression;
reg [15:0] planes,bit_count;
reg [31:0] candidate_size;
reg [31:0] pixel_bytes;
reg [32:0] pixel_end_q,dib_end_q;
reg header_ok;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  pixel_bytes<=0;pixel_end_q<=0;dib_end_q<=0;header_ok<=0;
 end else begin
  pixel_bytes<=AUDIO_MODE ? wav_length : ((width==320)?230400:921600);
  pixel_end_q<=(AUDIO_MODE ? 33'd44 : {1'b0,pixel_offset})+{1'b0,pixel_bytes};
  dib_end_q<={1'b0,dib_size}+33'd14;
  header_ok<=AUDIO_MODE ? (!wav_bad && wav_length!=0 && wav_length[1:0]==0 && !pixel_end_q[32] && candidate_size>=pixel_end_q[31:0]) : header0=="B" && header1=="M" &&
   ((width==320 && height==240)||(width==640 && height==480)) &&
   dib_size>=40 && {1'b0,pixel_offset}>=dib_end_q &&
   planes==1 && bit_count==24 && compression==0 && !pixel_end_q[32] &&
   bmp_file_size>=pixel_end_q[31:0] && candidate_size>=bmp_file_size;
 end
end
always @(posedge clk or posedge rst) begin
 if(rst) begin
  byte_index<=0;jump<=0;signature0<=0;signature1<=0;spc<=0;num_fats<=0;
  bytes_per_sector<=0;reserved_sectors<=0;root_entries<=0;fat16<=0;
  ext_flags<=0;fs_version<=0;total_sectors<=0;fat_sectors<=0;root_cluster<=0;
  header0<=0;header1<=0;bmp_file_size<=0;pixel_offset<=0;dib_size<=0;
  width<=0;height<=0;compression<=0;planes<=0;bit_count<=0;
  for(i=0;i<4;i=i+1) begin partition_type[i]<=0;partition_lba[i]<=0;partition_len[i]<=0;end
 end else begin
  if(sd_sec_read_end) byte_index<=0;
  else if(sd_sec_read_data_valid) byte_index<=byte_index+1'b1;
  if(sd_sec_read_data_valid && (state==BOOT_READ || state==VBR_READ)) begin
   case(byte_index)
    0:jump<=sd_sec_read_data;
    11:bytes_per_sector[7:0]<=sd_sec_read_data;12:bytes_per_sector[15:8]<=sd_sec_read_data;
    13:spc<=sd_sec_read_data;
    14:reserved_sectors[7:0]<=sd_sec_read_data;15:reserved_sectors[15:8]<=sd_sec_read_data;
    16:num_fats<=sd_sec_read_data;
    17:root_entries[7:0]<=sd_sec_read_data;18:root_entries[15:8]<=sd_sec_read_data;
    22:fat16[7:0]<=sd_sec_read_data;23:fat16[15:8]<=sd_sec_read_data;
    32:total_sectors[7:0]<=sd_sec_read_data;33:total_sectors[15:8]<=sd_sec_read_data;
    34:total_sectors[23:16]<=sd_sec_read_data;35:total_sectors[31:24]<=sd_sec_read_data;
    36:fat_sectors[7:0]<=sd_sec_read_data;37:fat_sectors[15:8]<=sd_sec_read_data;
    38:fat_sectors[23:16]<=sd_sec_read_data;39:fat_sectors[31:24]<=sd_sec_read_data;
    40:ext_flags[7:0]<=sd_sec_read_data;41:ext_flags[15:8]<=sd_sec_read_data;
    42:fs_version[7:0]<=sd_sec_read_data;43:fs_version[15:8]<=sd_sec_read_data;
    44:root_cluster[7:0]<=sd_sec_read_data;45:root_cluster[15:8]<=sd_sec_read_data;
    46:root_cluster[23:16]<=sd_sec_read_data;47:root_cluster[31:24]<=sd_sec_read_data;
    510:signature0<=sd_sec_read_data;511:signature1<=sd_sec_read_data;
    default:;
   endcase
   if(state==BOOT_READ) for(i=0;i<4;i=i+1) begin
    if(byte_index==450+i*16) partition_type[i]<=sd_sec_read_data;
    if(byte_index==454+i*16) partition_lba[i][7:0]<=sd_sec_read_data;
    if(byte_index==455+i*16) partition_lba[i][15:8]<=sd_sec_read_data;
    if(byte_index==456+i*16) partition_lba[i][23:16]<=sd_sec_read_data;
    if(byte_index==457+i*16) partition_lba[i][31:24]<=sd_sec_read_data;
    if(byte_index==458+i*16) partition_len[i][7:0]<=sd_sec_read_data;
    if(byte_index==459+i*16) partition_len[i][15:8]<=sd_sec_read_data;
    if(byte_index==460+i*16) partition_len[i][23:16]<=sd_sec_read_data;
    if(byte_index==461+i*16) partition_len[i][31:24]<=sd_sec_read_data;
   end
  end
  if(sd_sec_read_data_valid && state==HEADER_READ) case(byte_index)
   0:header0<=sd_sec_read_data;1:header1<=sd_sec_read_data;
   2:bmp_file_size[7:0]<=sd_sec_read_data;3:bmp_file_size[15:8]<=sd_sec_read_data;
   4:bmp_file_size[23:16]<=sd_sec_read_data;5:bmp_file_size[31:24]<=sd_sec_read_data;
   10:pixel_offset[7:0]<=sd_sec_read_data;11:pixel_offset[15:8]<=sd_sec_read_data;
   12:pixel_offset[23:16]<=sd_sec_read_data;13:pixel_offset[31:24]<=sd_sec_read_data;
   14:dib_size[7:0]<=sd_sec_read_data;15:dib_size[15:8]<=sd_sec_read_data;
   16:dib_size[23:16]<=sd_sec_read_data;17:dib_size[31:24]<=sd_sec_read_data;
   18:width[7:0]<=sd_sec_read_data;19:width[15:8]<=sd_sec_read_data;
   20:width[23:16]<=sd_sec_read_data;21:width[31:24]<=sd_sec_read_data;
   22:height[7:0]<=sd_sec_read_data;23:height[15:8]<=sd_sec_read_data;
   24:height[23:16]<=sd_sec_read_data;25:height[31:24]<=sd_sec_read_data;
   26:planes[7:0]<=sd_sec_read_data;27:planes[15:8]<=sd_sec_read_data;
   28:bit_count[7:0]<=sd_sec_read_data;29:bit_count[15:8]<=sd_sec_read_data;
   30:compression[7:0]<=sd_sec_read_data;31:compression[15:8]<=sd_sec_read_data;
   32:compression[23:16]<=sd_sec_read_data;33:compression[31:24]<=sd_sec_read_data;
   default:;
  endcase
 end
end

// Root directory sector remains cached while a candidate is checked/loaded.
reg [7:0] directory_ram[0:511];
reg [8:0] directory_addr;
reg [7:0] directory_q;
always @(posedge clk) begin
 if(state==DIR_READ && sd_sec_read_data_valid) directory_ram[byte_index]<=sd_sec_read_data;
 directory_q<=directory_ram[directory_addr];
end
reg [3:0] entry_index;
reg [4:0] entry_byte;
reg [7:0] entry_first,entry_attr,ext0,ext1,ext2;
reg [63:0] entry_name;
reg [31:0] entry_cluster,entry_size;
reg [31:0] dir_cluster,dir_lba,file_cluster;
reg [7:0] dir_sector,file_sector;
reg [8:0] dir_hops;
reg [31:0] catalogue_cluster[0:9],catalogue_size[0:9];

// Cluster-to-LBA conversion, shared by directory and file traffic.
reg [31:0] map_cluster;
reg [1:0] map_kind;
reg [31:0] cluster_delta;
reg [38:0] scaled_delta,mapped_lba;
always @(posedge clk or posedge rst) begin
 if(rst) begin cluster_delta<=0;scaled_delta<=0;mapped_lba<=0;end
 else begin
  cluster_delta<=map_cluster-2;
  scaled_delta<={7'd0,cluster_delta}<<cluster_shift;
  mapped_lba<=scaled_delta+{5'd0,data_base_q};
 end
end

reg fat_for_directory;
reg [31:0] fat_cluster;
reg [31:0] fat_value;
reg [32:0] fat_lba;
wire [27:0] next_cluster=fat_value[27:0];
wire [8:0] fat_offset={fat_cluster[6:0],2'b00};
always @(posedge clk or posedge rst) begin
 if(rst) begin fat_lba<=0;fat_value<=0;end
 else begin
  fat_lba<={1'b0,fat_base_q[31:0]}+{8'd0,fat_cluster[31:7]};
  if(state==FAT_READ && sd_sec_read_data_valid && byte_index[8:2]==fat_offset[8:2])
   case(byte_index[1:0])
    0:fat_value[7:0]<=sd_sec_read_data;1:fat_value[15:8]<=sd_sec_read_data;
    2:fat_value[23:16]<=sd_sec_read_data;3:fat_value[31:24]<=sd_sec_read_data;
   endcase
 end
end

// Offset counts only file bytes, never FAT sectors inserted between clusters.
reg [31:0] file_byte_count;
reg [1:0] pixel_byte;
reg [23:0] raw_pixel;
reg raw_valid,scale2x;
wire scale_idle,scale_error;
wire pixel_input=state==DATA_READ && sd_sec_read_data_valid &&
 file_byte_count>=(AUDIO_MODE ? 32'd44 : pixel_offset) && file_byte_count<pixel_end_q[31:0];
generate if(!AUDIO_MODE) begin: image_scaler
bmp_scale2x u_scaler(.clk(clk),.rst(rst),.frame_start(write_req && write_req_ack),
 .enable(scale2x),.in_valid(raw_valid),.in_pixel(raw_pixel),.out_valid(bmp_data_wr_en),
 .out_pixel(bmp_data),.can_read_sector(scale_idle),.overflow(scale_error));
end else begin: audio_capacity
 assign scale_idle=audio_can_read;assign scale_error=0;
 assign bmp_data_wr_en=0;assign bmp_data=0;
end endgenerate
reg [1:0] pcm_phase;
reg [23:0] pcm_pack;
always @(posedge clk or posedge rst) begin
 if(rst) begin pcm_valid<=0;pcm_data<=0;pcm_phase<=0;pcm_pack<=0;end
 else begin
  pcm_valid<=0;
  if(write_req && write_req_ack) pcm_phase<=0;
  if(AUDIO_MODE && pixel_input) begin
   pcm_phase<=pcm_phase+1'b1;
   case(pcm_phase)
    0:pcm_pack[7:0]<=sd_sec_read_data;
    1:pcm_pack[15:8]<=sd_sec_read_data;
    2:pcm_pack[23:16]<=sd_sec_read_data;
    3:begin pcm_data<={sd_sec_read_data,pcm_pack};pcm_valid<=1;end
   endcase
  end
 end
end
always @(posedge clk or posedge rst) begin
 if(rst) begin file_byte_count<=0;pixel_byte<=0;raw_pixel<=0;raw_valid<=0;end
 else begin
  raw_valid<=0;
  if(write_req && write_req_ack) begin file_byte_count<=0;pixel_byte<=0;end
  else if(state==DATA_READ && sd_sec_read_data_valid) file_byte_count<=file_byte_count+1'b1;
  if(pixel_input) begin
   case(pixel_byte)
    0:raw_pixel[7:0]<=sd_sec_read_data;
    1:raw_pixel[15:8]<=sd_sec_read_data;
    2:begin raw_pixel[23:16]<=sd_sec_read_data;raw_valid<=1;end
   endcase
   pixel_byte<=(pixel_byte==2)?0:pixel_byte+1'b1;
  end
 end
end

reg [2:0] partition_choice;
always @* begin
 partition_choice=4;
 for(integer k=3;k>=0;k=k-1)
  if((partition_type[k]==8'h0b || partition_type[k]==8'h0c) && partition_lba[k]!=0 && partition_len[k]!=0)
   partition_choice=k;
end
always @(posedge clk or posedge rst) begin
 if(rst) begin
  state<=IDLE;settle<=0;mounted<=0;boot_is_mbr<=0;opening_file<=0;
  sd_sec_read<=0;sd_sec_read_addr<=0;write_req<=0;state_code<=0;
  scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;
  volume_base<=0;partition_size<=0;candidate_size<=0;
  directory_addr<=0;entry_index<=0;entry_byte<=0;entry_first<=0;entry_attr<=0;
  ext0<=0;ext1<=0;ext2<=0;entry_cluster<=0;entry_size<=0;
  dir_cluster<=0;dir_lba<=0;file_cluster<=0;dir_sector<=0;file_sector<=0;dir_hops<=0;
  map_cluster<=0;map_kind<=0;fat_for_directory<=0;fat_cluster<=0;scale2x<=0;
  for(integer k=0;k<10;k=k+1) begin catalogue_cluster[k]<=0;catalogue_size[k]<=0;end
 end else begin
  scan_found_valid<=0;
  case(state)
   IDLE: begin
    sd_sec_read<=0;write_req<=0;state_code<=scan_done && scan_found_total==0 ? 4'hc : 4'd1;
    if(scan_start && sd_init_done) begin
     mounted<=0;scan_done<=0;scan_found_total<=0;volume_base<=0;partition_size<=0;
     sd_sec_read_addr<=0;state<=BOOT_READ;dir_hops<=0;
    end else if(load_start && mounted) begin
     if(load_sector<scan_found_total && load_sector<10) begin
      file_cluster<=catalogue_cluster[load_sector[3:0]];
      map_cluster<=catalogue_cluster[load_sector[3:0]];
      candidate_size<=catalogue_size[load_sector[3:0]];
      file_sector<=0;map_kind<=MAP_HEADER;settle<=0;opening_file<=1;state<=MAP_WAIT;
     end else state<=FATAL;
    end else if(scan_resume && mounted && !scan_done) state<=NEXT_ENTRY;
   end
   BOOT_READ,VBR_READ: begin
    state_code<=2;sd_sec_read<=1;
    if(sd_sec_read_end) begin
     sd_sec_read<=0;settle<=0;boot_is_mbr<=(state==BOOT_READ);state<=BOOT_CHECK;
    end
   end
   BOOT_CHECK: begin
    settle<=settle+1'b1;
    if(settle==12) begin
     if(volume_ok) begin
      mounted<=1;dir_cluster<=root_cluster;map_cluster<=root_cluster;
      dir_sector<=0;map_kind<=MAP_DIR;settle<=0;state<=MAP_WAIT;
     end else if(boot_is_mbr && signature0==8'h55 && signature1==8'haa && partition_choice<4) begin
      volume_base<=partition_lba[partition_choice[1:0]];
      partition_size<=partition_len[partition_choice[1:0]];
      sd_sec_read_addr<=partition_lba[partition_choice[1:0]];state<=VBR_READ;
     end else state<=FATAL; // No raw-sector fallback: deleted files must stay invisible.
    end
   end
   MAP_WAIT: begin
    settle<=settle+1'b1;
    if(settle==6) begin
     if(map_cluster<2 || map_cluster>last_cluster_q || (|mapped_lba[38:32]) ||
        mapped_lba>={5'd0,volume_end_q}) state<=FATAL;
     else begin
      sd_sec_read_addr<=mapped_lba[31:0];
      case(map_kind)
       MAP_DIR:begin dir_lba<=mapped_lba[31:0];state<=DIR_READ;end
       MAP_HEADER:state<=HEADER_READ;
       default:state<=DATA_READ;
      endcase
     end
    end
   end
   DIR_READ: begin
    state_code<=2;sd_sec_read<=1;
    if(sd_sec_read_end) begin sd_sec_read<=0;entry_index<=0;state<=ENTRY_INIT;end
   end
   ENTRY_INIT: begin
    entry_byte<=0;entry_name<=0;directory_addr<={entry_index,5'd0};state<=ENTRY_WAIT;
   end
   ENTRY_WAIT:state<=ENTRY_BYTE;
   ENTRY_BYTE: begin
    if(entry_byte<8) entry_name<={entry_name[55:0],directory_q};
    case(entry_byte)
     0:entry_first<=directory_q;
     8:ext0<=directory_q;9:ext1<=directory_q;10:ext2<=directory_q;11:entry_attr<=directory_q;
     20:entry_cluster[23:16]<=directory_q;21:entry_cluster[31:24]<={4'd0,directory_q[3:0]};
     26:entry_cluster[7:0]<=directory_q;27:entry_cluster[15:8]<=directory_q;
     28:entry_size[7:0]<=directory_q;29:entry_size[15:8]<=directory_q;
     30:entry_size[23:16]<=directory_q;31:entry_size[31:24]<=directory_q;
    endcase
    if(entry_byte==31) state<=ENTRY_CHECK;
    else begin entry_byte<=entry_byte+1'b1;directory_addr<=directory_addr+1'b1;state<=ENTRY_WAIT;end
   end
   ENTRY_CHECK: begin
    if(entry_first==0) begin scan_done<=1;state<=IDLE;end
    else if(entry_first==8'he5 || (entry_attr & 8'h1e)!=0 ||
      (AUDIO_MODE ? (entry_name!="01      " || (ext0 & 8'hdf)!="W" || (ext1 & 8'hdf)!="A" || (ext2 & 8'hdf)!="V") :
      ((ext0 & 8'hdf)!="B" || (ext1 & 8'hdf)!="M" || (ext2 & 8'hdf)!="P")) ||
      entry_cluster<2 || entry_cluster>last_cluster_q || entry_size<54) state<=NEXT_ENTRY;
    else begin
     file_cluster<=entry_cluster;map_cluster<=entry_cluster;candidate_size<=entry_size;
     map_kind<=MAP_HEADER;settle<=0;opening_file<=0;state<=MAP_WAIT;
    end
   end
   NEXT_ENTRY: begin
    if(entry_index!=15) begin entry_index<=entry_index+1'b1;state<=ENTRY_INIT;end
    else if(dir_sector+8'd1<spc) begin
     dir_sector<=dir_sector+1'b1;dir_lba<=dir_lba+1'b1;sd_sec_read_addr<=dir_lba+1'b1;state<=DIR_READ;
    end else begin
     fat_cluster<=dir_cluster;fat_for_directory<=1;settle<=0;state<=FAT_ADDR;
    end
   end
   HEADER_READ: begin
    sd_sec_read<=1;
    if(sd_sec_read_end) begin sd_sec_read<=0;settle<=0;state<=HEADER_CHECK;end
   end
   HEADER_CHECK: begin
    settle<=settle+1'b1;
    if(settle==5) begin
     if(!header_ok) state<=opening_file ? FATAL : NEXT_ENTRY;
     else if(opening_file) begin write_req<=1;scale2x<=!AUDIO_MODE && (width==320);state<=WRITE_WAIT;end
     else begin
      catalogue_cluster[scan_found_total[3:0]]<=file_cluster;
      catalogue_size[scan_found_total[3:0]]<=candidate_size;
      scan_found_sector<={28'd0,scan_found_total};scan_found_valid<=1;
      scan_found_total<=scan_found_total+1'b1;
      if(scan_found_total==9 || scan_found_total+1'b1>=scan_target_count) scan_done<=1;
      state<=IDLE;
     end
    end
   end
   WRITE_WAIT: begin
    state_code<=3;
    if(write_req_ack) begin
     write_req<=0;file_sector<=0;map_cluster<=file_cluster;map_kind<=MAP_DATA;settle<=0;state<=MAP_WAIT;
    end
   end
   DATA_READ: begin
    state_code<=4;sd_sec_read<=AUDIO_MODE ? audio_can_read : (!scale2x || scale_idle);
    if(sd_sec_read_end) begin sd_sec_read<=0;state<=DATA_NEXT;end
    if(scale_error) begin sd_sec_read<=0;state<=FATAL;end
   end
   DATA_NEXT: begin
    if(file_byte_count>=pixel_end_q[31:0]) begin settle<=0;state<=DRAIN;end
    else if(file_sector+8'd1<spc) begin
     file_sector<=file_sector+1'b1;sd_sec_read_addr<=sd_sec_read_addr+1'b1;state<=DATA_READ;
    end else begin fat_cluster<=file_cluster;fat_for_directory<=0;settle<=0;state<=FAT_ADDR;end
   end
   FAT_ADDR: begin
    settle<=settle+1'b1;
    if(settle==3) begin
     if(fat_lba[32]) state<=FATAL;
     else begin sd_sec_read_addr<=fat_lba[31:0];state<=FAT_READ;end
    end
   end
   FAT_READ: begin
    sd_sec_read<=1;
    if(sd_sec_read_end) begin sd_sec_read<=0;state<=FAT_CHECK;end
   end
   FAT_CHECK: begin
    if(next_cluster>=28'hffffff8) begin
     if(fat_for_directory) begin scan_done<=1;state<=IDLE;end
     else state<=FATAL; // A short chain cannot produce a complete image.
    end else if(next_cluster<2 || next_cluster>=28'hffffff0 ||
                {4'd0,next_cluster}>last_cluster_q || next_cluster==fat_cluster[27:0]) state<=FATAL;
    else begin
     map_cluster<={4'd0,next_cluster};settle<=0;state<=MAP_WAIT;
     if(fat_for_directory) begin
      if(dir_hops==255) state<=FATAL;
      dir_hops<=dir_hops+1'b1;dir_cluster<={4'd0,next_cluster};dir_sector<=0;map_kind<=MAP_DIR;
     end else begin file_cluster<={4'd0,next_cluster};file_sector<=0;map_kind<=MAP_DATA;end
    end
   end
   DRAIN: begin
    if(settle!=15) settle<=settle+1'b1;
    if(settle>=4 && scale_idle && !bmp_data_wr_en) state<=IDLE;
   end
   FATAL:begin state_code<=4'he;sd_sec_read<=0;write_req<=0;end
   default:state<=FATAL;
  endcase
 end
end
endmodule
