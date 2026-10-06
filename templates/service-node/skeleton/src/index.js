require('./telemetry');

const { createApp } = require('./app');

const port = process.env.PORT || 8080;
const app = createApp();

app.listen(port, () => {
  process.stdout.write(`[${process.env.OTEL_SERVICE_NAME || '${{ values.service_name }}'}] listening on ${port}\n`);
});
