const express = require('express');
const client = require('prom-client');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Collect default Node.js/process metrics (CPU, memory, event loop, etc.).
client.collectDefaultMetrics();

// Total HTTP requests handled by this service.
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

// Total HTTP errors (5xx) handled by this service.
const httpErrorsTotal = new client.Counter({
  name: 'http_errors_total',
  help: 'Total number of HTTP 5xx responses',
  labelNames: ['method', 'route', 'status_code']
});

// HTTP request duration histogram in seconds.
const httpRequestDurationSeconds = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  // Production-like buckets from fast to slow API responses.
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1, 2, 5]
});

// Middleware to record request count, error count, and latency.
app.use((req, res, next) => {
  const endTimer = httpRequestDurationSeconds.startTimer();

  res.on('finish', () => {
    const route = req.route?.path || req.path || 'unknown';
    const labels = {
      method: req.method,
      route,
      status_code: String(res.statusCode)
    };

    httpRequestsTotal.inc(labels);
    endTimer(labels);

    if (res.statusCode >= 500) {
      httpErrorsTotal.inc(labels);
    }
  });

  next();
});

app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    message: 'CI/CD Pipeline Demo App',
    version: process.env.APP_VERSION || '1.0.0'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', uptime: process.uptime() });
});

app.get('/greet/:name', (req, res) => {
  const { name } = req.params;
  res.json({ message: `Hello, ${name}!` });
});

// Endpoint used to test alerting paths.
app.get('/error', (req, res) => {
  res.status(500).json({ error: 'Simulated internal error' });
});

// Prometheus metrics endpoint.
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

if (require.main === module) {
  app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
}

module.exports = app;
