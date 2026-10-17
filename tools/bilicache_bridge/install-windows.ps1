param([string]$ExtensionId, [string]$CacheRoot, [string]$Player)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
if (-not $ExtensionId) { $ExtensionId = Read-Host 'Chrome 扩展 ID（下载页的播放器联动设置中显示）' }
if (-not $CacheRoot) {
  $picker = New-Object System.Windows.Forms.FolderBrowserDialog
  $picker.Description = '选择与 Chrome 中相同的 BiliCache 根目录'
  if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }
  $CacheRoot = $picker.SelectedPath
}
if (-not $Player) {
  $picker = New-Object System.Windows.Forms.OpenFileDialog
  $picker.Title = '选择你的 NipaPlay fork 播放器'; $picker.Filter = 'NipaPlay executable (*.exe)|*.exe'
  if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }
  $Player = $picker.FileName
}
& (Join-Path $PSScriptRoot 'bilicache_setup.exe') install --extension-id $ExtensionId --cache-root $CacheRoot --player $Player
exit $LASTEXITCODE
