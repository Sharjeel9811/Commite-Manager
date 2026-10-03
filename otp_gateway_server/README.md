# OTP gateway

A tiny Node service that actually delivers the verification codes for the
Committee Manager app, by email.

## Why this is a separate program

The app cannot send an email by itself. That needs a provider account, and any
credential compiled into an APK can be lifted out of it by anyone who
downloads the app. So the app posts a code to this service, and the provider
password stays on your machine.

The app has no offline fallback: a code the device can read by itself proves
nothing about who owns the address that was registered.

## Setup

```bash
cd otp_gateway_server
npm install
copy .env.example .env      # Windows
# cp .env.example .env      # macOS / Linux
```

Then open `.env` and fill in at least the email section. You need any SMTP
account; nothing project-specific is required.

### Gmail

1. Turn on 2-Step Verification for the account.
2. Create an **App password** at https://myaccount.google.com/apppasswords.
3. In `.env`:

```
MAIL_SERVICE=gmail
MAIL_USER=your.address@gmail.com
MAIL_PASS=the-16-character-app-password
MAIL_FROM="Committee Manager <your.address@gmail.com>"
```

### Outlook / Hotmail

```
MAIL_SERVICE=hotmail
MAIL_USER=your.address@outlook.com
MAIL_PASS=your-password
```

### Any other SMTP server

Leave `MAIL_SERVICE=custom` and set `MAIL_HOST`, `MAIL_PORT`, `MAIL_SECURE`,
`MAIL_USER` and `MAIL_PASS`. Port 587 normally wants `MAIL_SECURE=false`
(STARTTLS); port 465 normally wants `MAIL_SECURE=true` (implicit TLS).

## Running it

```bash
npm start          # or: npm run dev   (restarts on save)
```

Check what is working:

```bash
curl http://localhost:4000/health
# {"ok":true,"channels":{"email":true}}
```

`email: true` means SMTP is configured and a login has succeeded.

## Pointing the app at it

The address the phone uses must be one the phone can reach.

| Where the app runs | URL to use |
| --- | --- |
| Android emulator | `http://10.0.2.2:4000/otp` (already the default) |
| Real phone, same Wi-Fi | `http://<your computer's LAN IP>:4000/otp` |
| Production | `https://your-host/otp` |

Find your computer's LAN IP:

```powershell
ipconfig
# IPv4 Address . . . : 192.168.0.2
```

Two ways to set it:

- **In the app**: Settings → Verification codes → Verification gateway.
- **At build time** (better for distribution):

```bash
flutter build apk --release --dart-define=OTP_GATEWAY_URL=http://192.168.0.2:4000/otp
```

If the app is built for a real phone on your Wi-Fi and it still cannot connect,
add your LAN IP to `android/app/src/main/res/xml/network_security_config.xml`.
Android blocks plain `http://` by default, and that file is the only place a
specific host may be allowed through.

## Shared secret (optional)

Set `OTP_API_KEY` in `.env` and pass the same value at build time:

```bash
flutter build apk --release --dart-define=OTP_API_KEY=some-long-random-string
```

The app then sends it in the `x-otp-key` header on every request.

Note that a value compiled into an APK is not truly secret. The real protection
is that the SMTP password never reaches the app at all.

## The API

### `POST /otp`

```json
{
  "destination": "ada@example.com",
  "channel": "email",
  "code": "538190",
  "purpose": "Account verification"
}
```

- `channel` is always `email`. An older client sending `"sms"` gets `400` with a
  message explaining that SMS delivery was removed.
- `destination` must be a valid email address.
- `code` must be 4–10 digits.

Responses:

| Status | Meaning |
| --- | --- |
| `200` | The provider accepted the message |
| `400` | The request was malformed |
| `401` | `x-otp-key` missing or wrong |
| `429` | Too many requests (30 per 10 minutes per IP) |
| `503` | Email is not configured, or the provider refused |

The app treats a `5xx` as "try again later" and shows the gateway's `error`
field for `503`, so a misconfigured server tells you exactly what to fix.

### `GET /health`

Reports whether email is usable. Safe to poll.

## Troubleshooting

**App says it cannot reach the gateway**
- Is the server running? `curl http://localhost:4000/health`
- Emulator: use `10.0.2.2`, never `localhost` — inside the emulator `localhost`
  is the emulated phone itself.
- Real phone: use the computer's LAN IP, and make sure both are on the same
  Wi-Fi. Some routers block device-to-device traffic (AP isolation).
- Windows Firewall may be blocking inbound connections to Node.

**`535 Authentication failed` in the server log**
- Gmail and Google Workspace require an app password, not your account password.
- The address in `MAIL_FROM` must be one the SMTP account is allowed to send as.

**The code is rejected even though the email arrived**
- Codes expire after 5 minutes, allow 5 attempts, and are single use. Requesting
  a new code invalidates the previous one.
