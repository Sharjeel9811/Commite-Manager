'use strict';
/**
 * Dev-only helper for on-device verification.
 *
 * Serves the gateway's log file over HTTP so an integration test running on the
 * emulator/phone can read the LOG_CODES line ("the code was NNNNNN") back
 * through an adb reverse tunnel. It binds to 0.0.0.0 ONLY so the reverse tunnel
 * can reach it; it serves one fixed file and nothing else.
 *
 * Usage:  node logserve.js <path-to-gateway-log>
 */
require('dotenv').config();
const http = require('http');
const fs = require('fs');

const LOG_PATH = process.argv[2] || 'gateway.log';
const PORT = Number(process.env.LOGSERVE_PORT || 4101);

const server = http.createServer((req, res) => {
  if (req.url !== '/log') {
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('not found');
    return;
  }
  fs.readFile(LOG_PATH, 'utf8', (err, data) => {
    res.writeHead(200, { 'content-type': 'text/plain', 'cache-control': 'no-store' });
    res.end(err ? '' : data);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`logserve listening on 0.0.0.0:${PORT} serving ${LOG_PATH}`);
});