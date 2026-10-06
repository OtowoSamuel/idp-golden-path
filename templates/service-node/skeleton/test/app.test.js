const { test, after } = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');

const app = createApp();
const server = app.listen(0);
const base = `http://127.0.0.1:${server.address().port}`;

after(() => server.close());

test('health returns ok', async () => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.service, '${{ values.service_name }}');
});

test('api/hello returns service message', async () => {
  const res = await fetch(`${base}/api/hello`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.match(body.message, new RegExp('${{ values.service_name }}'));
});

test('metrics endpoint exposes request counter', async () => {
  await fetch(`${base}/health`);
  const res = await fetch(`${base}/metrics`);
  assert.equal(res.status, 200);
  const text = await res.text();
  assert.match(text, /http_requests_total/);
  assert.match(text, /process_cpu_user_seconds_total/);
});
