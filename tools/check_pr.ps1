<#
.SYNOPSIS
	Reviews a pull request for changes that could compromise the reviewer or the
	people who download the game.

.DESCRIPTION
	This repository is a Godot project that ships a runnable binary. That
	creates two attack paths that ordinary code review does not catch:

	  1. Godot executes GDScript automatically. A change to project.godot
	     (autoloads, main scene) or to any script runs on the reviewer's
	     machine the moment they open the project and press F5.
	  2. The committed release/RTSDemo-win64.zip IS the thing partners
	     download and run. A pull request that swaps it ships malware.

	This script classifies every changed file by how dangerous it is, verifies
	the published checksum, and prints an explicit verdict.

.EXAMPLE
	powershell -File tools/check_pr.ps1
	powershell -File tools/check_pr.ps1 -Base origin/main -Head HEAD
#>
[CmdletBinding()]
param(
	[string]$Base = 'origin/main',
	[string]$Head = 'HEAD'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Get-ChangedFiles {
	$output = git diff --name-status "$Base...$Head" 2>$null
	if ($LASTEXITCODE -ne 0) { return @() }
	$rows = @()
	foreach ($line in $output) {
		if ($line -match '^([AMDRT])\s+(.+)$') {
			$rows += [PSCustomObject]@{ Status = $Matches[1]; Path = $Matches[2] }
		}
	}
	return $rows
}

# --- classification -------------------------------------------------------
function Get-Risk([string]$path, [string]$status) {
	if ($path -eq 'project.godot') {
		return @('CRITICAL', 'changes autoloads / main scene - runs on your machine on F5')
	}
	if ($path -match '\.gd$') {
		return @('CRITICAL', 'GDScript - executes when the project is opened or run')
	}
	if ($path -match '\.ps1$|\.bat$|\.cmd$') {
		return @('CRITICAL', 'shell script - executes when you run it')
	}
	if ($path -match '^release/.*\.zip$') {
		return @('CRITICAL', 'the artifact partners download and run')
	}
	if ($path -eq 'export_presets.cfg') {
		return @('HIGH', 'can point the export at a custom template')
	}
	if ($path -match '\.import$|\.tscn$') {
		return @('MEDIUM', 'scene/resource definition')
	}
	if ($status -eq 'D') {
		return @('MEDIUM', 'file deletion')
	}
	return @('LOW', 'docs / assets')
}

$changed = Get-ChangedFiles
if ($changed.Count -eq 0) {
	Write-Host "No file differences between $Base and $Head."
	exit 0
}

Write-Host ""
Write-Host "Pull request review  ($Base ... $Head)"
Write-Host ("=" * 78)

$buckets = @{ CRITICAL = @(); HIGH = @(); MEDIUM = @(); LOW = @() }
foreach ($file in $changed) {
	$risk = Get-Risk $file.Path $file.Status
	$buckets[$risk[0]] += [PSCustomObject]@{ Path = $file.Path; Status = $file.Status; Why = $risk[1] }
}

foreach ($level in @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')) {
	$items = $buckets[$level]
	if ($items.Count -eq 0) { continue }
	$color = switch ($level) {
		'CRITICAL' { 'Red' }
		'HIGH'     { 'Yellow' }
		'MEDIUM'   { 'Cyan' }
		default    { 'Gray' }
	}
	Write-Host ""
	Write-Host ("$level  ($($items.Count))") -ForegroundColor $color
	foreach ($item in $items) {
		Write-Host ("  {0}  {1}" -f $item.Status, $item.Path) -ForegroundColor $color
		Write-Host ("        {0}" -f $item.Why) -ForegroundColor DarkGray
	}
}

# --- integrity check ------------------------------------------------------
Write-Host ""
Write-Host "Published binary integrity"
Write-Host ("-" * 78)
$zip = 'release/RTSDemo-win64.zip'
$sum = 'release/RTSDemo-win64.zip.sha256'
if (Test-Path $zip) {
	$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
	Write-Host "  local sha256 : $actual"
	if (Test-Path $sum) {
		$expected = ((Get-Content $sum -Raw).Trim() -split '\s+')[0].ToLower()
		if ($expected -eq $actual) {
			Write-Host "  matches the committed checksum" -ForegroundColor Green
		}
		else {
			Write-Host "  DOES NOT MATCH the committed checksum" -ForegroundColor Red
			Write-Host "  -> the published binary was replaced. Diff it by hand before merging." -ForegroundColor Red
		}
	}
	else {
		Write-Host "  no committed checksum file - run tools/package_release.ps1 to create one" -ForegroundColor Yellow
	}
}
else {
	Write-Host "  release/RTSDemo-win64.zip not present locally (it only exists on a branch)" -ForegroundColor Yellow
}

# --- verdict --------------------------------------------------------------
$critical = $buckets['CRITICAL'].Count
Write-Host ""
Write-Host ("=" * 78)
if ($critical -gt 0) {
	Write-Host "VERDICT: $critical critical file(s) changed." -ForegroundColor Red
	Write-Host ""
	Write-Host "Before merging, confirm you personally reviewed every CRITICAL file." -ForegroundColor Yellow
	Write-Host "For release/*.zip: extract it somewhere disposable and run it BEFORE telling" -ForegroundColor Yellow
	Write-Host "anyone to download it." -ForegroundColor Yellow
	exit 2
}
Write-Host "VERDICT: no executable or distributable changes. Low risk." -ForegroundColor Green
exit 0
