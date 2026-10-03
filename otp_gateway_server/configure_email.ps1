# ---------------------------------------------------------------------------
# Writes the .env file for the OTP gateway.
#
# The app password is read from the Windows clipboard, so it is never typed and
# never pasted into a chat window. Copy it once from the Google page, run this,
# done. Nothing is echoed to screen, nothing goes to shell history, and the only
# copy on disk is the .env itself.
#
# If the clipboard is empty or looks wrong, you are offered manual entry with
# the keystrokes hidden.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$serverDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $serverDir '.env'
$example = Join-Path $serverDir '.env.example'

if (-not (Test-Path $example)) {
  Write-Host "Cannot find .env.example in $serverDir" -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host '  Committee Manager - email setup' -ForegroundColor Cyan
Write-Host '  ---------------------------------' -ForegroundColor Cyan
Write-Host ''

# ----------------------------------------------------------------- email
$email = Read-Host '  Your Gmail address'
if ([string]::IsNullOrWhiteSpace($email) -or $email -notmatch '@') {
  Write-Host '  That does not look like an email address.' -ForegroundColor Red
  exit 1
}

# ------------------------------------------------------- app password
Write-Host ''
Write-Host '  Go to https://myaccount.google.com/apppasswords and copy the' -ForegroundColor DarkGray
Write-Host '  16-character password (click it, Ctrl+C), then press Enter here.' -ForegroundColor DarkGray
Write-Host ''
$null = Read-Host '  Press Enter once the password is on your clipboard'

$pass = ''
$clip = Get-Clipboard -Raw -ErrorAction SilentlyContinue
if ($null -ne $clip) {
  # Keep only the characters a Gmail app password can contain.
  $pass = ($clip -replace '[^A-Za-z0-9]', '')
}

$letterCount = $pass.Length
if ($letterCount -ne 16) {
  Write-Host ''
  Write-Host "  Clipboard has $letterCount letters, expected 16." -ForegroundColor Yellow
  $again = Read-Host '  Type it instead, hidden? (y/n)'
  if ($again -notmatch '^[Yy]') {
    Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor Yellow
    exit 1
  }
  $secure = Read-Host '  App password (hidden)' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $pass = ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)) -replace '[^A-Za-z0-9]', ''
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  if ($pass.Length -ne 16) {
    Write-Host "  Still $((($pass)).Length) letters, expected 16. Cancelled." -ForegroundColor Red
    $pass = ''
    exit 1
  }
}

# The 16 characters were copied as four groups of four; keep the spaces, because
# that is the format Google shows and some users expect to see it.
$pretty = "$($pass.Substring(0,4)) $($pass.Substring(4,4)) $($pass.Substring(8,4)) $($pass.Substring(12,4))"

# ------------------------------------------------------------ write .env
if (Test-Path $envFile) {
  $lines = Get-Content $envFile
} else {
  $lines = Get-Content $example
}

$out = foreach ($line in $lines) {
  if ($line -match '^MAIL_USER=') { "MAIL_USER=$email" }
  elseif ($line -match '^MAIL_PASS=') { "MAIL_PASS=$pretty" }
  elseif ($line -match '^MAIL_FROM=') { "MAIL_FROM=`"Committee Manager <$email>`"" }
  else { $line }
}

# MAIL_HOST is deliberately left blank: nodemailer fills it in for the gmail
# service, and setting it by hand is the most common cause of a hang on send.
$out | Set-Content -Path $envFile -Encoding UTF8

# Clear the local copies, then the clipboard, so the secret does not linger.
$pass = $null
$pretty = $null
$out = $null
Set-Clipboard -Value ''

Write-Host ''
Write-Host "  Saved to $envFile" -ForegroundColor Green
Write-Host "  MAIL_USER = $email" -ForegroundColor Green
Write-Host  '  MAIL_PASS = 16 characters, written (hidden)' -ForegroundColor Green
Write-Host ''
Write-Host '  Your clipboard has been cleared.' -ForegroundColor DarkGray
Write-Host ''
