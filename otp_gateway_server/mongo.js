'use strict';

const { MongoClient } = require('mongodb');

let client;
let database;

function isConfigured() {
  return Boolean(process.env.MONGODB_URI);
}

async function getDatabase() {
  if (!isConfigured()) {
    throw new Error('MONGODB_URI is not configured');
  }
  if (database) return database;

  client = new MongoClient(process.env.MONGODB_URI, {
    serverSelectionTimeoutMS: 5000,
  });
  await client.connect();
  database = client.db(process.env.MONGODB_DATABASE || 'committee_manager');
  return database;
}

async function checkConnection() {
  const db = await getDatabase();
  await db.command({ ping: 1 });
  return true;
}

async function close() {
  if (client) await client.close();
  client = undefined;
  database = undefined;
}

module.exports = {
  checkConnection,
  close,
  getDatabase,
  isConfigured,
};
