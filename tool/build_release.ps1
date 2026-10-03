#requires -Version 5
<##
.SYNOPSIS
  Builds the signed production Android App Bundle.

.DESCRIPTION
  Reads Supabase's public build-time values from supabase.env and uses the
  private signing material from android/key.properties. Neither file is
  committed, and their values are never printed.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvFile = Join-Path $ProjectRoot 'supabase.env'
$SigningFile = Join-Path $ProjectRoot 'android\key.properties'

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing supabase.env. Create it from the required SUPABASE_URL and SUPABASE_ANON_KEY values."
}
if (-not (Test-Path -LiteralPath $SigningFile)) {
    throw 'Missing android/key.properties. Create the upload keystore and fill the signing properties first.'
}

$supabaseUrl = $null
$supabaseAnonKey = $null
foreach ($line in Get-Content -LiteralPath $EnvFile) {
    if ($line -match '^\s*SUPABASE_URL\s*=\s*(.+?)\s*$') {
        $supabaseUrl = $Matches[1]
    } elseif ($line -match '^\s*SUPABASE_ANON_KEY\s*=\s*(.+?)\s*$') {
        $supabaseAnonKey = $Matches[1]
    }
}

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    throw 'supabase.env must contain non-empty SUPABASE_URL and SUPABASE_ANON_KEY values.'
}
if ($supabaseUrl -notmatch '^https://[^/]+\.supabase\.co/?$') {
    throw 'SUPABASE_URL must be an HTTPS Supabase project URL.'
}

Push-Location $ProjectRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    flutter build appbundle --release `
        "--dart-define=SUPABASE_URL=$supabaseUrl" `
        "--dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey"
    if ($LASTEXITCODE -ne 0) { throw 'Release App Bundle build failed.' }
} finally {
    Pop-Location
}

Write-Host 'Production App Bundle built successfully.' -ForegroundColor Green
Write-Host 'Output: build\app\outputs\bundle\release\app-release.aab'