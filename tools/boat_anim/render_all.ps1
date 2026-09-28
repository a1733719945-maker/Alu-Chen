$ErrorActionPreference = "Continue"
$env:PATH = "$env:TEMP\node22\node-v22.23.3-win-x64;" + $env:PATH
Set-Location "$env:TEMP\ba"
$ff = "$env:TEMP\ffm2\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"
New-Item -ItemType Directory -Force "$env:TEMP\ba\out\final" | Out-Null
$list = @(@("DungeonGate", "dungeon", 7), @("HuntGate", "hunt", 7), @("Voyage", "voyage", 7), @("Ascend", "ascend", 7), @("Prologue", "prologue", 6))
foreach ($c in $list) {
	$id = $c[0]; $name = $c[1]; $q = $c[2]
	$t0 = Get-Date
	& ".\node_modules\.bin\remotion.cmd" render src/index.ts $id "out/final/$name.mp4" --codec=h264 --crf=14 --log=error 2>&1 | Select-String -NotMatch "Rendered|Bundling|Getting|Encoded|Stitch" | Select-Object -Last 5
	& $ff -y -loglevel error -i "out/final/$name.mp4" -c:v libtheora -q:v $q -an "out/final/$name.ogv"
	"$name done in $([int]((Get-Date) - $t0).TotalSeconds)s, ogv $((Get-Item "out/final/$name.ogv").Length)"
}
& ".\node_modules\.bin\remotion.cmd" still src/index.ts Gourd "out/final/gourd.png" --log=error 2>&1 | Select-Object -Last 1
& $ff -y -loglevel error -i "out/final/gourd.png" -q:v 2 "out/final/w03.jpg"
"ALL DONE"
