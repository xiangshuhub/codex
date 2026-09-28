<#
.SYNOPSIS
  codex fork (rust-v0.157.1-lock1) 一键安装：锁定代理 + 时区版本。

.DESCRIPTION
  本脚本做四件事（全部幂等，可重复执行）：
    1. 替换 npm 安装的 codex.exe（原版备份为 codex_back.exe，只备份一次）
    2. 替换共享 app-server daemon 的 codex.exe（VS Code 扩展路径），并关闭
       daemon 自动更新（防止官方新版覆盖 fork）
    3. 若 ~/.codex/lock.toml 不存在则写入默认配置（已存在则保留）
    4. 逐一验证版本号

  用法（在解压后的目录里，PowerShell）:
    .\install.ps1              # 交互确认
    .\install.ps1 -Yes         # 免确认
    .\install.ps1 -RestartDaemon -Yes   # 装完顺手重启 daemon

  注意：安装过程会停止正在运行的 codex 进程。
#>
[CmdletBinding()]
param(
  [switch]$SkipNpm,
  [switch]$SkipDaemon,
  [switch]$RestartDaemon,
  [switch]$ForceLockToml,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$newExe = Join-Path $src 'codex.exe'
if (-not (Test-Path $newExe)) { throw "在 $src 旁边找不到 codex.exe" }
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }

function Get-Version([string]$exe) { (& $exe --version 2>$null) -join '' }

function Backup-And-Replace([string]$target) {
  $dir = Split-Path $target -Parent
  $backup = Join-Path $dir 'codex_back.exe'
  if (-not (Test-Path $backup)) {
    Copy-Item $target $backup -Force
    Write-Host "  备份原版 -> $backup"
  } else {
    Write-Host "  备份已存在，保留最早的 -> $backup"
  }
  Copy-Item $newExe $target -Force
  Write-Host "  替换完成 -> $target"
}

Write-Host "== codex fork 安装器 ==" -ForegroundColor Cyan
Write-Host "安装来源: $newExe ($((Get-Item $newExe).VersionInfo.FileVersion))"
Write-Host "检测版本: $(Get-Version $newExe)"
Write-Host "CODEX_HOME: $codexHome"

if (-not $Yes) {
  $answer = Read-Host "将停止 codex 进程并替换两处二进制 + 写入 lock.toml，继续? [y/N]"
  if ($answer -notmatch '^[yY]') { Write-Host "已取消"; exit 0 }
}

# 停止 codex 进程（替换前必须，否则文件被占用）
Get-Process codex -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "停止进程 $($_.Id) ($($_.Path))"
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# 1. npm vendor 位置
if (-not $SkipNpm) {
  Write-Host "`n[1/3] npm 位置" -ForegroundColor Yellow
  $npmRoot = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\node_modules'
  if (Test-Path $npmRoot) {
    $npmExes = Get-ChildItem $npmRoot -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty FullName
    if ($npmExes) {
      foreach ($exe in $npmExes) { Backup-AndReplace $exe }
    } else { Write-Host "  未找到 npm vendor codex.exe（跳过）" }
  } else { Write-Host "  未安装 npm 版 @openai/codex（跳过）" }
} else { Write-Host "`n[1/3] npm 位置 - SkipNpm 跳过" }

# 2. 共享 app-server daemon 位置（VS Code 扩展用）
if (-not $SkipDaemon) {
  Write-Host "`n[2/3] app-server daemon 位置" -ForegroundColor Yellow
  & $newExe app-server daemon stop 2>$null | Out-Null
  Start-Sleep -Seconds 2
  $daemonRoot = Join-Path $codexHome 'packages\app-server-daemon\releases'
  $daemonExes = @()
  if (Test-Path $daemonRoot) {
    $daemonExes = Get-ChildItem $daemonRoot -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty FullName
  }
  if ($daemonExes) {
    foreach ($exe in $daemonExes) { Backup-AndReplace $exe }
    # 关闭 daemon 自动更新
    $settingsFile = Join-Path $codexHome 'app-server-daemon\settings.json'
    $settingsDir = Split-Path $settingsFile -Parent
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null }
    $obj = if (Test-Path $settingsFile) {
      Get-Content $settingsFile -Raw | ConvertFrom-Json
    } else { New-Object PSObject }
    if (-not $obj.PSObject.Properties['updater'] -or -not $obj.updater) {
      $obj | Add-Member -NotePropertyName updater -NotePropertyValue (New-Object PSObject) -Force
    }
    if ($obj.updater.PSObject.Properties['autoUpdateEnabled']) {
      $obj.updater.autoUpdateEnabled = $false
    } else {
      $obj.updater | Add-Member -NotePropertyName autoUpdateEnabled -NotePropertyValue $false
    }
    $obj | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
    Write-Host "  daemon 自动更新已关闭 -> $settingsFile"
    if ($RestartDaemon) {
      & $newExe app-server daemon start 2>$null | Out-String | Write-Host
    } else {
      Write-Host "  daemon 未重启（下次使用时自动启动，或加 -RestartDaemon）"
    }
  } else { Write-Host "  未找到 daemon 安装（无 VS Code 扩展时正常，跳过）" }
} else { Write-Host "`n[2/3] daemon 位置 - SkipDaemon 跳过" }

# 3. lock.toml
Write-Host "`n[3/3] lock.toml" -ForegroundColor Yellow
$lockDst = Join-Path $codexHome 'lock.toml'
$lockSrc = Join-Path $src 'lock.toml.example'
if (Test-Path $lockDst) {
  if ($ForceLockToml) {
    Copy-Item $lockSrc $lockDst -Force
    Write-Host "  已覆盖 -> $lockDst"
  } else { Write-Host "  已存在，保留 -> $lockDst" }
} else {
  Copy-Item $lockSrc $lockDst -Force
  Write-Host "  已写入 -> $lockDst"
}

# 验证
Write-Host "`n== 验证 ==" -ForegroundColor Cyan
if (-not $SkipNpm) {
  $npmRoot = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\node_modules'
  if (Test-Path $npmRoot) {
    Get-ChildItem $npmRoot -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
      ForEach-Object { Write-Host "  npm: $(Get-Version $_.FullName)  ($($_.FullName))" }
  }
}
if (-not $SkipDaemon) {
  $daemonRoot = Join-Path $codexHome 'packages\app-server-daemon\releases'
  if (Test-Path $daemonRoot) {
    Get-ChildItem $daemonRoot -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq 'codex.exe' } |
      ForEach-Object { Write-Host "  daemon: $(Get-Version $_.FullName)  ($($_.FullName))" }
  }
}
Write-Host "`n完成。回滚：把各目录 codex_back.exe 复制回 codex.exe 即可。"
