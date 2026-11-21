# Octopus Fragment 一键构建/发版脚本（通过 build.bat 调用）
#
# 用法：
#   build.bat            按当前版本号构建（版本号唯一来源：lib/Actions.ahk 的 App.Version）
#   build.bat 1.0.4      先把版本号改为 1.0.4，再编译打包
#
# 版本号只改 lib/Actions.ahk 一处；OctopusFragment.ahk 的 ;@Ahk2Exe-SetVersion
# 每次构建自动同步，不再需要手动维护两处。

param([string]$Version = "")

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Fail($msg) {
    Write-Host "[build] 错误：$msg" -ForegroundColor Red
    exit 1
}

# 写 UTF-8 文本：已存在的文件保留原 BOM 状态，不改动换行符；新文件无 BOM
function Write-Utf8($Path, $Text) {
    $hasBom = $false
    if (Test-Path $Path) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($hasBom)))
}

# ---------- 1. 定位 Ahk2Exe ----------
# 注意 @() 再包一层：Where-Object 只剩一个结果时管道会把数组退化为标量
$ahk2ExeCandidates = @(
    @(
        $env:AHK2EXE,
        "$env:ProgramFiles\AutoHotkey\Compiler\Ahk2Exe.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\Compiler\Ahk2Exe.exe",
        "$env:ProgramFiles\AutoHotkey\v2\Compiler\Ahk2Exe.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
)
if (-not $ahk2ExeCandidates) {
    Fail "未找到 Ahk2Exe.exe。请安装 AutoHotkey v2，或设置环境变量 AHK2EXE 指向编译器"
}
$Ahk2Exe = $ahk2ExeCandidates[0]

$baseCandidates = @(
    @(
        (Join-Path (Split-Path -Parent (Split-Path -Parent $Ahk2Exe)) "v2\AutoHotkey64.exe"),
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    ) | Where-Object { Test-Path $_ }
)
$Base = $baseCandidates[0]          # 为空时 Ahk2Exe 使用默认 base

# ---------- 2. 版本号 ----------
$actionsPath = "$Root\lib\Actions.ahk"
$entryPath   = "$Root\OctopusFragment.ahk"

$actions = [System.IO.File]::ReadAllText($actionsPath)
if ($actions -notmatch '(?m)static Version\s*:=\s*"([^"]+)"') {
    Fail "lib/Actions.ahk 中未找到 App.Version（版本号唯一来源）"
}
$Ver = $Matches[1]

if ($Version -ne "") {
    if ($Version -notmatch '^\d+\.\d+(\.\d+)?$') {
        Fail "版本号格式应为 x.y 或 x.y.z（收到：$Version）"
    }
    if ($Version -ne $Ver) {
        # 替换串里用 ${1}：$1 后面紧跟版本号数字会拼成 $11 被当成第 11 个捕获组
        $actions = $actions -replace '(?m)(static Version\s*:=\s*")[^"]+(")', "`${1}$Version`${2}"
        Write-Utf8 $actionsPath $actions
        Write-Host "[build] App.Version：$Ver -> $Version"
        $Ver = $Version
    }
}

# exe 元数据的 SetVersion 自动同步为 App.Version
$entry = [System.IO.File]::ReadAllText($entryPath)
if ($entry -notmatch '(?m);@Ahk2Exe-SetVersion\s+(\S+)') {
    Fail "OctopusFragment.ahk 中未找到 ;@Ahk2Exe-SetVersion"
}
$metaVer = $Matches[1]
if ($metaVer -ne $Ver) {
    $entry = $entry -replace '(?m)(;@Ahk2Exe-SetVersion\s+)\S+', "`${1}$Ver"
    Write-Utf8 $entryPath $entry
    Write-Host "[build] SetVersion 元数据已同步：$metaVer -> $Ver"
}

Write-Host "[build] 版本：$Ver"

# ---------- 3. 编译 ----------
# Ahk2Exe.exe 是 GUI 程序：直接 & 调用 PowerShell 不等待、拿不到退出码，
# 必须用 Start-Process -Wait，并重定向输出便于排错
$distDir = "$Root\dist"
New-Item -ItemType Directory -Force $distDir | Out-Null
$outExe = "$distDir\OctopusFragment.exe"
if (Test-Path $outExe) { Remove-Item -Force $outExe }
$argList = @("/silent", "verbose")
if ($Base) { $argList += @("/base", $Base) }
$argList += @("/in", "$Root\OctopusFragment.ahk", "/out", $outExe)
$argStr = ($argList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
$stdoutLog = "$distDir\ahk2exe.out.log"
$stderrLog = "$distDir\ahk2exe.err.log"
$proc = Start-Process -FilePath $Ahk2Exe -ArgumentList $argStr -Wait -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
if ($proc.ExitCode -ne 0 -or -not (Test-Path $outExe)) {
    $out = (Get-Content $stdoutLog -Raw -ErrorAction SilentlyContinue)
    $err = (Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue)
    Write-Host $out $err
    Fail "Ahk2Exe 编译失败（exit=$($proc.ExitCode)）"
}
Remove-Item $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue
Write-Host "[build] 编译完成：$outExe"

# ---------- 4. 打包 ----------
$relDir = "$distDir\OctopusFragment-v${Ver}-win64"
if (Test-Path $relDir) { Remove-Item -Recurse -Force $relDir }
New-Item -ItemType Directory -Force $relDir | Out-Null
Copy-Item $outExe $relDir
Copy-Item "$Root\README.md" $relDir
$zip = "$distDir\OctopusFragment-v${Ver}-win64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$relDir\*" -DestinationPath $zip -Force
Write-Host "[build] 打包完成：$zip"

# ---------- 5. 发布说明模板（已存在则不覆盖） ----------
$notes = "$distDir\RELEASE_NOTES_v${Ver}.md"
if (-not (Test-Path $notes)) {
    $log = ""
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $lastTag = & git -C $Root describe --tags --abbrev=0 2>$null
        if ($lastTag) {
            $log = (& git -C $Root log --oneline "$lastTag..HEAD" 2>$null | ForEach-Object { "- $_" }) -join "`n"
        }
        $ErrorActionPreference = $prevEap
    }
    $tpl = @"
# Release Notes · v${Ver}

发布日期：$(Get-Date -Format "yyyy-MM-dd")
适用平台：Windows x64（AutoHotkey v2 编译，无需安装 AHK）

## 新功能

（待填写）

## 修复

（待填写）

## 自上次发布以来的提交

$log

## 安装 / 升级

1. 解压 OctopusFragment-v${Ver}-win64.zip；
2. 退出正在运行的旧版本（托盘右键 → 退出）；
3. 运行 OctopusFragment.exe（首次运行会在同目录生成 data\ 数据目录）。
"@
    Write-Utf8 $notes $tpl
    Write-Host "[build] 已生成发布说明模板：$notes"
}

# ---------- 6. 收尾提示 ----------
Write-Host ""
Write-Host "[build] 构建完成，发布收尾步骤：" -ForegroundColor Green
Write-Host "  1. 补充 dist\RELEASE_NOTES_v${Ver}.md"
Write-Host "  2. git add -A && git commit（版本号改动等）"
Write-Host "  3. git tag v${Ver}"
Write-Host "  4. git push origin master --tags（如需发布到 GitHub）"
Write-Host "  5. 在 GitHub Releases 上传 dist\OctopusFragment-v${Ver}-win64.zip"
