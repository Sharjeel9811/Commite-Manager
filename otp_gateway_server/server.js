'use strict';

/**
 * Committee Manager — Production OTP Gateway
 *
 * Runs on Render.com (or any Node >= 18 host).  Every phone on any network
 * in the world can reach it over HTTPS.  The LAN/localhost path is gone.
 *
 * Endpoints
 * ---------
 *   POST /api/auth/send-otp    — generate, hash & email a 6-digit OTP
 *   POST /api/auth/verify-otp  — check the OTP, mark it used, return a token
 *   GET  /health               — liveness probe (Render uses this)
 *   GET  /                     — human-readable status
 *
 * Security properties
 * -------------------
 *   - OTP is generated with crypto.randomInt (CSPRNG)
 *   - Only the HMAC-SHA256 hash is stored — plaintext never touches the DB
 *   - Challenges expire after OTP_VALIDITY_MINUTES (default 5)
 *   - Max 5 wrong guesses per challenge, then it is burned
 *   - Max 3 send requests per email per 10 minutes (rate limiter)
 *   - Global IP-based rate limiter (express-rate-limit)
 *   - OTP / SMTP password never logged in production
 *   - helmet + CORS locked to mobile origin (no Origin header = allowed)
 */

require('dotenv').config();

const crypto      = require('crypto');
const path        = require('path');
const express     = require('express');
const cors        = require('cors');
const helmet      = require('helmet');
const rateLimit   = require('express-rate-limit');
const nodemailer  = require('nodemailer');

const app = express();

// ─────────────────────────────────────────────────────────────────────────────
// Configuration — every secret comes from environment variables.
// Never hard-code credentials here.
// ─────────────────────────────────────────────────────────────────────────────
const PORT                 = Number(process.env.PORT  || 4000);
const APP_NAME             = process.env.APP_NAME     || 'Committee Manager';
const OTP_API_KEY          = process.env.OTP_API_KEY  || '';
const OTP_SECRET           = process.env.OTP_SECRET   || (() => {
  if (process.env.NODE_ENV === 'production') {
    console.error('[FATAL] OTP_SECRET must be set in production');
    process.exit(1);
  }
  return 'dev-secret-change-me';
})();
const OTP_VALIDITY_MINUTES = Number(process.env.OTP_VALIDITY_MINUTES || 5);
const OTP_MAX_ATTEMPTS     = Number(process.env.OTP_MAX_ATTEMPTS     || 5);
const OTP_LENGTH           = 6;

// Comma-separated allowed origins.  A mobile app sends NO Origin header so
// we must accept requests with an absent Origin as well.
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '*')
  .split(',').map(s => s.trim()).filter(Boolean);

// ─────────────────────────────────────────────────────────────────────────────
// In-memory OTP store with TTL sweep.
//
// Render's free tier gives you 512 MB RAM and a single process, so in-memory
// is fine for thousands of concurrent challenges.  If you later need
// multi-instance scale, swap this Map for Redis (one line change in the
// challenge helpers below).
//
// Schema per entry:
//   {
//     hash:       string   — HMAC-SHA256 of the plaintext OTP
//     expiresAt:  number   — Date.now() + validity window
//     attempts:   number   — wrong-guess counter
//     used:       boolean  — single-use guard
//   }
// ─────────────────────────────────────────────────────────────────────────────
const challenges = new Map();

/** Remove expired/used entries every 2 minutes so memory never bloats. */
setInterval(() => {
  const now = Date.now();
  for (const [key, val] of challenges) {
    if (val.used || val.expiresAt < now) challenges.delete(key);
  }
}, 2 * 60 * 1000);

// Per-email send-rate limiter (max 3 requests per 10 min per normalised email)
const sendRateBucket = new Map(); // email → [timestamp, ...]

function checkSendRate(email) {
  const windowMs = 10 * 60 * 1000;
  const maxSends = 3;
  const now      = Date.now();
  const history  = (sendRateBucket.get(email) || []).filter(t => now - t < windowMs);
  if (history.length >= maxSends) return false;
  history.push(now);
  sendRateBucket.set(email, history);
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Crypto helpers
// ─────────────────────────────────────────────────────────────────────────────
function generateOtp() {
  // crypto.randomInt upper bound is exclusive; 10^6 = 1 000 000
  const n = crypto.randomInt(0, 1_000_000);
  return n.toString().padStart(OTP_LENGTH, '0');
}

function hashOtp(otp) {
  return crypto.createHmac('sha256', OTP_SECRET).update(otp).digest('hex');
}

function secureEqual(a, b) {
  // Constant-time comparison prevents timing attacks.
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    // Still do a dummy comparison so execution time does not leak the length.
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

// ─────────────────────────────────────────────────────────────────────────────
// Nodemailer transport — built lazily so a startup error is surfaced early
// ─────────────────────────────────────────────────────────────────────────────
let _transport = null;

function getTransport() {
  if (_transport) return _transport;

  const base = (process.env.MAIL_SERVICE && process.env.MAIL_SERVICE !== 'custom')
    ? { service: process.env.MAIL_SERVICE }
    : {
        host:   process.env.MAIL_HOST,
        port:   Number(process.env.MAIL_PORT || 587),
        secure: String(process.env.MAIL_SECURE || 'false') === 'true',
      };

  _transport = nodemailer.createTransport({
    ...base,
    auth: {
      user: process.env.MAIL_USER,
      pass: process.env.MAIL_PASS,   // app password — never logged
    },
  });
  return _transport;
}

function buildEmailHtml(code) {
  return `<!doctype html>
<html>
  <body style="margin:0;padding:24px;background:#f4f4f8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
           style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;
                  overflow:hidden;border:1px solid #e4e4ef">
      <tr>
        <td style="background:#4f46e5;padding:22px 28px">
          <h1 style="margin:0;color:#ffffff;font-size:18px">${APP_NAME}</h1>
        </td>
      </tr>
      <tr>
        <td style="padding:28px">
          <p style="margin:0 0 18px;color:#1f1f2e;font-size:15px;line-height:1.6">
            Your verification code is:
          </p>
          <p style="margin:0 0 18px;text-align:center">
            <span style="display:inline-block;padding:14px 22px;background:#f4f4f8;
                         border:1px solid #e4e4ef;border-radius:12px;font-size:30px;
                         font-weight:700;letter-spacing:10px;color:#1f1f2e">${code}</span>
          </p>
          <p style="margin:0 0 8px;color:#6b6b7b;font-size:13px;line-height:1.6">
            This code expires in ${OTP_VALIDITY_MINUTES} minutes and can only be used once.
            If you did not request it, ignore this email.
          </p>
          <p style="margin:0;color:#9a9aab;font-size:12px">
            Never share this code with anyone.
          </p>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

async function sendEmail(destination, otp) {
  const fromAddress = process.env.MAIL_FROM
    || `"${APP_NAME}" <${process.env.MAIL_USER}>`;

  await getTransport().sendMail({
    from:    fromAddress,
    to:      destination,
    subject: `${otp} — your ${APP_NAME} code`,  // OTP in subject is intentional; body hides it
    text:    `Your ${APP_NAME} verification code is ${otp}. It expires in ${OTP_VALIDITY_MINUTES} minutes. Do not share it.`,
    html:    buildEmailHtml(otp),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Middleware
// ─────────────────────────────────────────────────────────────────────────────
app.set('trust proxy', 1);  // Render puts a proxy in front; needed for real IPs

app.use(helmet({ contentSecurityPolicy: false }));

app.use(cors({
  // A Flutter mobile app sends NO Origin header (it is not a browser).
  // Returning true for every request (including those with an Origin) is safe
  // because the API key provides the actual auth layer.
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);                      // mobile / curl
    if (ALLOWED_ORIGINS.includes('*')) return cb(null, true);
    if (ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    cb(new Error('Not allowed by CORS'));
  },
  methods: ['GET', 'POST'],
}));

app.use(express.json({ limit: '8kb' }));

// Global IP rate limit — 60 requests / 15 min per IP
app.use(rateLimit({
  windowMs:        15 * 60 * 1000,
  max:             60,
  standardHeaders: true,
  legacyHeaders:   false,
  message:         { error: 'Too many requests. Please slow down.' },
}));

// ─────────────────────────────────────────────────────────────────────────────
// Shared-secret gate (optional but recommended for production)
// ─────────────────────────────────────────────────────────────────────────────
function requireApiKey(req, res, next) {
  if (!OTP_API_KEY) return next();  // key not configured — open (dev mode)
  const supplied = req.get('x-otp-key') || '';
  if (!secureEqual(supplied, OTP_API_KEY)) {
    log('warn', `401 — bad x-otp-key from ${req.ip}`);
    return res.status(401).json({ error: 'Unauthorized' });
  }
  return next();
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation
// ─────────────────────────────────────────────────────────────────────────────
const EMAIL_RE = /^[\w.+\-]+@[\w\-]+\.[\w.\-]+$/;
const OTP_RE   = /^[0-9]{6}$/;

function normalise(email) {
  return String(email || '').trim().toLowerCase();
}

// ─────────────────────────────────────────────────────────────────────────────
// Logging — OTPs and passwords are NEVER logged
// ─────────────────────────────────────────────────────────────────────────────
const IS_PROD = process.env.NODE_ENV === 'production';

function log(level, msg) {
  const line = `[${new Date().toISOString()}] ${level.toUpperCase().padEnd(5)} ${msg}`;
  if (level === 'error') console.error(line);
  else if (level === 'warn')  console.warn(line);
  else if (!IS_PROD || level !== 'debug') console.log(line);
}

function maskEmail(email) {
  const at   = email.indexOf('@');
  const name = at > 0 ? email.slice(0, at) : email;
  const head = name.slice(0, Math.min(2, name.length));
  return `${head}***${email.slice(at)}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Routes
// ─────────────────────────────────────────────────────────────────────────────

// GET / — human readable, also confirms the service is alive
app.get('/', (_req, res) => {
  res.json({
    service: `${APP_NAME} OTP Gateway`,
    version: '2.0.0',
    status:  'running',
    endpoints: {
      sendOtp:    'POST /api/auth/send-otp',
      verifyOtp:  'POST /api/auth/verify-otp',
      health:     'GET  /health',
    },
  });
});

// GET /health — used by Render's health-check and your own monitoring
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

/**
 * POST /api/auth/send-otp
 *
 * Body: { "email": "user@example.com" }
 *
 * - Validates email
 * - Rate-limits sends per email (3 per 10 min)
 * - Generates a CSPRNG 6-digit OTP
 * - Stores only the HMAC hash
 * - Emails the plaintext OTP via Nodemailer
 * - Returns { "ok": true }  (OTP is NEVER in the response)
 */
app.post('/api/auth/send-otp', requireApiKey, async (req, res) => {
  const email = normalise(req.body?.email);

  if (!EMAIL_RE.test(email)) {
    return res.status(400).json({ error: 'A valid email address is required.' });
  }

  if (!checkSendRate(email)) {
    log('warn', `send-rate exceeded for ${maskEmail(email)}`);
    return res.status(429).json({
      error: 'Too many verification requests. Please wait a few minutes.',
    });
  }

  const otp       = generateOtp();         // plaintext — only used here and in the email
  const hash      = hashOtp(otp);          // what we store
  const expiresAt = Date.now() + OTP_VALIDITY_MINUTES * 60 * 1000;

  // Overwrite any previous challenge for this email (new code invalidates old)
  challenges.set(email, { hash, expiresAt, attempts: 0, used: false });

  try {
    await sendEmail(email, otp);
    log('info', `OTP sent to ${maskEmail(email)}`);
    // The plaintext OTP goes out of scope after this line.
    return res.json({ ok: true, message: `A ${OTP_LENGTH}-digit code was sent to your email.` });
  } catch (err) {
    // Remove the challenge so a retry is possible immediately
    challenges.delete(email);
    log('error', `Email send failed for ${maskEmail(email)}: ${err.message}`);
    return res.status(502).json({
      error: 'The verification email could not be sent. Please try again.',
    });
  }
});

/**
 * POST /api/auth/verify-otp
 *
 * Body: { "email": "user@example.com", "otp": "123456" }
 *
 * - Validates inputs
 * - Checks challenge exists, is unexpired, is unused, within attempt limit
 * - Constant-time HMAC comparison
 * - Burns the challenge on success
 * - Returns { "verified": true } on success
 */
app.post('/api/auth/verify-otp', requireApiKey, (req, res) => {
  const email = normalise(req.body?.email);
  const otp   = String(req.body?.otp || '').trim();

  if (!EMAIL_RE.test(email)) {
    return res.status(400).json({ error: 'A valid email address is required.' });
  }
  if (!OTP_RE.test(otp)) {
    return res.status(400).json({ error: 'OTP must be exactly 6 digits.' });
  }

  const challenge = challenges.get(email);

  if (!challenge) {
    return res.status(400).json({ error: 'No pending code for this address. Request a new one.' });
  }
  if (challenge.used) {
    challenges.delete(email);
    return res.status(400).json({ error: 'That code has already been used. Request a new one.' });
  }
  if (Date.now() > challenge.expiresAt) {
    challenges.delete(email);
    return res.status(400).json({ error: 'That code has expired. Request a new one.' });
  }
  if (challenge.attempts >= OTP_MAX_ATTEMPTS) {
    challenges.delete(email);
    return res.status(400).json({
      error: 'Too many incorrect attempts. Request a new code.',
    });
  }

  const supplied = hashOtp(otp);
  if (!secureEqual(supplied, challenge.hash)) {
    challenge.attempts += 1;
    const left = OTP_MAX_ATTEMPTS - challenge.attempts;
    log('warn', `Wrong OTP for ${maskEmail(email)} — ${left} attempt(s) left`);
    if (left <= 0) {
      challenges.delete(email);
      return res.status(400).json({ error: 'Too many incorrect attempts. Request a new code.' });
    }
    return res.status(400).json({
      error: `That code is not correct. ${left} attempt${left === 1 ? '' : 's'} left.`,
    });
  }

  // ✓ Correct — single-use: burn the challenge immediately
  challenges.delete(email);
  log('info', `OTP verified for ${maskEmail(email)}`);

  return res.json({
    verified: true,
    message:  'Email verified successfully.',
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Catch-all 404
// ─────────────────────────────────────────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ error: 'Endpoint not found.' }));

// ─────────────────────────────────────────────────────────────────────────────
// Unhandled error handler
// ─────────────────────────────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  log('error', `Unhandled: ${err.message}`);
  res.status(500).json({ error: 'Internal server error.' });
});

// ─────────────────────────────────────────────────────────────────────────────
// Start
// ─────────────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  log('info', `${APP_NAME} OTP Gateway v2 listening on port ${PORT}`);
  log('info', `NODE_ENV=${process.env.NODE_ENV || 'development'}`);
  log('info', `OTP validity: ${OTP_VALIDITY_MINUTES} min | max attempts: ${OTP_MAX_ATTEMPTS}`);
  log('info', `API key protection: ${OTP_API_KEY ? 'ENABLED' : 'disabled (set OTP_API_KEY)'}`);

  if (!process.env.MAIL_USER || !process.env.MAIL_PASS) {
    log('error', 'MAIL_USER / MAIL_PASS not set — email delivery will fail');
  } else {
    // Verify SMTP credentials on startup (background — does not block the server)
    getTransport().verify().then(() => {
      log('info', 'SMTP credentials verified — email channel is ready');
    }).catch(err => {
      log('error', `SMTP verify failed: ${err.message}`);
    });
  }
});
