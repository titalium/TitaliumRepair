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

# Compilation
Write-Host ''
Write-Step 'Compilation en cours...'
Write-Host ''

$ps2exeArgs = @{
    inputFile     = $Source
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
    exit 1
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
