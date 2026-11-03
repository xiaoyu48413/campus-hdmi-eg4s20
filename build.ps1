$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$run = Join-Path $root 'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1'
$release = Join-Path $root 'release'
New-Item -ItemType Directory -Path $release -Force | Out-Null
Push-Location $run
try {
    $started = Get-Date
    & 'D:\anlu.app\bin\td_commands_prompt.exe' 'D:/anlu.app/doc/scripts/DefaultFlow.tcl' *> build_extension.log
    $log = Get-Content ./build_extension.log -Raw
    $bit = Get-Item './HDMI1.4b_Transmitter_v1.0.bit'
    if ($log -match 'ERROR:|couldn.t read|can.t read' -or $bit.LastWriteTime -lt $started) {
        throw 'TD build failed. See build_extension.log; no release updated.'
    }
    Copy-Item -LiteralPath $bit.FullName -Destination (Join-Path $release 'campus_hdmi_v5_reliable_trial.bit')
    Copy-Item './HDMI1.4b_Transmitter_v1.0_pr.timing' (Join-Path $release 'timing_report.txt')
    Copy-Item './HDMI1.4b_Transmitter_v1.0_phy.area' (Join-Path $release 'resource_report.txt')
    Copy-Item './build_extension.log' (Join-Path $release 'build_extension.log')
    Get-FileHash (Join-Path $release 'campus_hdmi_v5_reliable_trial.bit') -Algorithm SHA256 |
        Format-List | Out-String | Set-Content (Join-Path $release 'bit_sha256.txt') -Encoding utf8
    Get-ChildItem (Join-Path $root 'src/user_source'),(Join-Path $root 'src/td_project/al_ip') -File -Recurse |
        Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash |
        Export-Csv (Join-Path $release 'source_sha256.csv') -NoTypeInformation -Encoding utf8
    Write-Output 'Bitstream generated. Timing is NOT accepted until all real violations are resolved.'
    Select-String -Path (Join-Path $release 'timing_report.txt') -Pattern 'SWNS:|HWNS:' | Select-Object -First 2
} finally { Pop-Location }
