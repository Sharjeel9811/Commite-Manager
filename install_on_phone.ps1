#requires -Version 5
<#
.SYNOPSIS
  Builds Committee Manager and installs it on a USB-connected Android phone.

.DESCRIPTION
  Automatically selects the right OTP transport:
    - If gateway.env exists and contains a public HTTPS URL  -> uses that
    - Otherwise reads supabase.env and uses Supabase Auth

  Steps:
    1. Load credentials from gateway.env or supabase.env
    2. Check adb and Flutter are available
    3. Wait for a real phone over USB (up to 2 minutes)
    4. flutter build apk --debug with the right --dart-define flags
    5. Install on phone, handle Xiaomi/Samsung quirks
    6. Launch the app

  Run:  .\install_on_phone.ps1
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$SupabaseEnvFile = Join-Path $ProjectRoot 'supabase.env'
$GatewayEnvFile  = Join-Path $ProjectRoot 'gateway.env'
$PackageId       = 'pk.com.committeemanager.committee_manager'
$AppName         = 'Committee Manager'
$ApkPath         = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-debug.apk'

function Find-Tool([string]$Name, [string[]]$Candidates) {
    foreach ($c in $Candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $p = Get-Command $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.Source }
    return $null
}

$Adb     = Find-Tool 'adb' @(
    'C:\src\android-sdk\platform-tools\adb.exe',
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe"
)
$Flutter = Find-Tool 'flutter' @(
    'C:\src\flutter\bin\flutter.bat',
    'C:\src\flutter\bin\flutter'
)

function Write-Step([string]$n, [string]$label) {
    Write-Host ''
    $pad = '=' * [Math]::Max(0, 70 - $label.Length - $n.Length - 2)
    Write-Host "==== $n  $label $pad" -ForegroundColor Cyan
}
function Write-Ok([string]$m)   { Write-Host "  [ OK ]  $m" -ForegroundColor Green  }
function Write-Warn([string]$m) { Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Write-Info([string]$m) { Write-Host "  [INFO]  $m"                         }
function Write-Fail([string]$m) { Write-Host "  [FAIL]  $m" -ForegroundColor Red    }

# ============================================================================
#  STEP 1 -- Load credentials
# ============================================================================
Write-Step '1/5' 'Load OTP transport credentials'

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
    if ($GatewayUrl) {
        $UseGateway = $true
        Write-Ok "OTP transport: Gateway at $GatewayUrl"
        if ($GatewayUrl -match '(localhost|127\.0\.0\.1)') {
            Write-Warn 'Gateway URL is localhost -- only works on the emulator.'
        } elseif ($GatewayUrl -match '(192\.168\.|10\.\d+\.)') {
            Write-Warn 'Gateway URL is a LAN address -- phone must be on the same Wi-Fi.'
            Write-Warn 'For a production build, use your Render.com HTTPS URL in gateway.env.'
        } else {
            Write-Ok 'Gateway URL is a public address -- works from anywhere.'
        }
    }
}

if (-not $UseGateway) {
    if (-not (Test-Path -LiteralPath $SupabaseEnvFile)) {
        Write-Fail "Neither gateway.env nor supabase.env found."
        exit 1
    }
    foreach ($line in (Get-Content -LiteralPath $SupabaseEnvFile)) {
        $line = $line.Trim()
        if ($line -match '^SUPABASE_URL\s*=\s*(.+)$')      { $SupabaseUrl  = $Matches[1].Trim() }
        if ($line -match '^SUPABASE_ANON_KEY\s*=\s*(.+)$') { $SupabaseAnon = $Matches[1].Trim() }
    }
    if (-not $SupabaseUrl -or -not $SupabaseAnon) {
        Write-Fail 'SUPABASE_URL or SUPABASE_ANON_KEY is empty in supabase.env.'
        exit 1
    }
    Write-Ok "OTP transport: Supabase Auth at $SupabaseUrl"
}

# ============================================================================
#  STEP 2 -- Check tools
# ============================================================================
Write-Step '2/5' 'Check tools'

if (-not $Adb)     { Write-Fail 'adb not found. Install Android SDK Platform Tools.'; exit 1 }
Write-Ok "adb:     $Adb"
if (-not $Flutter) { Write-Fail 'Flutter SDK not found.'; exit 1 }
Write-Ok "flutter: $Flutter"

# ============================================================================
#  STEP 3 -- Wait for phone
# ============================================================================
Write-Step '3/5' 'Detect Android device over USB'

cmd /c "`"$Adb`" start-server >nul 2>&1"

$Serial   = $null
$Deadline = (Get-Date).AddMinutes(2)
$Dots     = 0

while (-not $Serial -and (Get-Date) -lt $Deadline) {
    $lines = & $Adb devices 2>&1
    foreach ($line in $lines) {
        if ($line -match '^(\S+)\s+device\s*$') {
            $candidate = $Matches[1]
            if ($candidate -notlike 'emulator-*') { $Serial = $candidate; break }
        }
    }
    if (-not $Serial) {
        if ($Dots -eq 0) { Write-Host '  Waiting for phone...' -NoNewline }
        Write-Host '.' -NoNewline
        $Dots++
        Start-Sleep -Seconds 3
    }
}
if ($Dots -gt 0) { Write-Host '' }

if (-not $Serial) {
    Write-Fail 'No phone detected after 2 minutes.'
    Write-Host '  1. Data cable (not charge-only).' -ForegroundColor Yellow
    Write-Host '  2. Developer Options -> USB debugging ON.' -ForegroundColor Yellow
    Write-Host '  3. Tap ALLOW on the phone popup.' -ForegroundColor Yellow
    exit 2
}
Write-Ok "Phone: $Serial"

# ============================================================================
#  STEP 4 -- Build debug APK
# ============================================================================
Write-Step '4/5' 'Build debug APK'

Write-Info 'First run ~1 min, subsequent runs ~20 s.'
Write-Host ''

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
    & $Flutter build apk --debug @defines
    if ($LASTEXITCODE -ne 0) { Write-Fail 'flutter build apk failed.'; exit 5 }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $ApkPath)) { Write-Fail 'APK not found after build.'; exit 6 }
$Mb = [Math]::Round((Get-Item -LiteralPath $ApkPath).Length / 1MB, 1)
Write-Ok "APK ready: $ApkPath  ($Mb MB)"

# ============================================================================
#  STEP 5 -- Install and launch
# ============================================================================
Write-Step '5/5' 'Install and launch'

# Xiaomi: give the USB-install flag a moment to propagate
cmd /c "`"$Adb`" -s `"$Serial`" shell settings put global install_allow_usb 1 2>nul"
$null = $LASTEXITCODE
Start-Sleep -Seconds 2

$MaxAttempts = 5
$Installed   = $false

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output   = & $Adb -s $Serial install -r $ApkPath 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $text = $output | Out-String

    if ($exitCode -eq 0 -and $text -notmatch 'INSTALL_FAILED') { $Installed = $true; break }

    if ($text -match 'INSTALL_FAILED_USER_RESTRICTED') {
        Write-Warn "Attempt $attempt/$MaxAttempts - phone blocked install."
        Write-Host '  On the phone: Developer options -> "Install via USB" -> ON.' -ForegroundColor Yellow
        Write-Host '  Press Enter when ready...' -ForegroundColor Cyan -NoNewline
        [Console]::ReadLine() | Out-Null
    } elseif ($text -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
        Write-Warn 'Old signing mismatch -- uninstalling old APK...'
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $Adb -s $Serial uninstall $PackageId 2>&1 | Out-Null
        $ErrorActionPreference = $prev
    } else {
        Write-Fail "Install failed: $($text.Trim())"; exit 7
    }
}

if (-not $Installed) { Write-Fail "Could not install after $MaxAttempts attempts."; exit 7 }
Write-Ok 'Installed.'

# Xiaomi may briefly drop USB after install -- wait for reconnect
$reconnect = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $reconnect) {
    $check = & $Adb devices 2>&1 | Out-String
    if ($check -match [regex]::Escape($Serial)) { break }
    Start-Sleep -Milliseconds 500
}

$stillUp = (& $Adb devices 2>&1 | Out-String) -match [regex]::Escape($Serial)
if ($stillUp) {
    & $Adb -s $Serial shell am start -n "$PackageId/.MainActivity" 2>&1 | Out-Null
    Write-Ok "Launched $AppName."
} else {
    Write-Warn 'Phone disconnected after install (normal on Xiaomi).'
    Write-Warn "Open $AppName from your app drawer."
}

# ============================================================================
#  Checklist
# ============================================================================
Write-Host ''
Write-Host ('=' * 74) -ForegroundColor Green
Write-Host "  $AppName -- test checklist" -ForegroundColor Green
Write-Host ('=' * 74) -ForegroundColor Green
Write-Host ''
Write-Host '  ---- OTP flow -------------------------------------------------------'
Write-Host '  1. Register with a real email address.'
Write-Host '  2. The 6-digit verification screen opens and the code is sent automatically.'
Write-Host '  3. Enter the 6-digit code -> dashboard opens.'
if ($UseGateway -and $GatewayUrl -notmatch '(192\.168\.|10\.\d+\.|localhost|127\.)') {
    Write-Host '  4. OTP sent via cloud gateway -- works on ANY network.' -ForegroundColor Green
} elseif ($UseGateway) {
    Write-Host '  4. OTP sent via LAN gateway -- phone must be on the same Wi-Fi.' -ForegroundColor Yellow
} else {
    Write-Host '  4. OTP sent via Supabase Auth -- works on ANY network.' -ForegroundColor Green
}
Write-Host ''
Write-Host '  ---- Members and security ------------------------------------------'
Write-Host '  5. Open a committee -> Members -> edit a person -> choose Organizer -> Save.'
Write-Host '  6. Settings -> Require PIN -> switch it on; the app locks immediately.'
Write-Host '  7. Unlock with the PIN, then background and reopen the app to test the lock.'
Write-Host ''
Write-Host '  ---- Language -------------------------------------------------------'
Write-Host '  8. Settings -> Language -> tap "Urdu" -> whole app switches to Urdu.'
Write-Host '  9. Tap "English" to switch back.  Choice persists across restarts.'
Write-Host ''
Write-Host '  ---- For a Play Store release build ---------------------------------'
Write-Host '  .\build_release.ps1' -ForegroundColor Cyan
Write-Host ''
