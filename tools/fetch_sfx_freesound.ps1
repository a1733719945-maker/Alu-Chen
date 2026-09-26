# 从 freesound.org 下载 CC0（公有领域，可以随便用）的真实录音音效，转成游戏用的 wav。
# 用法：powershell -ExecutionPolicy Bypass -File tools/fetch_sfx_freesound.ps1 -Ffmpeg <ffmpeg.exe 路径>
# 每个音效：按关键词搜 CC0 结果，排除科幻 / 激光 / 卡通，挑时长合适、下载量最多的，下载高质量试听版，
# 切掉开头静音、截到合适长度、淡出、统一音量。用了哪些声音记在 game/assets/sfx/CREDITS_freesound.txt。
param([string]$Ffmpeg = "ffmpeg", [string[]]$Only = @())
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
$root = [IO.Path]::GetDirectoryName($PSScriptRoot)
$out = Join-Path $root "game/assets/sfx"
$tmp = Join-Path $env:TEMP "fs_dl"
New-Item -ItemType Directory -Force $tmp | Out-Null

# 名字 = 游戏里的音效名；q = 搜索词；min/max = 原始时长范围（秒）；len = 最后截到多长；vol = 峰值（dB）
$want = @(
	@{name="xiujian_fire"; q="pistol shot"; min=0.2; max=4; len=1.2; vol=-1},
	@{name="zhuge_fire"; q="gunshot"; min=0.15; max=2.5; len=0.7; vol=-1},
	@{name="kongque_fire"; q="rifle gunshot"; min=0.2; max=5; len=1.4; vol=-1},
	@{name="baoyu_fire"; q="shotgun shot"; min=0.3; max=4; len=1.6; vol=-1},
	@{name="zhuihun_fire"; q="sniper rifle shot"; min=0.4; max=6; len=2.4; vol=-1},
	@{name="mag_out"; q="magazine release"; min=0.1; max=3; len=0.6; vol=-4},
	@{name="mag_in"; q="magazine insert"; min=0.1; max=3; len=0.6; vol=-3},
	@{name="bolt_cycle"; q="bolt action rifle"; min=0.3; max=4; len=1.0; vol=-3},
	@{name="pump"; q="shotgun pump reload"; min=0.2; max=3; len=0.8; vol=-3},
	@{name="dry"; q="gun dry fire click"; min=0.05; max=2; len=0.3; vol=-6},
	@{name="hit"; q="bullet impact flesh"; min=0.1; max=2; len=0.35; vol=-3},
	@{name="punch"; q="punch hit"; min=0.1; max=2; len=0.45; vol=-2},
	@{name="boom"; q="explosion"; min=1.0; max=6; len=2.5; vol=-1},
	@{name="gull_cry"; q="seagull"; min=0.4; max=8; len=1.6; vol=-3},
	@{name="splash_big"; q="water splash big"; min=0.4; max=4; len=1.6; vol=-2},
	@{name="splash_small"; q="water splash small"; min=0.2; max=3; len=0.8; vol=-4},
	@{name="sell"; q="coins drop"; min=0.3; max=3; len=1.2; vol=-3},
	@{name="boss_roar"; q="monster roar"; min=1.0; max=6; len=3.0; vol=-1},
	@{name="skill_cast"; q="magic whoosh"; min=0.3; max=3; len=1.0; vol=-3},
	@{name="skill_launch"; q="earth impact"; min=0.4; max=6; len=1.8; vol=-2},
	@{name="skill_beam"; q="magic beam"; min=0.4; max=4; len=1.5; vol=-3},
	@{name="skill_buff"; q="power up magic"; min=0.4; max=4; len=1.6; vol=-4},
	@{name="skill_heal"; q="heal spell"; min=0.4; max=6; len=1.6; vol=-4},
	@{name="skill_dash"; q="fast whoosh"; min=0.2; max=2; len=0.6; vol=-3},
	@{name="thud"; q="heavy thud"; min=0.1; max=3; len=0.8; vol=-3},
	@{name="level_up"; q="level up"; min=0.5; max=6; len=2.2; vol=-4},
	@{name="kill_burst"; q="magic sparkle"; min=0.3; max=5; len=1.2; vol=-5}
)
$bad = "plasma|laser|sci-?fi|cartoon|toy|8-?bit|retro|game over|voice|music|loop|synth|robot|scifi|blaster|phaser|nerf|airsoft|cap gun"

$credits = @()
foreach ($w in $want) {
	if ($Only.Count -gt 0 -and -not ($Only -contains $w.name)) { continue }
	Start-Sleep -Seconds 2
	$url = "https://freesound.org/search/?q=" + [uri]::EscapeDataString($w.q) + "&f=license%3A%22Creative+Commons+0%22&s=Downloads+desc"
	try { $html = (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 60 -Headers @{"User-Agent"="Mozilla/5.0"}).Content } catch { Write-Output "search failed: $($w.name)"; continue }
	$best = $null
	foreach ($m in [regex]::Matches($html, '(?s)data-sound-id="(\d+)".*?data-username="([^"]*)".*?data-ogg="([^"]+)".*?data-title="([^"]*)".*?data-duration="([\d.]+)".*?data-num-downloads="(\d+)"')) {
		$title = [System.Net.WebUtility]::HtmlDecode($m.Groups[4].Value)
		$dur = [double]$m.Groups[5].Value
		if ($title -match $bad) { continue }
		if ($dur -lt $w.min -or $dur -gt $w.max) { continue }
		$best = @{id=$m.Groups[1].Value; user=$m.Groups[2].Value; ogg=$m.Groups[3].Value; title=$title; dur=$dur}
		break
	}
	if (-not $best) { Write-Output "no match: $($w.name)"; continue }
	$hq = $best.ogg -replace "-lq\.ogg$", "-hq.ogg"
	$src = Join-Path $tmp ($w.name + ".ogg")
	try { Invoke-WebRequest -UseBasicParsing -Uri $hq -OutFile $src -TimeoutSec 120 } catch { Invoke-WebRequest -UseBasicParsing -Uri $best.ogg -OutFile $src -TimeoutSec 120 }
	$dst = Join-Path $out ($w.name + ".wav")
	$fade = [Math]::Max($w.len - 0.25, 0.05)
	$mid = Join-Path $tmp ($w.name + "_cut.wav")
	$af = "silenceremove=start_periods=1:start_threshold=-45dB,atrim=0:$($w.len),afade=t=out:st=$($fade):d=0.25"
	& $Ffmpeg -hide_banner -loglevel error -y -i $src -ac 1 -ar 44100 -af $af -c:a pcm_s16le $mid
	# 峰值对齐到 vol dB
	$det = & $Ffmpeg -hide_banner -i $mid -af volumedetect -f null NUL 2>&1 | Out-String
	$peak = 0.0
	if ($det -match "max_volume:\s*(-?[\d.]+) dB") { $peak = [double]$Matches[1] }
	$gain = $w.vol - $peak
	& $Ffmpeg -hide_banner -loglevel error -y -i $mid -af "volume=$($gain)dB" -c:a pcm_s16le $dst
	$credits += "$($w.name).wav  <-  ""$($best.title)"" by $($best.user)  https://freesound.org/s/$($best.id)/  (CC0)"
	Write-Output ("ok  {0,-14} {1}s  {2}" -f $w.name, $best.dur, $best.title)
}
$cf = Join-Path $out "CREDITS_freesound.txt"
$old = @()
if (Test-Path $cf) { $old = Get-Content $cf -Encoding UTF8 | Where-Object { $n = ($_ -split "\.wav")[0]; -not ($credits | Where-Object { $_.StartsWith($n + ".wav") }) } }
($old + $credits) | Set-Content -Encoding UTF8 $cf
