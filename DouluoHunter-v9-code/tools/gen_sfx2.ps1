# 第二版音效：枪声、换弹、命中、卖东西、海鸥、水下。Windows 自带的 PowerShell 就能跑，不用装 Python。
# 用法：powershell -ExecutionPolicy Bypass -File tools/gen_sfx2.ps1
# 注意：tools/gen_sfx.py 会生成同名的旧版枪声，跑完它以后要再跑一次这个。
$root = [IO.Path]::GetDirectoryName($PSScriptRoot)
Add-Type -Path (Join-Path $PSScriptRoot "GenSfx2.cs")
[GenSfx2]::Run((Join-Path $root "game/assets/sfx"))
Write-Output "done"
