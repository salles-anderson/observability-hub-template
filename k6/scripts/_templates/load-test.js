/**
 * Template: Load Test
 *
 * Teste de carga com ramp-up e ramp-down.
 * Duração: ~15 minutos | VUs: 10 → 50 → 100 → 50 → 0
 *
 * Uso:
 *   k6 run -e BASE_URL=https://sua-api.com load-test.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const apiLatency = new Trend('api_latency', true);

export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp-up
    { duration: '5m', target: 50 },   // Carga normal
    { duration: '2m', target: 100 },  // Pico
    { duration: '5m', target: 50 },   // Volta ao normal
    { duration: '1m', target: 0 },    // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.01'],
  },
  tags: {
    testType: 'load',
    project: __ENV.PROJECT || 'unknown',
    environment: __ENV.ENVIRONMENT || 'dev',
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const API_TOKEN = __ENV.API_TOKEN || '';

const headers = {
  'Content-Type': 'application/json',
  ...(API_TOKEN && { 'Authorization': `Bearer ${API_TOKEN}` }),
};

export function setup() {
  const res = http.get(`${BASE_URL}/health`);
  if (res.status !== 200) {
    throw new Error(`API não está saudável: ${res.status}`);
  }
  console.log(`Iniciando teste contra: ${BASE_URL}`);
  return {};
}

export default function () {
  group('Health Check', () => {
    const res = http.get(`${BASE_URL}/health`);
    check(res, { 'health: 200': (r) => r.status === 200 });
  });

  sleep(randomBetween(1, 3));

  group('API Endpoints', () => {
    // Adicione seus endpoints aqui
    const res = http.get(`${BASE_URL}/api/v1/status`, { headers });

    const success = check(res, {
      'api: status 2xx': (r) => r.status >= 200 && r.status < 300,
      'api: latency < 500ms': (r) => r.timings.duration < 500,
    });

    apiLatency.add(res.timings.duration);
    errorRate.add(!success);
  });

  sleep(randomBetween(1, 2));
}

function randomBetween(min, max) {
  return Math.random() * (max - min) + min;
}

export function handleSummary(data) {
  const p95 = data.metrics.http_req_duration?.values['p(95)'] || 0;
  const errRate = data.metrics.errors?.values?.rate || 0;
  const passed = p95 < 500 && errRate < 0.01;

  console.log(`\n${'='.repeat(50)}`);
  console.log(passed ? '✅ LOAD TEST PASSED' : '❌ LOAD TEST FAILED');
  console.log(`P95: ${p95.toFixed(2)}ms | Error Rate: ${(errRate * 100).toFixed(2)}%`);
  console.log(`${'='.repeat(50)}\n`);

  return {};
}
