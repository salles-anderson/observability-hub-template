/**
 * Template: Smoke Test
 *
 * Teste rápido para validar que a API está funcionando.
 * Duração: 30 segundos | VUs: 1
 *
 * Uso:
 *   k6 run -e BASE_URL=https://sua-api.com smoke-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  vus: __ENV.K6_VUS || 1,
  duration: __ENV.K6_DURATION || '30s',
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    errors: ['rate<0.1'],
  },
  tags: {
    testType: 'smoke',
    project: __ENV.PROJECT || 'unknown',
    environment: __ENV.ENVIRONMENT || 'dev',
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export default function () {
  const res = http.get(`${BASE_URL}/health`, {
    tags: { name: 'health' },
  });

  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  errorRate.add(!success);
  sleep(1);
}

export function handleSummary(data) {
  const passed = data.metrics.errors.values.rate < 0.1;
  console.log(`\n${'='.repeat(50)}`);
  console.log(passed ? '✅ SMOKE TEST PASSED' : '❌ SMOKE TEST FAILED');
  console.log(`${'='.repeat(50)}\n`);
  return {};
}
