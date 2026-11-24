<# : Partie batch (ignoree par PowerShell)
@echo off
set "CC_DIR=%~dp0"
where pwsh >nul 2>nul && (set "CC_PS=pwsh") || (set "CC_PS=powershell")
%CC_PS% -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText('%~f0'))"
exit /b
#>

# ---------------- Installeur Chaos Cam (PowerShell) ----------------
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Say($msg, $icon = 'Information') {
    if ($env:CC_SILENT) { Write-Host $msg; return }
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Chaos Cam', 'OK', $icon)
}

$src = Join-Path $env:CC_DIR 'chaos_cam.lua'
if (-not (Test-Path -LiteralPath $src)) {
    Say "Je ne trouve pas chaos_cam.lua a cote de l'installeur.`nGarde les deux fichiers dans le meme dossier." 'Error'
    exit 1
}

$obsDir    = Join-Path $env:APPDATA 'obs-studio'
$scenesDir = Join-Path $obsDir 'basic\scenes'
$collections = @()
if (Test-Path -LiteralPath $scenesDir) {
    $collections = @(Get-ChildItem -LiteralPath $scenesDir -File | Where-Object { $_.Extension -eq '.json' })
}
if ($collections.Count -eq 0) {
    Say "OBS ne semble pas installe (ou n'a jamais ete lance).`nLance OBS une premiere fois, ferme-le, puis relance l'installeur." 'Error'
    exit 1
}

# OBS doit etre ferme, sinon il ecrase la config en quittant
while (Get-Process -Name obs64, obs32, obs -ErrorAction SilentlyContinue) {
    if ($env:CC_SILENT) { Write-Host 'OBS est ouvert, abandon.'; exit 1 }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "OBS est ouvert.`nFerme OBS puis clique sur OK (ou Annuler pour arreter).",
        'Chaos Cam', 'OKCancel', 'Warning')
    if ($r -ne 'OK') { exit 1 }
}

# Copie du script dans le dossier d'OBS
$destDir = Join-Path $obsDir 'chaos-cam'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir 'chaos_cam.lua'
Copy-Item -LiteralPath $src -Destination $dest -Force
$destJson = $dest -replace '\\', '/'

# Ajout du script dans chaque collection de scenes
$utf8 = New-Object System.Text.UTF8Encoding $false
$ok = 0
$failed = @()
foreach ($f in $collections) {
    try {
        $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
        if ($null -eq $j.modules) {
            $j | Add-Member -NotePropertyName modules -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $list = @()
        if ($null -ne $j.modules.'scripts-tool') { $list = @($j.modules.'scripts-tool') }

        $found = $false
        foreach ($s in $list) {
            if ($s.path -match 'chaos_cam\.lua$') {
                if ($found) { $s.path = '' } else { $s.path = $destJson; $found = $true }
            }
        }
        $list = @($list | Where-Object { $_.path -ne '' })
        if (-not $found) {
            $list += [pscustomobject]@{ path = $destJson; settings = [pscustomobject]@{} }
        }
        $j.modules | Add-Member -NotePropertyName 'scripts-tool' -NotePropertyValue $list -Force

        Copy-Item -LiteralPath $f.FullName -Destination ($f.FullName + '.avant-chaos-cam.bak') -Force
        [IO.File]::WriteAllText($f.FullName, ($j | ConvertTo-Json -Depth 100), $utf8)
        $ok++
    } catch {
        $failed += $f.BaseName
    }
}

if ($ok -eq 0) {
    Say "Impossible de modifier les collections de scenes.`nAjoute le script a la main : OBS > Outils > Scripts > + > $dest" 'Error'
    exit 1
}

$msg = "Chaos Cam est installe dans $ok collection(s) de scenes !`n`n" +
       "Ouvre OBS > Outils > Scripts > Chaos Cam pour choisir ta webcam et ta chaine Twitch."
if ($failed.Count -gt 0) { $msg += "`n`nNon modifiee(s) : " + ($failed -join ', ') }
Say $msg
