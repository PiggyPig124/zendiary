param(
  [string]$ReleaseDir = (Join-Path (Join-Path $PSScriptRoot '..') 'build\windows\x64\runner\Release'),
  [string]$DataRoot,
  [ValidateRange(1, 1440)]
  [int]$TodoMinutes = 20,
  [ValidateRange(1, 1440)]
  [int]$EventMinutes = 8,
  [switch]$NoSeed,
  [switch]$Background
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$trialRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'tmp'))
$trialPrefix = $trialRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

if ([string]::IsNullOrWhiteSpace($DataRoot)) {
  $DataRoot = Join-Path $trialRoot ('windows-reminder-trial-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
} else {
  $DataRoot = [IO.Path]::GetFullPath($DataRoot)
}
if (-not $DataRoot.StartsWith($trialPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "DataRoot 必须位于仓库 tmp 目录内，以确保试用不会接触用户数据：$trialRoot"
}

$releaseExe = Join-Path ([IO.Path]::GetFullPath($ReleaseDir)) 'zendiary.exe'
if (-not (Test-Path -LiteralPath $releaseExe -PathType Leaf)) {
  throw "找不到 Windows Release 可执行文件：$releaseExe"
}

$dataDir = Join-Path $DataRoot 'data'
$appData = Join-Path $DataRoot 'appdata'
$localAppData = Join-Path $DataRoot 'localappdata'
New-Item -ItemType Directory -Force -Path $dataDir, $appData, $localAppData | Out-Null

# The explicit --data-dir mode stores SharedPreferences at
# <data-dir>\shared_preferences.json. These environment values are inherited
# by the child for plugins that honor APPDATA/LOCALAPPDATA; the explicit data
# directory remains the isolation boundary for the app profile. They do not
# change the user's shell after this script exits.
$env:APPDATA = $appData
$env:LOCALAPPDATA = $localAppData
$env:PUB_CACHE = Join-Path $repoRoot 'tmp\pub-cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

if (-not $NoSeed) {
  $dart = Join-Path $repoRoot 'tmp\flutter\bin\dart.bat'
  if (-not (Test-Path -LiteralPath $dart -PathType Leaf)) {
    throw "找不到项目附带的 Dart SDK：$dart"
  }
  & $dart run (Join-Path $repoRoot 'tool\seed_windows_reminder_trial.dart') `
    --data-dir $dataDir --todo-minutes $TodoMinutes --event-minutes $EventMinutes
  if ($LASTEXITCODE -ne 0) {
    throw "试用种子写入失败，退出码：$LASTEXITCODE"
  }
}

$arguments = @('--data-dir', $dataDir)
if ($Background) { $arguments += '--background' }
$process = Start-Process -FilePath $releaseExe -ArgumentList $arguments -PassThru

Write-Output "ZenDiary 隔离试用进程已启动：PID=$($process.Id)"
Write-Output "Release=$releaseExe"
Write-Output "DataRoot=$DataRoot"
Write-Output "DataDir=$dataDir"
Write-Output "SharedPreferences=$dataDir\shared_preferences.json"
Write-Output "APPDATA=$appData"
Write-Output "LOCALAPPDATA=$localAppData"
Write-Output "请保持该进程存活；关闭窗口只应隐藏到托盘，退出托盘会结束本次试用。"
Write-Output "不要在进程退出后点击遗留通知：Windows 冷启动可能没有原 --data-dir 参数。"
