# =============================================================================
#   TITALIUM REPAIR TOOL - Builder
#   Compile TitaliumRepair.ps1 en TitaliumRepair.exe portable via ps2exe.
#   Auteur : Titalium
# =============================================================================

[CmdletBinding()]
param(
    [string]$Source = (Join-Path $PSScriptRoot 'TitaliumRepair.ps1'),
    [string]$Output = (Join-Path $PSScriptRoot 'TitaliumRepair.exe'),
    [string]$Version = '1.0.0.0',
    [switch]$NoIcon
)

function Write-Step {
    param([string]$Message, [string]$Level = 'INFO')
    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║         TITALIUM REPAIR TOOL — Build portable .exe              ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Verif source
if (-not (Test-Path $Source)) {
    Write-Step "Fichier source introuvable : $Source" 'ERROR'
    exit 1
}
Write-Step "Source : $Source"
Write-Step "Output : $Output"
Write-Host ''

# Installer ps2exe si absent
Write-Step 'Verification du module ps2exe...'
$ps2exe = Get-Module -ListAvailable -Name ps2exe | Sort-Object Version -Descending | Select-Object -First 1
if (-not $ps2exe) {
    Write-Step 'ps2exe non trouve. Installation depuis PSGallery...' 'WARN'
    try {
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
            Register-PSRepository -Default -ErrorAction Stop
        }
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Step 'ps2exe installe.' 'OK'
    } catch {
        Write-Step "Echec d'installation : $($_.Exception.Message)" 'ERROR'
        Write-Step 'Tentative manuelle :' 'WARN'
        Write-Step '  Install-Module ps2exe -Scope CurrentUser -Force' 'WARN'
        exit 1
    }
} else {
    Write-Step "ps2exe v$($ps2exe.Version) detecte." 'OK'
}

Import-Module ps2exe -Force -ErrorAction Stop

# Injection du logo (logo.png en base64) dans une copie temporaire du .ps1.
# Le logo n'est pas committé dans le repo (gitignored) : il est embarqué uniquement
# dans le .exe final via cette injection au moment de la compilation.
$logoPath = Join-Path $PSScriptRoot 'logo.png'
$buildSource = $Source
if (Test-Path $logoPath) {
    Write-Step "Logo trouve : $logoPath — injection en base64..." 'OK'
    $logoBytes = [System.IO.File]::ReadAllBytes($logoPath)
    $logoB64 = [Convert]::ToBase64String($logoBytes)
    Write-Step ("  Taille logo : {0:N0} octets / base64 : {1:N0} car." -f $logoBytes.Length, $logoB64.Length)
    $srcContent = [System.IO.File]::ReadAllText($Source, [System.Text.UTF8Encoding]::new($true))
    if ($srcContent.Contains('@@LOGO_PNG_BASE64@@')) {
        $srcContent = $srcContent.Replace('@@LOGO_PNG_BASE64@@', $logoB64)
        $tempPs1 = Join-Path $env:TEMP "TitaliumRepairBuild_$([Guid]::NewGuid().ToString('N')).ps1"
        [System.IO.File]::WriteAllText($tempPs1, $srcContent, [System.Text.UTF8Encoding]::new($true))
        $buildSource = $tempPs1
        Write-Step "  Source temporaire avec logo injecte : $tempPs1" 'OK'
    } else {
        Write-Step "  Placeholder @@LOGO_PNG_BASE64@@ introuvable dans le .ps1 — logo non injecte." 'WARN'
    }
} else {
    Write-Step 'Aucun logo.png — fallback "T" stylise.' 'WARN'
}

# Compilation
Write-Host ''
Write-Step 'Compilation en cours...'
Write-Host ''

$ps2exeArgs = @{
    inputFile     = $buildSource
    outputFile    = $Output
    noConsole     = $true
    STA           = $true
    requireAdmin  = $true
    title         = 'Titalium Repair Tool'
    description   = 'Outil de reparation et optimisation Windows'
    company       = 'Titalium'
    product       = 'Titalium Repair Tool'
    copyright     = "(c) $(Get-Date -Format yyyy) Titalium"
    version       = $Version
    DPIAware      = $true
}

# Icone optionnelle
$iconPath = Join-Path $PSScriptRoot 'TitaliumRepair.ico'
if ((Test-Path $iconPath) -and (-not $NoIcon)) {
    Write-Step "Icone trouvee : $iconPath" 'OK'
    $ps2exeArgs['iconFile'] = $iconPath
} else {
    Write-Step 'Aucune icone (TitaliumRepair.ico absent).' 'WARN'
}

try {
    Invoke-ps2exe @ps2exeArgs
} catch {
    Write-Step "Erreur de compilation : $($_.Exception.Message)" 'ERROR'
    if ($buildSource -ne $Source) { try { Remove-Item -LiteralPath $buildSource -Force -EA SilentlyContinue } catch {} }
    exit 1
}

# Cleanup de la copie temporaire avec logo injecté (ne reste pas sur disque)
if ($buildSource -ne $Source) {
    try { Remove-Item -LiteralPath $buildSource -Force -EA SilentlyContinue } catch {}
}

if (Test-Path $Output) {
    $info = Get-Item $Output
    $sizeMB = '{0:N2}' -f ($info.Length / 1MB)
    Write-Host ''
    Write-Step '═══════════════════════════════════════════════════════════════' 'OK'
    Write-Step "BUILD REUSSI" 'OK'
    Write-Step '═══════════════════════════════════════════════════════════════' 'OK'
    Write-Step "Fichier  : $Output"
    Write-Step "Taille   : $sizeMB Mo"
    Write-Step "Version  : $Version"
    Write-Host ''
    Write-Step "Le .exe est portable : copie-le sur n'importe quel poste Windows 10/11."
    Write-Step "L'UAC se declenche automatiquement au lancement (manifest requireAdmin)."
    Write-Host ''
} else {
    Write-Step "Le fichier de sortie n'a pas ete cree." 'ERROR'
    exit 1
}
