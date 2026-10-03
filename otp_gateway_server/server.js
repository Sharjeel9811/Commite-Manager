'use strict';

/**
 * Committee Manager — Production OTP Gateway v3
 *
 * Storage: Upstash Redis (free, serverless, works on Vercel stateless functions)
 * Every OTP challenge is stored in Redis with a TTL so it auto-expires.
 * No in-memory Map — works correctly across all Vercel function instances.
 *
 * Endpoints
 * ---------
 *   POST /api/auth/send-otp    — generate, hash & email a 6-digit OTP
 *   POST /api/auth/verify-otp  — check the OTP, mark it used, return verified
 *   GET  /health               — liveness probe
 *   GET  /                     — human-readable status
 */

require('dotenv').config();

const crypto    = require('crypto');
const express   = require('express');
const cors      = require('cors');
const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');
const nodemailer = require('nodemailer');
const { Redis } = require('@upstash/redis');

const app = express();

// ─────────────────────────────────────────────────────────────── Config
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
const OTP_VALIDITY_SECONDS = Number(process.env.OTP_VALIDITY_MINUTES || 5) * 60;
const OTP_MAX_ATTEMPTS     = Number(process.env.OTP_MAX_ATTEMPTS || 5);
const SEND_RATE_WINDOW_SEC = 10 * 60;  // 10 minutes
const SEND_RATE_MAX        = 3;        // max sends per email per window

const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '*')
  .split(',').map(s => s.trim()).filter(Boolean);

// ─────────────────────────────────────────────────────── Upstash Redis client
// Reads UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN from env.
// These are set automatically if you connect Upstash via the Vercel integration,
// or manually if you paste them from the Upstash dashboard.
const redis = new Redis({
  url:   process.env.UPSTASH_REDIS_REST_URL,
  token: process.env.UPSTASH_REDIS_REST_TOKEN,
});

// Redis key helpers — all keys are namespaced so they never clash
const challengeKey = email => `otp:challenge:${email}`;
const sendRateKey  = email => `otp:sendrate:${email}`;

// ─────────────────────────────────────────────────────────────── Crypto
function generateOtp() {
  const n = crypto.randomInt(0, 1_000_000);
  return n.toString().padStart(6, '0');
}

function hashOtp(otp) {
  return crypto.createHmac('sha256', OTP_SECRET).update(otp).digest('hex');
}

function secureEqual(a, b) {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

// ─────────────────────────────────────────────────────────── Nodemailer
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
    auth: { user: process.env.MAIL_USER, pass: process.env.MAIL_PASS },
  });
  return _transport;
}

function buildEmailHtml(code) {
  return `<!doctype html>
<html>
  <body style="margin:0;padding:24px;background:#f4f4f8;
               font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
           style="max-width:520px;margin:0 auto;background:#fff;
                  border-radius:16px;overflow:hidden;border:1px solid #e4e4ef">
      <tr>
        <td style="background:#4f46e5;padding:22px 28px">
          <h1 style="margin:0;color:#fff;font-size:18px">${APP_NAME}</h1>
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
            This code expires in ${OTP_VALIDITY_SECONDS / 60} minutes and can only be used once.
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
  const from = process.env.MAIL_FROM || `"${APP_NAME}" <${process.env.MAIL_USER}>`;
  await getTransport().sendMail({
    from,
    to:      destination,
    subject: `${otp} — your ${APP_NAME} verification code`,
    text:    `Your ${APP_NAME} code is ${otp}. It expires in ${OTP_VALIDITY_SECONDS / 60} minutes. Do not share it.`,
    html:    buildEmailHtml(otp),
  });
}

// ─────────────────────────────────────────────────────────────── Logging
const IS_PROD = process.env.NODE_ENV === 'production';

function log(level, msg) {
  const line = `[${new Date().toISOString()}] ${level.toUpperCase().padEnd(5)} ${msg}`;
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else console.log(line);
}

function maskEmail(email) {
  const at   = email.indexOf('@');
  const name = at > 0 ? email.slice(0, at) : email;
  return `${name.slice(0, Math.min(2, name.length))}***${email.slice(at)}`;
}

// ─────────────────────────────────────────────────────────────── Middleware
app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    if (ALLOWED_ORIGINS.includes('*')) return cb(null, true);
    if (ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    cb(new Error('Not allowed by CORS'));
  },
  methods: ['GET', 'POST'],
}));
app.use(express.json({ limit: '8kb' }));
app.use(rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please slow down.' },
}));

// ─────────────────────────────────────────────────────────── API key gate
function requireApiKey(req, res, next) {
  if (!OTP_API_KEY) return next();
  const supplied = req.get('x-otp-key') || '';
  if (!secureEqual(supplied, OTP_API_KEY)) {
    log('warn', `401 from ${req.ip} — bad x-otp-key`);
    return res.status(401).json({ error: 'Unauthorized' });
  }
  return next();
}

// ─────────────────────────────────────────────────────────────── Validation
const EMAIL_RE = /^[\w.+\-]+@[\w\-]+\.[\w.\-]+$/;
const OTP_RE   = /^[0-9]{6}$/;

function normalise(email) {
  return String(email || '').trim().toLowerCase();
}

// ─────────────────────────────────────────────────────────────── Routes

app.get('/', (_req, res) => res.json({
  service:   `${APP_NAME} OTP Gateway`,
  version:   '3.0.0',
  status:    'running',
  storage:   'Upstash Redis',
  endpoints: {
    sendOtp:   'POST /api/auth/send-otp',
    verifyOtp: 'POST /api/auth/verify-otp',
    health:    'GET  /health',
  },
}));

app.get('/health', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// ── POST /api/auth/send-otp ──────────────────────────────────────────────────
app.post('/api/auth/send-otp', requireApiKey, async (req, res) => {
  const email = normalise(req.body?.email);

  if (!EMAIL_RE.test(email)) {
    return res.status(400).json({ error: 'A valid email address is required.' });
  }

  // Per-email send rate limit stored in Redis
  // key holds a counter; INCR is atomic, EXPIRE sets the window on first use
  const rateKey = sendRateKey(email);
  const count   = await redis.incr(rateKey);
  if (count === 1) {
    // First request in this window — set the expiry
    await redis.expire(rateKey, SEND_RATE_WINDOW_SEC);
  }
  if (count > SEND_RATE_MAX) {
    log('warn', `send-rate exceeded for ${maskEmail(email)}`);
    return res.status(429).json({
      error: 'Too many verification requests. Please wait a few minutes.',
    });
  }

  const otp  = generateOtp();   // plaintext — only used here and in the email
  const hash = hashOtp(otp);    // only the hash is persisted

  // Store challenge in Redis with automatic TTL expiry
  const challenge = JSON.stringify({ hash, attempts: 0, used: false });
  await redis.set(challengeKey(email), challenge, { ex: OTP_VALIDITY_SECONDS });

  try {
    await sendEmail(email, otp);
    log('info', `OTP sent to ${maskEmail(email)}`);
    return res.json({ ok: true, message: `A 6-digit code was sent to your email.` });
  } catch (err) {
    // Remove the challenge so the user can retry immediately
    await redis.del(challengeKey(email));
    log('error', `Email send failed for ${maskEmail(email)}: ${err.message}`);
    return res.status(502).json({
      error: 'The verification email could not be sent. Please try again.',
    });
  }
});

// ── POST /api/auth/verify-otp ────────────────────────────────────────────────
app.post('/api/auth/verify-otp', requireApiKey, async (req, res) => {
  const email = normalise(req.body?.email);
  const otp   = String(req.body?.otp || '').trim();

  if (!EMAIL_RE.test(email)) {
    return res.status(400).json({ error: 'A valid email address is required.' });
  }
  if (!OTP_RE.test(otp)) {
    return res.status(400).json({ error: 'OTP must be exactly 6 digits.' });
  }

  const raw = await redis.get(challengeKey(email));

  if (!raw) {
    return res.status(400).json({ error: 'No pending code for this address. Request a new one.' });
  }

  const challenge = typeof raw === 'string' ? JSON.parse(raw) : raw;

  if (challenge.used) {
    await redis.del(challengeKey(email));
    return res.status(400).json({ error: 'That code has already been used. Request a new one.' });
  }

  if (challenge.attempts >= OTP_MAX_ATTEMPTS) {
    await redis.del(challengeKey(email));
    return res.status(400).json({ error: 'Too many incorrect attempts. Request a new code.' });
  }

  const supplied = hashOtp(otp);

  if (!secureEqual(supplied, challenge.hash)) {
    challenge.attempts += 1;
    const left = OTP_MAX_ATTEMPTS - challenge.attempts;
    log('warn', `Wrong OTP for ${maskEmail(email)} — ${left} attempt(s) left`);

    if (left <= 0) {
      await redis.del(challengeKey(email));
      return res.status(400).json({ error: 'Too many incorrect attempts. Request a new code.' });
    }

    // Persist updated attempt count (keep same TTL by re-setting with remaining time)
    const ttl = await redis.ttl(challengeKey(email));
    await redis.set(
      challengeKey(email),
      JSON.stringify(challenge),
      { ex: Math.max(ttl, 1) },
    );

    return res.status(400).json({
      error: `That code is not correct. ${left} attempt${left === 1 ? '' : 's'} left.`,
    });
  }

  // ✓ Correct — burn the challenge immediately (single-use)
  await redis.del(challengeKey(email));
  log('info', `OTP verified for ${maskEmail(email)}`);

  return res.json({ verified: true, message: 'Email verified successfully.' });
});

// ─────────────────────────────────────────────────────────────── 404 + errors
app.use((_req, res) => res.status(404).json({ error: 'Endpoint not found.' }));

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  log('error', `Unhandled: ${err.message}`);
  res.status(500).json({ error: 'Internal server error.' });
});

// ─────────────────────────────────────────────────────────────── Start
app.listen(PORT, () => {
  log('info', `${APP_NAME} OTP Gateway v3 (Upstash Redis) on port ${PORT}`);
  log('info', `NODE_ENV=${process.env.NODE_ENV || 'development'}`);
  log('info', `OTP validity: ${OTP_VALIDITY_SECONDS / 60} min | max attempts: ${OTP_MAX_ATTEMPTS}`);
  log('info', `API key: ${OTP_API_KEY ? 'ENABLED' : 'disabled'}`);

  if (!process.env.UPSTASH_REDIS_REST_URL || !process.env.UPSTASH_REDIS_REST_TOKEN) {
    log('error', 'UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN not set — Redis will fail');
  }
  if (!process.env.MAIL_USER || !process.env.MAIL_PASS) {
    log('error', 'MAIL_USER / MAIL_PASS not set — email delivery will fail');
  } else {
    getTransport().verify()
      .then(() => log('info', 'SMTP credentials verified — email channel ready'))
      .catch(err => log('error', `SMTP verify failed: ${err.message}`));
  }
});
