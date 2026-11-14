<#
  Builds Photo Downloader on Windows from the command line (PowerShell).

    windows\build.ps1                 Release and debug builds, with the same build number
    windows\build.ps1 -Mode Release   Release build only (small)  -> bin\win64-release\PhotoDownloader.exe
    windows\build.ps1 -Mode Default   debug build only            -> bin\win64\PhotoDownloader.exe
    windows\build.ps1 -NoGit          build without pulling and pushing the build number

  The build number: one number per version of the program code. build-stamp.txt holds the number and a
  fingerprint of the program sources (units, project file without its BuildNr line); when the sources
  changed since then, the number goes up by one, otherwise it stays, so debug and Release builds of the
  same code (and the builds on Windows and Linux) carry the same number. PhotoDownloader.lpi holds that
  number (AutoIncrementBuild is off). The script first pulls from GitHub; after a successful build with
  a new number it commits only PhotoDownloader.lpi and build-stamp.txt ("Built 0.1.4.N (Windows)") and
  pushes them. The lines lazbuild rewrites in the project file are put back as they were.
  Linux: linux/build.sh (computes the same fingerprint).
#>
param(
  [ValidateSet('Both', 'Release', 'Default')] [string]$Mode = 'Both',  # which build modes
  [switch]$NoGit  # no pull before and no push after
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)  # the project folder (this script lies in windows\)
$Lpi = 'PhotoDownloader.lpi'
$Stamp = 'build-stamp.txt'
$Utf8 = New-Object System.Text.UTF8Encoding($false)  # files are written without a byte order mark
$Sync = (-not $NoGit) -and ((git rev-parse --is-inside-work-tree 2>$null) -eq 'true')

if ($Sync) {
  Write-Host 'Getting the newest version from GitHub (git pull) ...'
  git pull --ff-only --quiet
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'git pull did not work (no network, or changes on both computers). The build number counts on from this copy.'
  }
}

$LazBuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $LazBuild) { $LazBuild = 'C:\lazarus\lazbuild.exe' }
if (-not (Test-Path -LiteralPath $LazBuild)) { throw 'lazbuild was not found. Install Lazarus 4.8, or add its folder to the PATH.' }

# fingerprint of the program sources: the units, include files and icon Git knows (normalized line endings,
# so it is the same on Windows and Linux) and the project file without the lines that change with each
# build; linux/build.sh computes the same value
function Get-SourceFingerprint {
  $lines = Get-Content -LiteralPath $Lpi | Where-Object { $_ -notmatch '<BuildNr |<AutoIncrementBuild |LCLWidgetType|<MacroValues|</MacroValues>' }
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), $Utf8)
    $lpiHash = (git hash-object --no-filters -- $tmp).Trim()
    $files = git ls-files -- '*.pas' '*.pp' '*.lpr' '*.inc' '*.lrs' '*.ico' '*.darkstylecolors' ':!plugins'
    $hashes = $files | git hash-object --stdin-paths
    [System.IO.File]::WriteAllText($tmp, (((@($hashes) + $lpiHash) -join "`n") + "`n"), $Utf8)
    return (git hash-object --no-filters -- $tmp).Trim()
  } finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  }
}

# the build number of this code: the stamp's number, one more when the sources changed
$fp = Get-SourceFingerprint
$stampNr = $null; $stampFp = ''
if (Test-Path -LiteralPath $Stamp) {
  $first = (Get-Content -LiteralPath $Stamp -TotalCount 1)
  if ($first -match '^(\d+) (.*)$') { $stampNr = [int]$Matches[1]; $stampFp = $Matches[2] }
}
$lpiText = [System.IO.File]::ReadAllText((Resolve-Path $Lpi))
if ($null -eq $stampNr) {  # no stamp yet: the number in the project file counts as used
  $stampNr = [int]([regex]::Match($lpiText, '<BuildNr Value="(\d+)"/>').Groups[1].Value)
}
$lpiBefore = $lpiText
$stampBefore = if (Test-Path -LiteralPath $Stamp) { [System.IO.File]::ReadAllText((Resolve-Path $Stamp)) } else { $null }
if ($fp -eq $stampFp) {
  $built = $stampNr
  Write-Host "The program code has not changed since build ${built}: the number stays."
} else {
  $built = $stampNr + 1
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Stamp), "$built $fp`n", $Utf8)
}
$lpiText = [regex]::Replace($lpiText, '<BuildNr Value="\d+"/>', "<BuildNr Value=""$built""/>")
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $Lpi), $lpiText, $Utf8)
$minor = [regex]::Match($lpiText, '<MinorVersionNr Value="(\d+)"/>').Groups[1].Value
$rev = [regex]::Match($lpiText, '<RevisionNr Value="(\d+)"/>').Groups[1].Value
$ver = "0.$minor.$rev.$built"

$modes = switch ($Mode) { 'Both' { @('Release', 'Default') } default { @($Mode) } }
$failed = $false
foreach ($m in $modes) {
  Write-Host "Building Photo Downloader $ver ($m) ..."
  $log = & $LazBuild -B "--build-mode=$m" $Lpi 2>&1
  $ok = $LASTEXITCODE -eq 0
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Lpi), $lpiText, $Utf8)  # undo the lines lazbuild rewrote
  if ($ok) {
    ($log | Select-String 'lines compiled' | Select-Object -Last 1)
    Write-Host "Done: $m (version $ver)"
  } else {
    $log | Select-String 'Error|Fatal' | Select-Object -First 20
    if ($log -match "Can't create") { Write-Host 'The program file could not be written: close Photo Downloader and build again.' }
    $failed = $true
    break
  }
}
if ($failed) {  # the number was not used: back to what it was
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Lpi), $lpiBefore, $Utf8)
  if ($null -ne $stampBefore) { [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Stamp), $stampBefore, $Utf8) }
  else { Remove-Item -LiteralPath $Stamp -ErrorAction SilentlyContinue }
  Write-Host 'Build failed.'
  exit 1
}

if ($Sync) {
  git diff --quiet HEAD -- $Lpi $Stamp 2>$null
  if ($LASTEXITCODE -ne 0) {  # a new number: send it to GitHub
    git add -- $Stamp
    git commit --quiet -m "Built $ver (Windows)" -- $Lpi $Stamp
    if ($LASTEXITCODE -eq 0) { git push --quiet }
    if ($LASTEXITCODE -eq 0) { Write-Host "Build number $built sent to GitHub." }
    else { Write-Warning 'The build number could not be sent to GitHub. Later: git push' }
  }
}
