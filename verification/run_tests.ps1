$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$simBin = 'C:\FPGA\tools\mingw64\bin'
$env:PATH = "$simBin;" + $env:PATH
$env:TEMP = 'C:\FPGA\tools'
$env:TMP = $env:TEMP
$hdl = '../src/user_source/hdl_source'
$sources = @("$hdl/SD/bmp_read.v", "$hdl/campus/bmp_scale2x.v", "$hdl/campus/campus_overlay.v", "$hdl/campus/campus_font.v", "$hdl/campus/campus_swap.v", "$hdl/SD/sd_card_bmp.v", "$hdl/video_rgb_to_axis_640x480.v", "$hdl/SD/video_timing_data.v", "$hdl/SD/color_bar.v")
$results = @()
foreach ($test in @('tb_campus','tb_swap','tb_sd_mailbox','tb_timing','tb_fat32_v3')) {
    & "$simBin/iverilog.exe" -g2012 -i -I "$hdl/SD" -s $test -o "$test.vvp" "$test.sv" @sources
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $test" }
    $output = & "$simBin/vvp.exe" "$test.vvp" 2>&1
    $output | Write-Output
    $results += $output
    if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $test" }
}
$results | Set-Content -Encoding utf8 simulation_results.txt
& "$simBin/iverilog.exe" -g2012 -s tb_fat32_v3 '-Ptb_fat32_v3.QUICK_MULTI=1' -o tb_fat32_multi.vvp tb_fat32_v3.sv "$hdl/SD/bmp_read.v" "$hdl/campus/bmp_scale2x.v"
if ($LASTEXITCODE -ne 0) { throw 'Compile failed: multi-sector clusters' }
$multi = & "$simBin/vvp.exe" tb_fat32_multi.vvp 2>&1
$multi | Write-Output
$multi | Set-Content -Encoding utf8 multi_cluster_results.txt
if ($LASTEXITCODE -ne 0) { throw 'Simulation failed: multi-sector clusters' }
