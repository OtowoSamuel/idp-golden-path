const express = require('express');
const client = require('prom-client');
const pkg = require('../package.json');

function createApp() {
  const app = express();
  const register = new client.Registry();
  client.collectDefaultMetrics({ register });

  const httpRequestsTotal = new client.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests handled',
    labelNames: ['method', 'route', 'code'],
    registers: [register],
  });

  app.use((req, res, next) => {
    res.on('finish', () => {
      httpRequestsTotal.inc({
        method: req.method,
        route: req.route ? req.route.path : req.path,
        code: String(res.statusCode),
      });
    });
    next();
  });

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: pkg.name });
  });

  app.get('/ready', (req, res) => {
    res.json({ status: 'ready', service: pkg.name });
  });

  app.get('/api/hello', (req, res) => {
    res.json({ message: 'Hello from ' + pkg.name, version: pkg.version });
  });

  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.send(await register.metrics());
  });

  return app;
}

module.exports = { createApp };
