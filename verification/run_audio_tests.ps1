$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
$sim='C:/FPGA/tools/mingw64/bin'
$env:PATH="$sim;"+$env:PATH
$env:TEMP='C:/FPGA/tools';$env:TMP=$env:TEMP
$h='../src/user_source/hdl_source'
$sources=@("$h/SD/bmp_read.v","$h/campus/bmp_scale2x.v","$h/campus/sd_audio_loop.v","$h/campus/pcm_hdmi_bridge.v","$h/campus/wav_pcm_stream.v")
foreach($test in @('tb_wav','tb_pcm_bridge','tb_audio_fat','tb_ten_catalog')) {
 & "$sim/iverilog.exe" -g2012 -s $test -o "$test.vvp" "$test.sv" @sources
 if($LASTEXITCODE -ne 0){throw "Compile failed: $test"}
 & "$sim/vvp.exe" "$test.vvp" | Tee-Object "$test.results.txt"
 if($LASTEXITCODE -ne 0){throw "Test failed: $test"}
}
