<#
.SYNOPSIS
	Builds the playable Windows archive that is committed to the repository.

.DESCRIPTION
	Exports the Godot project to a release binary and packages it, together with
	the "how to play" notes, into release/RTSDemo-win64.zip.

	The raw .exe is ~104 MB, which exceeds GitHub's 100 MB per-blob limit, so the
	committed artifact has to be the compressed archive (about 36 MB).

.EXAMPLE
	powershell -File tools/package_release.ps1
#>
[CmdletBinding()]
param(
	[string]$Godot = 'E:\rts_demo\tools\godot\Godot_v4.7.2-stable_win64.exe',
	[string]$Project = 'E:\rts_demo'
)

$ErrorActionPreference = 'Stop'

$buildDir = Join-Path $Project 'build'
$releaseDir = Join-Path $Project 'release'
$exePath = Join-Path $buildDir 'RTSDemo.exe'
$pckPath = Join-Path $buildDir 'RTSDemo.pck'
$zipPath = Join-Path $releaseDir 'RTSDemo-win64.zip'
$notesPath = Join-Path $releaseDir 'HOW-TO-PLAY.txt'

if (-not (Test-Path $Godot)) {
	throw "Godot executable not found: $Godot"
}

New-Item -ItemType Directory -Force -Path $buildDir, $releaseDir | Out-Null

Write-Host "[1/3] Importing project..."
& $Godot --headless --path $Project --import 2>&1 | Out-Null

Write-Host "[2/3] Exporting Windows release..."
& $Godot --headless --path $Project --export-release 'Windows Desktop' $exePath 2>&1 |
	Select-String -Pattern 'ERROR|error' | ForEach-Object { Write-Warning $_ }
if (-not (Test-Path $exePath)) { throw "Export failed, no binary at $exePath" }

Write-Host "[3/3] Packaging archive..."
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$stream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
	foreach ($file in @(
			@{ Path = $exePath;  Name = 'RTSDemo.exe' },
			@{ Path = $pckPath;  Name = 'RTSDemo.pck' },
			@{ Path = $notesPath; Name = 'HOW-TO-PLAY.txt' }
		)) {
		if (-not (Test-Path $file.Path)) {
			throw "Missing file to package: $($file.Path)"
		}
		$entry = $archive.CreateEntry($file.Name, [System.IO.Compression.CompressionLevel]::Optimal)
		$source = [System.IO.File]::OpenRead($file.Path)
		$destination = $entry.Open()
		$source.CopyTo($destination)
		$destination.Dispose()
		$source.Dispose()
	}
}
finally {
	$archive.Dispose()
	$stream.Dispose()
}

$sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host ""
Write-Host "Packaged $zipPath ($sizeMb MB)"
if ($sizeMb -ge 100) {
	Write-Warning "Archive exceeds GitHub's 100 MB per-file limit for a git blob."
}
