# Committee Manager — Production OTP Gateway
## Complete Deployment Guide: LAN → Cloud (Render.com)

---

## What Was Wrong With the Old Architecture

```
OLD (BROKEN FOR PRODUCTION):
Phone ──WiFi──▶ 192.168.x.x:4000 ──▶ Nodemailer ──▶ Gmail
                     ↑
              Your PC must be ON
              Phone must be on same WiFi
              Breaks on mobile data
              Breaks in another city

NEW (PRODUCTION-READY):
Any Phone ──Internet──▶ https://your-app.onrender.com ──▶ Nodemailer ──▶ Gmail
                               ↑
                    Render.com cloud server
                    Always ON (even when your PC is off)
                    Works from anywhere in the world
                    HTTPS enforced
```

---

## Why Render.com?

| Requirement | Render.com |
|---|---|
| Free tier | Yes — free Web Service tier |
| No credit card needed to start | Yes |
| HTTPS automatic | Yes — free TLS on every service |
| Permanent URL | Yes — `https://your-name.onrender.com` |
| Environment variables UI | Yes — no config files needed |
| Auto-deploy from GitHub | Yes — push to main = deploy |
| Node.js native support | Yes |
| Your PC can be OFF | Yes — runs 24/7 in their datacenter |
| Works from any network | Yes |

---

## What Changed in the Code

### Backend (`otp_gateway_server/server.js`)
| Before | After |
|---|---|
| `POST /otp` | `POST /api/auth/send-otp` |
| OTP stored as plaintext hash in memory | OTP stored as HMAC-SHA256 hash only |
| No attempt limiting | Max 5 wrong guesses burns the challenge |
| No per-email rate limit | Max 3 sends per email per 10 minutes |
| OTP logged to console in dev mode | OTP never logged in any mode |
| `HOST=0.0.0.0` (LAN binding) | Render injects PORT; no HOST config needed |

### Flutter (`lib/services/implementations/gateway_otp_sender.dart`)
| Before | After |
|---|---|
| `POST /otp` | `POST /api/auth/send-otp` |
| Response contained `delivered: true` | Response contains `ok: true` |
| Verify was done in-app | `POST /api/auth/verify-otp` (server-side) |

### Flutter (`lib/core/config/app_config.dart`)
No change to structure — still uses `--dart-define=OTP_GATEWAY_URL=...`

---

## Step-by-Step Deployment

---

### STEP 1 — Create a separate GitHub repository for the gateway

The gateway must be in its own repository (not inside the Flutter project).
Render.com deploys from a GitHub repo root.

```powershell
# On your PC — create a new folder OUTSIDE the Flutter project
mkdir C:\Users\YourName\committee-otp-gateway
cd C:\Users\YourName\committee-otp-gateway

# Copy the gateway files into it
Copy-Item "C:\Users\Sharjeel Adnan\Desktop\Flutter project\otp_gateway_server\server.js"    .
Copy-Item "C:\Users\Sharjeel Adnan\Desktop\Flutter project\otp_gateway_server\package.json" .
Copy-Item "C:\Users\Sharjeel Adnan\Desktop\Flutter project\otp_gateway_server\.env.example" .

# Create a .gitignore so secrets are never committed
@"
node_modules/
.env
*.log
"@ | Out-File -Encoding utf8 .gitignore

# Initialise git
git init
git add .
git commit -m "Initial production gateway"
```

Now push to GitHub:
1. Go to https://github.com/new
2. Name it `committee-otp-gateway` (private is fine)
3. Do NOT initialise with a README
4. Copy the two commands it shows and run them:

```powershell
git remote add origin https://github.com/YOUR_USERNAME/committee-otp-gateway.git
git branch -M main
git push -u origin main
```

---

### STEP 2 — Generate your secrets

Run these in PowerShell to generate strong random values:

```powershell
# OTP_SECRET — 64-char hex, used as the HMAC key
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# OTP_API_KEY — 48-char hex, sent in x-otp-key header by the Flutter app
node -e "console.log(require('crypto').randomBytes(24).toString('hex'))"
```

**Save both values somewhere safe** (e.g. a password manager).
You will paste them into Render's environment variables in the next step.

---

### STEP 3 — Deploy to Render.com

1. Go to https://render.com and sign up (free, no credit card)

2. Click **New +** → **Web Service**

3. Connect your GitHub account if asked

4. Select the `committee-otp-gateway` repository → click **Connect**

5. Fill in the service settings:

   | Field | Value |
   |---|---|
   | Name | `committee-manager-otp` (or anything you like) |
   | Region | Choose closest to your users (e.g. Singapore for Pakistan) |
   | Branch | `main` |
   | Runtime | **Node** |
   | Build Command | `npm install` |
   | Start Command | `node server.js` |
   | Instance Type | **Free** |

6. Click **Advanced** → **Add Environment Variable** and add all of these:

   | Key | Value |
   |---|---|
   | `NODE_ENV` | `production` |
   | `OTP_SECRET` | *(paste the 64-char hex from Step 2)* |
   | `OTP_API_KEY` | *(paste the 48-char hex from Step 2)* |
   | `OTP_VALIDITY_MINUTES` | `5` |
   | `OTP_MAX_ATTEMPTS` | `5` |
   | `MAIL_SERVICE` | `gmail` |
   | `MAIL_USER` | `sharjeeladnan93@gmail.com` |
   | `MAIL_PASS` | `nvywyxdvsxovnizz` *(your Gmail app password)* |
   | `MAIL_FROM` | `"Committee Manager <sharjeeladnan93@gmail.com>"` |
   | `APP_NAME` | `Committee Manager` |
   | `ALLOWED_ORIGINS` | `*` |

   > **Important:** `MAIL_PASS` is your Gmail **app password** (16 chars, no spaces).
   > If it stops working, generate a new one at:
   > myaccount.google.com → Security → 2-Step Verification → App passwords

7. Click **Create Web Service**

8. Render will build and deploy. Watch the log at the bottom.
   When you see:
   ```
   Committee Manager OTP Gateway v2 listening on port 10000
   SMTP credentials verified — email channel is ready
   ```
   — it is live.

9. **Copy your permanent URL** from the top of the page:
   ```
   https://committee-manager-otp.onrender.com
   ```
   This is your production gateway URL. It never changes.

---

### STEP 4 — Test the live backend from your browser

Open these URLs in any browser (your phone browser works too):

```
https://committee-manager-otp.onrender.com/
https://committee-manager-otp.onrender.com/health
```

You should see JSON like:
```json
{ "ok": true, "ts": "2026-10-03T08:40:00.000Z" }
```

Test the send-OTP endpoint from PowerShell:
```powershell
Invoke-RestMethod -Uri "https://committee-manager-otp.onrender.com/api/auth/send-otp" `
  -Method POST `
  -ContentType "application/json" `
  -Headers @{ "x-otp-key" = "YOUR_OTP_API_KEY" } `
  -Body '{"email":"yourtest@gmail.com"}'
```

You should receive `{ "ok": true }` AND get an email within 10 seconds.

> If you get 401: check the `x-otp-key` value matches `OTP_API_KEY` in Render.
> If you get 502: check SMTP logs in Render → your service → Logs tab.

---

### STEP 5 — Update Flutter to use the production URL

Open `gateway.env` in the Flutter project root:

```
C:\Users\Sharjeel Adnan\Desktop\Flutter project\gateway.env
```

Replace the placeholder URL with your real Render URL:

```
OTP_GATEWAY_URL=https://committee-manager-otp.onrender.com
OTP_GATEWAY_API_KEY=YOUR_OTP_API_KEY_FROM_STEP_2
```

That is the only change needed in the Flutter project.

---

### STEP 6 — Test on your phone (debug build)

Connect your phone via USB and run:

```powershell
cd "C:\Users\Sharjeel Adnan\Desktop\Flutter project"
.\install_on_phone.ps1
```

The script will:
- Read `gateway.env`
- Detect the public HTTPS URL
- Print `OTP transport: Gateway at https://... -- works from anywhere`
- Build and install the debug APK

Test the OTP flow:
1. Register with a real email
2. Tap "Send a new code"
3. **Turn off your PC's Wi-Fi** (use mobile data) — OTP should still arrive
4. Enter the code → dashboard opens

If OTP arrives with your PC's network OFF → production architecture confirmed.

---

### STEP 7 — Build the Play Store release (AAB)

```powershell
cd "C:\Users\Sharjeel Adnan\Desktop\Flutter project"
.\build_release.ps1
```

The script reads `gateway.env` and bakes the production URL into the binary.
The resulting file is at:
```
build\app\outputs\bundle\release\app-release.aab
```

Upload it to Google Play Console → Your app → Release → Production.

---

### STEP 8 — (Optional) Keep Supabase Auth as fallback

The codebase supports both transports.
If you want to use **Supabase Auth** instead of (or alongside) the gateway:
- Set `OTP_GATEWAY_URL=` (empty) in `gateway.env`
- Fill in `supabase.env` with your Supabase project credentials
- The build scripts automatically fall back to Supabase when no gateway URL is set

---

## Development vs Production Configuration

| Scenario | What to put in `gateway.env` | Works from |
|---|---|---|
| Emulator dev | `OTP_GATEWAY_URL=http://10.0.2.2:4000` | Emulator only |
| Real phone on same WiFi (dev) | `OTP_GATEWAY_URL=http://192.168.x.x:4000` | Same LAN only |
| **Production (Play Store)** | `OTP_GATEWAY_URL=https://your-app.onrender.com` | **Anywhere** |

The install script warns you if the URL is a LAN address so you can't accidentally ship a LAN URL to the Play Store.

---

## Keeping the Gateway Running After Free Tier Spin-Down

Render's free tier spins down after 15 minutes of inactivity.
The first OTP request after spin-down takes ~30 seconds (cold start).

**To prevent this:**

Option A — Upgrade to Render's $7/month "Starter" tier (always-on).

Option B — Add a free uptime monitor (UptimeRobot, BetterStack) that pings
`/health` every 10 minutes to keep it warm.

Setup UptimeRobot (free):
1. Go to https://uptimerobot.com → sign up free
2. Add monitor → HTTP(s) → URL: `https://your-app.onrender.com/health`
3. Check interval: 5 minutes
4. Done — your gateway will never cold-start for your users.

---

## Security Audit — Before vs After

| Security Property | Before (LAN) | After (Cloud) |
|---|---|---|
| OTP plaintext in logs | Yes (LOG_CODES flag) | Never |
| OTP in API response | No | No |
| OTP storage | HMAC hash in memory | HMAC hash in memory |
| Transport encryption | None (plain HTTP on LAN) | TLS 1.2/1.3 (Render cert) |
| Attempt limiting | None | 5 wrong guesses burns challenge |
| Send rate limiting | Server-side 30/10min global | 3 per email per 10 min |
| API key protection | Blank by default | Required in production |
| SMTP password location | .env on your PC | Render environment variables |
| OTP comparison | String equality | HMAC + constant-time |
| Works when PC is off | No | Yes |

---

## Final Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                  USER'S PHONE                           │
│                                                          │
│  Committee Manager APK                                   │
│  • OTP_GATEWAY_URL baked in at build time               │
│  • x-otp-key header (API key, not a secret user sees)   │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTPS (TLS 1.3)
                        │ POST /api/auth/send-otp
                        │ POST /api/auth/verify-otp
                        ▼
┌─────────────────────────────────────────────────────────┐
│           RENDER.COM CLOUD SERVER                       │
│   https://committee-manager-otp.onrender.com            │
│                                                          │
│  Node.js 18 + Express                                   │
│  ┌─────────────────────────────────────────────────┐    │
│  │  POST /api/auth/send-otp                        │    │
│  │    validate email                               │    │
│  │    rate-limit (3 sends / email / 10 min)        │    │
│  │    generate OTP  (crypto.randomInt CSPRNG)      │    │
│  │    store HMAC-SHA256(OTP, OTP_SECRET)           │    │
│  │    send email via Nodemailer                    │    │
│  │    return { ok: true }  ← OTP never here        │    │
│  └─────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────┐    │
│  │  POST /api/auth/verify-otp                      │    │
│  │    validate email + otp                         │    │
│  │    check expiry (5 min)                         │    │
│  │    check attempts (max 5)                       │    │
│  │    HMAC compare (constant-time)                 │    │
│  │    burn challenge (single-use)                  │    │
│  │    return { verified: true }                    │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  Environment variables (set in Render dashboard):       │
│    OTP_SECRET, OTP_API_KEY                              │
│    MAIL_USER, MAIL_PASS  ← never in the APK            │
└───────────────────────┬─────────────────────────────────┘
                        │ SMTP TLS (port 587)
                        ▼
┌─────────────────────────────────────────────────────────┐
│              GMAIL SMTP SERVERS                         │
│   smtp.gmail.com:587                                    │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              USER'S EMAIL INBOX                         │
│   "123456 — your Committee Manager code"                │
└─────────────────────────────────────────────────────────┘
```

---

## Production Readiness Checklist

- [x] OTP generated with `crypto.randomInt` (CSPRNG)
- [x] Only HMAC-SHA256 hash stored — plaintext never persisted
- [x] OTP expires after 5 minutes
- [x] Single-use — challenge deleted on first successful verify
- [x] Max 5 wrong attempts before challenge is burned
- [x] Max 3 sends per email per 10 minutes
- [x] Global IP rate limiter (60 req / 15 min per IP)
- [x] OTP never appears in any API response
- [x] OTP never logged in production
- [x] SMTP password in environment variable — not in source code
- [x] API key protection via `x-otp-key` header
- [x] HTTPS enforced (Render provides free TLS certificate)
- [x] `trust proxy 1` set (Render sits behind a reverse proxy)
- [x] `helmet` security headers enabled
- [x] CORS configured for mobile app
- [x] Backend works when your PC is completely OFF
- [x] Backend works on mobile data, other WiFi, other cities
- [x] No localhost / LAN IP in the Flutter production build
- [x] Secrets stored in Render environment variables dashboard
- [x] `gateway.env` listed in `.gitignore` — never committed
- [x] Build scripts reject LAN URLs in release builds
- [x] Existing Flutter UI screens unchanged
- [x] Development (local) and production (cloud) configs both supported
