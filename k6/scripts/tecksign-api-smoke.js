/**
 * Tecksign API - Smoke Test
 *
 * Teste rapido para validar que a API esta funcionando corretamente.
 * Ideal para executar apos deploys ou em pipelines CI/CD.
 *
 * Uso:
 *   k6 run -e BASE_URL=https://api.tecksign.dev.tecksolucoes.com.br tecksign-api-smoke.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Metricas customizadas
const errorRate = new Rate('errors');

// Configuracao do teste
export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    errors: ['rate<0.1'],
  },
  tags: {
    testType: 'smoke',
    service: 'tecksign-api',
    environment: __ENV.ENVIRONMENT || 'dev',
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://api.tecksign.dev.tecksolucoes.com.br';

export default function () {
  // Health check
  const healthRes = http.get(`${BASE_URL}/health`, {
    tags: { name: 'health' },
  });

  const healthCheck = check(healthRes, {
    'health: status is 200': (r) => r.status === 200,
    'health: response time < 500ms': (r) => r.timings.duration < 500,
  });

  errorRate.add(!healthCheck);

  sleep(1);
}

export function handleSummary(data) {
  const passed = data.metrics.errors.values.rate < 0.1;

  console.log('\n========================================');
  console.log(passed ? 'SMOKE TEST PASSED' : 'SMOKE TEST FAILED');
  console.log('========================================\n');

  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.3/index.js';
