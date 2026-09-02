# Build RS_HandHud.pk3 -- allowlisted, forward-slash entries (see RS_VR_Unified/build.ps1
# for why: Compress-Archive writes backslashes, and a stray file in the tree would
# shadow a real lump).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$out  = Join-Path $root 'RS_HandHud.pk3'

$required = @('zscript.txt', 'MAPINFO.txt', 'CVARINFO.txt', 'MENUDEF.txt', 'ANIMDEFS.txt', 'MODELDEF.txt')
$dirs     = @('zscript', 'models')

$files = @()
foreach ($f in $required) {
    $p = Join-Path $root $f
    if (-not (Test-Path $p)) { throw "REQUIRED lump missing: $f" }
    $files += Get-Item $p
}
foreach ($d in $dirs) {
    $p = Join-Path $root $d
    if (Test-Path $p) { $files += Get-ChildItem $p -Recurse -File }
}

if (Test-Path $out) { Remove-Item $out -Force }
$fs  = [System.IO.File]::Open($out, 'Create')
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($f in $files) {
    $rel = ($f.FullName.Substring($root.Length + 1)) -replace '\\', '/'
    $e   = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
    $st  = $e.Open()
    $b   = [System.IO.File]::ReadAllBytes($f.FullName)
    $st.Write($b, 0, $b.Length)
    $st.Close()
}
$zip.Dispose()
$fs.Close()

$z = [System.IO.Compression.ZipFile]::OpenRead($out)
$n = $z.Entries.Count
$z.Dispose()
Write-Host "RS_HandHud.pk3 -- $n entries, $([math]::Round((Get-Item $out).Length / 1KB, 1)) KB"
