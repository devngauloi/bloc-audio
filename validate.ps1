# BLOC audio catalog validator.
# Checks catalog.json structure + every referenced MP3 (format/integrity)
# BEFORE you push to GitHub/jsDelivr.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File .\validate.ps1
# Exit code 0 = OK to push, 1 = problems found.
#
# NOTE: pure ASCII on purpose - Windows PowerShell 5.1 reads .ps1 as ANSI, so a
# non-ASCII byte can break parsing.

[CmdletBinding()]
param(
    [string]$CatalogPath = "catalog.json"
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$expectedMoods = @("lofi", "ambient", "rain", "instrumental")
$errors   = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$referenced = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

function Add-Err($m)  { $errors.Add($m) }
function Add-Warn($m) { $warnings.Add($m) }

# --- 1. Tooling ---
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: ffprobe not found on PATH (install ffmpeg)." -ForegroundColor Red
    exit 1
}

# --- 2. Catalog exists + valid JSON ---
if (-not (Test-Path $CatalogPath)) {
    Write-Host "ERROR: $CatalogPath not found." -ForegroundColor Red
    exit 1
}
try {
    $catalog = Get-Content -Raw -Encoding UTF8 $CatalogPath | ConvertFrom-Json
} catch {
    Write-Host "ERROR: $CatalogPath is not valid JSON: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- 3. Mood presence ---
foreach ($mood in $expectedMoods) {
    if ($catalog.PSObject.Properties.Name -notcontains $mood) {
        Add-Err "Missing mood '$mood' in catalog."
    }
}
foreach ($prop in $catalog.PSObject.Properties) {
    if ($prop.Name -eq "_comment") { continue }
    if ($expectedMoods -notcontains $prop.Name) {
        Add-Warn "Unknown mood key '$($prop.Name)' (app uses only: $($expectedMoods -join ', '))."
    }
}

# --- 4. Per-track validation ---
foreach ($mood in $expectedMoods) {
    $tracks = $catalog.$mood
    if ($null -eq $tracks) { continue }
    if (@($tracks).Count -lt 1) {
        Add-Err "Mood '$mood' has no tracks (need at least 1)."
        continue
    }
    $i = 0
    foreach ($t in @($tracks)) {
        $label = "$mood[$i]"; $i++

        if ([string]::IsNullOrWhiteSpace($t.title)) { Add-Err "${label}: empty 'title'." }

        $url = $t.url
        if ([string]::IsNullOrWhiteSpace($url)) { Add-Err "${label}: empty 'url'."; continue }
        if ($url -notmatch '^https://cdn\.jsdelivr\.net/gh/.+@.+/.+\.mp3$') {
            Add-Warn "${label}: url is not a jsDelivr .mp3 URL: $url"
        }

        # Derive the local path = everything after '@<ref>/'.
        if ($url -match '@[^/]+/(.+)$') { $rel = $Matches[1] }
        else { Add-Err "${label}: cannot derive local path from url: $url"; continue }

        if ($rel -cmatch '[^a-z0-9._/-]') {
            Add-Warn "${label}: path '$rel' has spaces/uppercase/special chars - prefer lowercase a-z0-9._-"
        }

        $local = Join-Path $root $rel.Replace('/', '\')
        if (-not (Test-Path $local)) { Add-Err "${label}: local file missing: $rel"; continue }
        [void]$referenced.Add((Resolve-Path $local).Path)

        $sizeMB = [math]::Round((Get-Item $local).Length / 1MB, 2)
        if ($sizeMB -gt 50)      { Add-Err  "${label}: $rel is ${sizeMB}MB (>50MB jsDelivr limit)." }
        elseif ($sizeMB -gt 20)  { Add-Warn "${label}: $rel is ${sizeMB}MB (large; keep loops compact)." }

        $probe = & ffprobe -v quiet -print_format json -show_format -show_streams $local 2>$null | ConvertFrom-Json
        if ($null -eq $probe) { Add-Err "${label}: ffprobe could not read $rel (corrupt?)."; continue }

        $a = $probe.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1
        if ($null -eq $a) { Add-Err "${label}: $rel has no audio stream."; continue }
        if ($a.codec_name -ne "mp3") { Add-Err "${label}: $rel codec is '$($a.codec_name)', expected mp3." }

        $dur = [double]$probe.format.duration
        if ($dur -le 0) { Add-Err "${label}: $rel has zero/unknown duration." }

        $sr = [int]$a.sample_rate
        if ($sr -ne 44100 -and $sr -ne 48000) { Add-Warn "${label}: $rel sample rate ${sr}Hz (prefer 44100/48000)." }

        if ($probe.format.bit_rate) {
            $kbps = [int]([int]$probe.format.bit_rate / 1000)
            if ($kbps -lt 96)       { Add-Warn "${label}: $rel bitrate ${kbps}k (low; prefer 128-192k)." }
            elseif ($kbps -gt 256)  { Add-Warn "${label}: $rel bitrate ${kbps}k (high; 128-192k is plenty)." }
        }
    }
}

# --- 5. Orphan check (mp3 in repo but not in catalog; skips _src/) ---
Get-ChildItem -Recurse -Filter *.mp3 -File |
    Where-Object { $_.FullName -notmatch '\\_src\\' } |
    ForEach-Object {
        if (-not $referenced.Contains((Resolve-Path $_.FullName).Path)) {
            Add-Warn "Orphan file not in catalog: $($_.FullName.Substring($root.Length).TrimStart('\','/'))"
        }
    }

# --- 6. Report ---
Write-Host ""
if ($warnings.Count -gt 0) {
    Write-Host "WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "ERRORS ($($errors.Count)):" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "FAIL - fix the errors above before pushing." -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "PASS - catalog + all MP3s valid. OK to push." -ForegroundColor Green
exit 0
