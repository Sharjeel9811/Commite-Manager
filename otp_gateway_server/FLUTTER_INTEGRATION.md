# OTP email gateway

The app can deliver verification codes through **this server** instead of
Supabase Auth. You already have it: it is the same Nodemailer gateway that used
to back the app, now selectable at build time.

## What changes when you use it

| | Supabase Auth | This gateway |
|---|---|---|
| Who mints the code | Supabase servers | **The app** |
| Who emails it | Supabase via SMTP you configure | This server via Nodemailer |
| Where the code is checked | Supabase | **The app** |
| Mail credentials | In the Supabase dashboard | In this server's `.env` |
| Server you must run | No | **Yes, this one** |

Read that table before choosing. This gateway is a fine choice when the point is
keeping the mailbox off the device and off the repo. It is a **weaker** identity
check than Supabase, because the app generates and validates the code itself, so
anyone with the unlocked device in hand can read or force the pending code. If
that matters to you, do not set `OTP_GATEWAY_URL` and the app keeps using
Supabase.

## Running it

```powershell
cd otp_gateway_server
Copy-Item .env.example .env    # then fill it in
npm install
npm start
```

It listens on `http://0.0.0.0:4000` by default and logs whether the mail channel
is genuinely working — it probes SMTP with a real login, not just a non-empty
config check.

### Mail credentials

`MAIL_USER` / `MAIL_PASS` for a Google account must be an **app password**:
Google requires 2-Step Verification on the account, and the password is typed
with no spaces. `configure_email.ps1` walks through it.

To reach real users you must expose this over **HTTPS**. Put it behind a reverse
proxy (Caddy or nginx) with a real certificate, and set `ALLOWED_ORIGINS` instead
of `*`.

## Building the app against it

```powershell
flutter build appbundle --release `
  --dart-define=OTP_GATEWAY_URL=https://otp.your-domain.com `
  --dart-define=OTP_GATEWAY_API_KEY=<the value of OTP_API_KEY in .env>
```

Set `OTP_GATEWAY_URL` and the gateway transport is selected. Leave it unset and
the app uses Supabase Auth, so the two coexist.

For the Android emulator, `http://10.0.2.2:4000` is your machine. It is plain
HTTP, so use it for development only.

`OTP_GATEWAY_API_KEY` is sent as the `x-otp-key` header. It ships inside the APK
and is therefore extractable by anyone who downloads it. Its only job is to stop
a stranger from using your server to send mail to arbitrary addresses — it
grants no access to any data, because this server holds no committee data and no
session authority. Rotate it if you ever publish a build you regret.

## Contract

The app depends on exactly this. Changing it will break sign-in, and
`test/gateway_otp_sender_test.dart` pins the Dart side of it.

```
POST /otp
  header  x-otp-key: <OTP_API_KEY>     (only when OTP_API_KEY is set)
  body    { destination, channel: 'email', code, purpose }
  200     { "delivered": true, "channel": "email" }
  400     { "error": "..." }           bad destination or code
  401     { "error": "Unauthorized" }  missing or wrong key
  429     { "error": "..." }           too many requests
  503     { "error": "..." }           mail not configured on the server

GET /health
  200     { "ok": true, "channels": { "email": true|false } }
```

## Verifying a change

`flutter test test/gateway_otp_sender_test.dart` checks the Dart side against a
stub. To check the two sides actually agree, run the contract harness, which
boots this server against a blank `.env` (so it can never send a real email) and
exercises every response above:

```powershell
cd otp_gateway_server
node contract_check.js .
```

It refuses to run if the port is already taken, so it can never accidentally test
some other process, and it needs only Node built-ins — no new dependency.
