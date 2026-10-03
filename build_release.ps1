#requires -Version 5
<#
.SYNOPSIS
  Builds the Committee Manager release App Bundle (AAB) for Google Play.

.DESCRIPTION
  Reads credentials from supabase.env AND gateway.env, then runs
  flutter build appbundle --release with the right --dart-define flags.

  The resulting .aab is in:
    build\app\outputs\bundle\release\app-release.aab

  Upload that file to the Google Play Console.

.NOTES
  Run:  .\build_release.ps1
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$SupabaseEnvFile = Join-Path $ProjectRoot 'supabase.env'
$GatewayEnvFile  = Join-Path $ProjectRoot 'gateway.env'
$Flutter         = 'C:\src\flutter\bin\flutter.bat'

function Write-Step([string]$Label) {
    Write-Host ''
    Write-Host ('==== ' + $Label + ' ' + ('=' * [Math]::Max(0, 70 - $Label.Length))) -ForegroundColor Cyan
}
function Write-Ok([string]$Message)   { Write-Host ('  [ OK ]  ' + $Message) -ForegroundColor Green }
function Write-Info([string]$Message) { Write-Host ('  [INFO]  ' + $Message) }
function Write-Fail([string]$Message) { Write-Host ('  [FAIL]  ' + $Message) -ForegroundColor Red; exit 1 }

# ---- 1. Determine which OTP transport to use --------------------------------
Write-Step '1/3  Detect OTP transport'

$UseGateway   = $false
$GatewayUrl   = ''
$GatewayKey   = ''
$SupabaseUrl  = ''
$SupabaseAnon = ''

if (Test-Path -LiteralPath $GatewayEnvFile) {
    foreach ($line in (Get-Content -LiteralPath $GatewayEnvFile)) {
        $line = $line.Trim()
        if ($line -match '^OTP_GATEWAY_URL\s*=\s*(.+)$')     { $GatewayUrl = $Matches[1].Trim() }
        if ($line -match '^OTP_GATEWAY_API_KEY\s*=\s*(.+)$') { $GatewayKey = $Matches[1].Trim() }
    }
    if ($GatewayUrl -and $GatewayUrl -notmatch '(localhost|127\.0\.0\.1|192\.168\.|10\.)') {
        $UseGateway = $true
        Write-Ok "OTP transport: Self-hosted gateway at $GatewayUrl"
    } elseif ($GatewayUrl) {
        Write-Fail "gateway.env contains a LOCAL address ($GatewayUrl). Set a public HTTPS URL for release builds."
    }
}

if (-not $UseGateway) {
    if (-not (Test-Path -LiteralPath $SupabaseEnvFile)) {
        Write-Fail "Neither gateway.env nor supabase.env found. At least one OTP transport must be configured."
    }
    foreach ($line in (Get-Content -LiteralPath $SupabaseEnvFile)) {
        $line = $line.Trim()
        if ($line -match '^SUPABASE_URL\s*=\s*(.+)$')      { $SupabaseUrl  = $Matches[1].Trim() }
        if ($line -match '^SUPABASE_ANON_KEY\s*=\s*(.+)$') { $SupabaseAnon = $Matches[1].Trim() }
    }
    if (-not $SupabaseUrl -or -not $SupabaseAnon) {
        Write-Fail "SUPABASE_URL or SUPABASE_ANON_KEY is empty in supabase.env."
    }
    Write-Ok "OTP transport: Supabase Auth at $SupabaseUrl"
}

# ---- 2. Build ---------------------------------------------------------------
Write-Step '2/3  Build release App Bundle'

$defines = @()
if ($UseGateway) {
    $defines += "--dart-define=OTP_GATEWAY_URL=$GatewayUrl"
    if ($GatewayKey) { $defines += "--dart-define=OTP_GATEWAY_API_KEY=$GatewayKey" }
} else {
    $defines += "--dart-define=SUPABASE_URL=$SupabaseUrl"
    $defines += "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnon"
}

Push-Location $ProjectRoot
try {
    & $Flutter build appbundle --release @defines
    if ($LASTEXITCODE -ne 0) { Write-Fail 'flutter build appbundle failed. Read the output above.' }
} finally {
    Pop-Location
}

# ---- 3. Report --------------------------------------------------------------
Write-Step '3/3  Done'

$Aab = Join-Path $ProjectRoot 'build\app\outputs\bundle\release\app-release.aab'
if (Test-Path -LiteralPath $Aab) {
    $Mb = [Math]::Round((Get-Item -LiteralPath $Aab).Length / 1MB, 1)
    Write-Ok "App Bundle: $Aab  ($Mb MB)"
    Write-Host ''
    Write-Host '  Upload to Play Console:' -ForegroundColor White
    Write-Host '    Play Console -> Your app -> Release -> Production -> Create new release' -ForegroundColor White
    Write-Host '    -> Upload .aab above.' -ForegroundColor White
} else {
    Write-Fail 'App Bundle not found at expected path.'
}
