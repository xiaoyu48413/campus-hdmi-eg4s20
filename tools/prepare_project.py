from pathlib import Path
import shutil,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1];O=R.with_name('campus_hdmi_v3');P=R/'src/td_project';P.mkdir(exist_ok=True)
if not (P/'al_ip').exists():shutil.copytree(O/'src/td_project/al_ip',P/'al_ip')
name='HDMI1.4b_Transmitter_v1.0'
run=P/(name+'_Runs')/'syn_1';run.mkdir(parents=True,exist_ok=True)
shutil.copyfile(O/'src/td_project'/f'{name}.al',P/f'{name}.al')
oldrun=O/'src/td_project'/(name+'_Runs')/'syn_1'
shutil.copyfile(oldrun/'settings.cfg',run/'settings.cfg')
shutil.copyfile(oldrun/f'{name}.prj',run/f'{name}.prj')
new=['campus/sd_audio_loop.v','campus/pcm_hdmi_bridge.v']
for file in [P/f'{name}.al',run/f'{name}.prj']:
 s=file.read_text(encoding='utf-8-sig')
 assert '</Verilog>' in s
 prefix='../user_source/hdl_source/' if file.suffix=='.al' else '../../../user_source/hdl_source/'
 for i,n in enumerate(new):
  entry=f'<File Path="{prefix+n}"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{200+i}"/></FileInfo></File>\n'
  s=s.replace('</Verilog>',entry+'</Verilog>')
 file.write_text(s,encoding='utf-8')
s=(O/'build.ps1').read_text(encoding='utf-8-sig').replace('campus_hdmi_v3_trial.bit','campus_hdmi_v4_trial.bit')
(R/'build.ps1').write_text(s,encoding='utf-8-sig')
# Update test ports to actual ten-image widths.
p=R/'verification/tb_fat32_v3.sv';s=p.read_text(encoding='utf-8-sig').replace('wire[2:0] count','wire[3:0] count').replace('.scan_target_count(3\'d4)',".scan_target_count(4'd4)");p.write_text(s,encoding='utf-8')
# File extensions in original IP file names are case-insensitive on Windows.
print('Fresh project and build configuration prepared, no previous build products copied.')
