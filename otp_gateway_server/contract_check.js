// Contract check: starts the real gateway, exercises the exact HTTP contract
// that GatewayOtpSender in the Flutter app depends on, then shuts it down.
//
// SAFETY: the gateway's real .env holds a live mailbox credential. This
// harness never loads it. server.js is copied into a scratch directory next to
// a blank .env, and the original node_modules is reached through NODE_PATH, so
// the process under test provably has no credentials and cannot send mail.
'use strict';

const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SERVER_DIR = process.argv[2];
const PORT = Number(process.env.CHECK_PORT || 4131);
const BASE = `http://127.0.0.1:${PORT}`;
const KEY = 'contract-test-key';

if (!SERVER_DIR || !fs.existsSync(SERVER_DIR)) {
  console.error('usage: node contract_check.js <gateway-dir>');
  process.exit(2);
}

// Must be absolute: the child runs with `cwd` set to the scratch directory, and a
// relative NODE_PATH would be resolved against that instead of this folder.
const GATEWAY_DIR = path.resolve(SERVER_DIR);

// A port already in use would mean we are testing somebody else's process, so
// refuse rather than silently probing it.
function assertPortFree() {
  const net = require('net');
  const probe = net.createServer();
  return new Promise((resolve, reject) => {
    probe.once('error', (e) =>
      reject(new Error(`port ${PORT} is already in use (${e.code}); refusing to test an unknown server`)),
    );
    probe.once('listening', () => probe.close(() => resolve()));
    probe.listen(PORT, '127.0.0.1');
  });
}

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'gw-contract-'));
fs.copyFileSync(path.join(GATEWAY_DIR, 'server.js'), path.join(scratch, 'server.js'));
// Blank on purpose: no MAIL_USER / MAIL_PASS, so every send must be refused.
fs.writeFileSync(
  path.join(scratch, '.env'),
  [
    `APP_NAME=Committee Manager`,
    `HOST=127.0.0.1`,
    `PORT=${PORT}`,
    `OTP_API_KEY=${KEY}`,
    `MAIL_USER=`,
    `MAIL_PASS=`,
    `LOG_CODES=false`,
    '',
  ].join('\n'),
);
fs.writeFileSync(
  path.join(scratch, 'package.json'),
  JSON.stringify({ name: 'contract-check', private: true, main: 'server.js' }),
);

const child = spawn(process.execPath, ['server.js'], {
  cwd: scratch,
  env: {
    ...process.env,
    NODE_PATH: path.join(GATEWAY_DIR, 'node_modules'),
    // Belt and braces: even if dotenv resolved the real file, these win because
    // dotenv never overwrites a key that already exists in process.env.
    MAIL_USER: '',
    MAIL_PASS: '',
    OTP_API_KEY: KEY,
    PORT: String(PORT),
    HOST: '127.0.0.1',
    LOG_CODES: 'false',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let serverLog = '';
child.stdout.on('data', (d) => {
  serverLog += d;
});
child.stderr.on('data', (d) => {
  serverLog += d;
});

function shutdown(code) {
  child.kill();
  try {
    fs.rmSync(scratch, { recursive: true, force: true });
  } catch (_) {
    /* best effort */
  }
  setTimeout(() => process.exit(code), 300);
}

async function waitForHealth(attempts = 40) {
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(`${BASE}/health`);
      if (res.ok) return true;
    } catch (_) {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}

const results = [];
function check(name, passed, detail) {
  results.push({ name, passed, detail });
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -> ${detail}` : ''}`);
}

async function postOtp(body, key) {
  const headers = { 'content-type': 'application/json' };
  if (key !== undefined) headers['x-otp-key'] = key;
  const res = await fetch(`${BASE}/otp`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_) {
    /* not json */
  }
  return { status: res.status, json, text };
}

(async () => {
  try {
    await assertPortFree();
  } catch (e) {
    console.error(String(e.message));
    process.exit(2);
  }

  if (!(await waitForHealth())) {
    console.error('gateway never became healthy\n' + serverLog);
    return shutdown(1);
  }

  // 1. Health is reachable without the API key, which is what the app polls.
  const health = await (await fetch(`${BASE}/health`)).json();
  check('GET /health answers without the key', health.ok === true, JSON.stringify(health.channels));
  check(
    'health reports email as NOT ready when credentials are blank',
    health.channels && health.channels.email === false,
    health.emailError || '',
  );

  // 2. The delivery route is gated by x-otp-key.
  const noKey = await postOtp(
    { destination: 'user@example.com', channel: 'email', code: '123456', purpose: 'Account verification' },
    undefined,
  );
  check('POST /otp without a key is 401', noKey.status === 401, String(noKey.status));

  const badKey = await postOtp(
    { destination: 'user@example.com', channel: 'email', code: '123456', purpose: 'p' },
    'wrong-key',
  );
  check('POST /otp with a wrong key is 401', badKey.status === 401, String(badKey.status));

  // 3. Body validation matches what the Dart sender sends.
  const badEmail = await postOtp(
    { destination: 'not-an-email', channel: 'email', code: '123456', purpose: 'p' },
    KEY,
  );
  check(
    'an invalid destination is 400',
    badEmail.status === 400 && /valid email/i.test(badEmail.json?.error || ''),
    badEmail.json?.error,
  );

  const badCode = await postOtp(
    { destination: 'user@example.com', channel: 'email', code: 'abc', purpose: 'p' },
    KEY,
  );
  check(
    'a non-numeric code is 400',
    badCode.status === 400 && /code must be/i.test(badCode.json?.error || ''),
    badCode.json?.error,
  );

  const sms = await postOtp(
    { destination: '+923001234567', channel: 'sms', code: '123456', purpose: 'p' },
    KEY,
  );
  check(
    'the removed SMS channel is rejected with 400',
    sms.status === 400 && /email only/i.test(sms.json?.error || ''),
    sms.json?.error,
  );

  // 4. A well-formed request with blank credentials must fail 503 with the
  //    message the gateway authored for users. This is the exact path the Dart
  //    sender surfaces, and the exact error text its test asserts on.
  const good = await postOtp(
    { destination: 'user@example.com', channel: 'email', code: '123456', purpose: 'Account verification' },
    KEY,
  );
  check(
    'a valid request with no mail credentials is 503',
    good.status === 503,
    String(good.status),
  );
  check(
    'the 503 body carries no secret material',
    // Matches on credential *values* (a bearer token, a PEM, a URL with a
    // password), not on the words "MAIL_PASS" appearing in a config hint.
    !/-----BEGIN|eyJ[A-Za-z0-9_-]{10,}|[a-z]+:\/\/[^\s"']*:[^\s"'@]+@/i.test(good.text),
    good.text,
  );
  check(
    'the 503 message is the gateway-authored, user-safe one',
    /not configured on the gateway/i.test(good.json?.error || ''),
    good.json?.error,
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\n${results.length - failed.length}/${results.length} contract checks passed`);
  if (failed.length) {
    console.log('\n--- gateway log ---\n' + serverLog);
  }
  shutdown(failed.length ? 1 : 0);
})().catch((err) => {
  console.error('harness error:', err);
  console.error('--- gateway log ---\n' + serverLog);
  shutdown(1);
});
