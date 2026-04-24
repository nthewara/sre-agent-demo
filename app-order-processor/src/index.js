require('dotenv').config();

// Initialize Application Insights if connection string is provided
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const appInsights = require('applicationinsights');
  appInsights
    .setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true)
    .setSendLiveMetrics(true)
    .start();
}

const express = require('express');
const pinoHttp = require('pino-http');
const { v4: uuidv4 } = require('uuid');
const logger = require('./logger');
const db = require('./mongodb');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(express.json());
app.use(pinoHttp({ logger }));

// ── Health endpoints ──────────────────────────────────────────────────────────

app.get('/health', async (req, res) => {
  const healthy = db.isConnected();
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'healthy' : 'degraded',
    timestamp: new Date().toISOString(),
    checks: {
      mongodb: healthy ? 'connected' : 'disconnected',
    },
  });
});

app.get('/ready', (req, res) => {
  if (db.isConnected()) {
    res.status(200).json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'not ready', reason: 'MongoDB not connected' });
  }
});

app.get('/live', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

// ── Order API ─────────────────────────────────────────────────────────────────

// Submit an order
app.post('/api/orders', async (req, res) => {
  const { item, quantity } = req.body;
  if (!item) return res.status(400).json({ error: 'item is required' });

  try {
    const order = {
      id: uuidv4(),
      item,
      quantity: quantity || 1,
      status: 'pending',
      createdAt: new Date(),
    };
    await db.insertOrder(order);
    logger.info({ orderId: order.id, item }, 'Order created');
    res.status(201).json({ message: 'Order created', order });
  } catch (err) {
    logger.error({ error: err.message }, 'Failed to create order');
    res.status(500).json({ error: 'Failed to create order' });
  }
});

// List orders
app.get('/api/orders', async (req, res) => {
  try {
    const orders = await db.listOrders();
    res.json({ orders });
  } catch (err) {
    logger.error({ error: err.message }, 'Failed to list orders');
    res.status(500).json({ error: 'Failed to list orders' });
  }
});

// ── Metrics ───────────────────────────────────────────────────────────────────

app.get('/metrics', (req, res) => {
  res.json({
    uptime: process.uptime(),
    memoryUsage: process.memoryUsage(),
    cpuUsage: process.cpuUsage(),
    mongodb: { connected: db.isConnected() },
    timestamp: new Date().toISOString(),
  });
});

// ── Error handler ─────────────────────────────────────────────────────────────

app.use((err, req, res, next) => {
  logger.error({ error: err.message, url: req.url, method: req.method }, 'Unhandled error');
  res.status(500).json({ error: 'Internal server error' });
});

// ── Graceful shutdown ─────────────────────────────────────────────────────────

const gracefulShutdown = async (signal) => {
  logger.info({ signal }, 'Received shutdown signal');
  try {
    await db.disconnect();
    logger.info('Graceful shutdown completed');
    process.exit(0);
  } catch (err) {
    logger.error({ error: err.message }, 'Error during shutdown');
    process.exit(1);
  }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// ── Start ─────────────────────────────────────────────────────────────────────

const startServer = async () => {
  try {
    await db.connect();
  } catch (err) {
    logger.error({ error: err.message }, 'Failed to connect to MongoDB — starting in degraded mode');
  }

  app.listen(PORT, () => {
    logger.info({ port: PORT }, 'Order processor started');
  });
};

startServer();
