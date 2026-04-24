const { MongoClient } = require('mongodb');
const logger = require('./logger');

const MONGODB_URL = process.env.MONGODB_URL || 'mongodb://mongodb:27017/orders';

let client = null;
let connected = false;
let pingInterval = null;

// Periodic connectivity check — flips `connected` within 3s of an outage
const startPingLoop = () => {
  pingInterval = setInterval(async () => {
    if (!client) return;
    try {
      await client.db('admin').command({ ping: 1 });
      if (!connected) {
        logger.info('MongoDB reconnected');
        connected = true;
      }
    } catch {
      if (connected) {
        logger.warn('MongoDB connection lost');
        connected = false;
      }
    }
  }, 3000);
};

const connect = async () => {
  client = new MongoClient(MONGODB_URL, {
    serverSelectionTimeoutMS: 5000,
    connectTimeoutMS: 5000,
  });
  await client.connect();
  connected = true;
  logger.info({ url: MONGODB_URL }, 'MongoDB initial connection established');
  startPingLoop();
};

const disconnect = async () => {
  if (pingInterval) clearInterval(pingInterval);
  if (client) await client.close();
  connected = false;
};

const isConnected = () => connected;

const collection = () => {
  if (!client || !connected) throw new Error('MongoDB not connected');
  return client.db('orders').collection('orders');
};

const insertOrder = (order) => collection().insertOne(order);

const listOrders = () =>
  collection().find({}).sort({ createdAt: -1 }).limit(20).toArray();

module.exports = { connect, disconnect, isConnected, insertOrder, listOrders };
