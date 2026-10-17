# Runs the customer app on a phone in debug and hot-reloads it whenever a Dart file under lib/ changes.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1 [-Device RZ8M9351AKY]
#
# It drives a plain `flutter run` and types `r` (hot reload) into it after the files settle. Ctrl-C stops it.
param([string]$Device = 'RZ8M9351AKY')

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = (Get-Command flutter -ErrorAction Stop).Source }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $flutter
$psi.Arguments = "run -d $Device"
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$p = [System.Diagnostics.Process]::Start($psi)
$script:appId = $null
$script:nextId = 1

$out = Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -Action {
  if ($EventArgs.Data) {
    $line = $EventArgs.Data
    if ($line -match 'Flutter DevTools|VM Service|Syncing files|Reloaded|Restarted|Hot reload|Error|Exception') { $global:HpReady = $true }
    Write-Host $line
  }
}
$err = Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived -Action {
  if ($EventArgs.Data) { Write-Host ('[err] ' + $EventArgs.Data) }
}
$p.BeginOutputReadLine()
$p.BeginErrorReadLine()

$w = New-Object System.IO.FileSystemWatcher
$w.Path = Join-Path $root 'lib'
$w.Filter = '*.dart'
$w.IncludeSubdirectories = $true
$w.NotifyFilter = [System.IO.NotifyFilters]'LastWrite, FileName'
$w.EnableRaisingEvents = $true

Write-Host "[dev] starting on $Device - building the debug app, this takes a minute..."
try {
  while (-not $p.HasExited) {
    $r = $w.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
    if ($r.TimedOut) { continue }
    # Let a burst of saves finish, then reload once.
    Start-Sleep -Milliseconds 600
    $p.StandardInput.WriteLine('r')
    $p.StandardInput.Flush()
    Write-Host ('[dev] hot reload: ' + $r.Name)
  }
}
finally {
  if (-not $p.HasExited) { try { $p.Kill() } catch {} }
  Unregister-Event -SourceIdentifier $out.Name -ErrorAction SilentlyContinue
  Unregister-Event -SourceIdentifier $err.Name -ErrorAction SilentlyContinue
}
