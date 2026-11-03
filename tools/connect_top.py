from pathlib import Path
import re
R=Path(__file__).resolve().parents[1];H=R/'src/user_source/hdl_source'
p=H/'SD/sd_card_bmp.v';s=p.read_text(encoding='utf-8-sig')
assert 'music_pcm_valid' not in s
s=s.replace('input                       SD_MISO','input music_can_read, output music_pcm_valid, output [31:0] music_pcm_data, output [3:0] music_status,\n    input                       SD_MISO')
insertion='''wire phy_req,phy_valid,phy_end,audio_req,audio_valid_sd,audio_end_sd;
wire [31:0] phy_addr,audio_addr;
sd_audio_loop music(.clk(clk),.rst(rst),.sd_init_done(sd_init_done),.can_read(music_can_read),
 .sec_req(audio_req),.sec_addr(audio_addr),.sec_data(sd_sec_read_data),
 .sec_valid(audio_valid_sd),.sec_end(audio_end_sd),.pcm_valid(music_pcm_valid),.pcm_data(music_pcm_data),.status(music_status));
sd_sector_arbiter arb(.clk(clk),.rst(rst),.image_req(sd_sec_read),.image_addr(sd_sec_read_addr),
 .image_valid(sd_sec_read_data_valid),.image_end(sd_sec_read_end),
 .audio_req(audio_req),.audio_addr(audio_addr),.audio_valid(audio_valid_sd),.audio_end(audio_end_sd),
 .req(phy_req),.addr(phy_addr),.valid(phy_valid),.finish(phy_end));
'''
a=s.index('sd_card_top sd_card_top_m0(')
s=s[:a]+insertion+s[a:]
a=s.index('sd_card_top sd_card_top_m0(')
t=s[a:]
for x,y in [('(sd_sec_read)','(phy_req)'),('(sd_sec_read_addr)','(phy_addr)'),('(sd_sec_read_data_valid)','(phy_valid)'),('(sd_sec_read_end)','(phy_end)')]:t=t.replace(x,y)
s=s[:a]+t
s=s.replace('(auto_cnt == (CLK_FREQ_HZ - 1))','(auto_cnt == (CLK_FREQ_HZ * 5 - 1))')
p.write_text(s,encoding='utf-8')
p=H/'top_tf_hdmi_audio.v';s=p.read_text(encoding='utf-8-sig')
s=s.replace('.CLK_FREQ_HZ       (100_000_000)', '.CLK_FREQ_HZ       (50_000_000)')
s=s.replace('wire        audio_valid;', '''wire music_can_read,music_pcm_valid;
wire [31:0] music_pcm_data,music_underruns;
wire music_overflow;
wire [3:0] music_status;
wire        audio_valid;''')
a=s.index('sd_card_bmp #(');b=s.index(');',a)
s=s[:b]+',\n    .music_can_read(music_can_read),.music_pcm_valid(music_pcm_valid),.music_pcm_data(music_pcm_data),.music_status(music_status)\n'+s[b:]
a=s.index('hdmi_audio_tone_i2s_64fs #(');b=s.index('audio_arc_calculate #(',a)
s=s[:a]+'''pcm_hdmi_bridge music_output(.sd_clk(sd_card_clk),.video_clk(video_clk),.rst(rst_all),.enable(image_visible),
 .pcm_valid(music_pcm_valid),.pcm_data(music_pcm_data),.can_read(music_can_read),
 .audio_valid(audio_valid),.audio_left(audio_left_data),.audio_right(audio_right_data),
 .underruns(music_underruns),.overflow(music_overflow));

'''+s[b:]
p.write_text(s,encoding='utf-8')
# Fixed VCO remains 1 GHz: feedback is from C0 so FBCLK_DIV must change with C0.
# Keep C0 at 100 MHz for now; adjust clock only after functional tests if needed.
p=H/'top_tf_hdmi_audio.v';s=p.read_text(encoding='utf-8').replace('.CLK_FREQ_HZ       (50_000_000)', '.CLK_FREQ_HZ       (100_000_000)');p.write_text(s,encoding='utf-8')
# 31.25 MHz SDRAM clock, 180-degree shifted partner; slower physical timing, same SD/video clocks.
p=H/'IP/sys_pll.v';s=p.read_text(encoding='utf-8-sig').replace('.CLKC1_DIV(8)','.CLKC1_DIV(32)').replace('.CLKC1_CPHASE(7)','.CLKC1_CPHASE(31)').replace('.CLKC2_DIV(8)','.CLKC2_DIV(32)').replace('.CLKC2_CPHASE(3)','.CLKC2_CPHASE(15)');p.write_text(s,encoding='utf-8')
p=H/'include/global_def.v';s=p.read_text(encoding='utf-8-sig').replace('1000000000/125000000','1000000000/31250000');p.write_text(s,encoding='utf-8')
