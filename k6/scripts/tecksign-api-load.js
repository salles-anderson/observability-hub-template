/**
 * Tecksign API - Load Test
 *
 * Teste de carga para validar performance sob diferentes niveis de carga.
 * Simula um padrao realista de usuarios acessando a API.
 *
 * Uso:
 *   k6 run -e BASE_URL=https://api.tecksign.dev.tecksolucoes.com.br \
 *          -e API_TOKEN=xxx \
 *          --out experimental-prometheus-rw \
 *          tecksign-api-load.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Metricas customizadas
const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration', true);
const successfulRequests = new Counter('successful_requests');
const failedRequests = new Counter('failed_requests');

// Configuracao do teste - Ramping pattern
export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp-up lento
    { duration: '5m', target: 50 },   // Carga normal
    { duration: '2m', target: 100 },  // Pico de carga
    { duration: '5m', target: 50 },   // Volta ao normal
    { duration: '2m', target: 0 },    // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.01'],
    http_req_failed: ['rate<0.01'],
  },
  tags: {
    testType: 'load',
    service: 'tecksign-api',
    environment: __ENV.ENVIRONMENT || 'dev',
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://api.tecksign.dev.tecksolucoes.com.br';
const API_TOKEN = __ENV.API_TOKEN || '';

// Headers padrao
const headers = {
  'Content-Type': 'application/json',
  'Authorization': API_TOKEN ? `Bearer ${API_TOKEN}` : '',
};

export function setup() {
  // Validar conectividade antes de iniciar
  const healthRes = http.get(`${BASE_URL}/health`);
  if (healthRes.status !== 200) {
    throw new Error(`API nao esta saudavel: ${healthRes.status}`);
  }
  console.log(`Teste iniciando contra: ${BASE_URL}`);
  return { startTime: new Date().toISOString() };
}

export default function (data) {
  group('Health Check', function () {
    const res = http.get(`${BASE_URL}/health`, {
      tags: { name: 'GET /health' },
    });

    const success = check(res, {
      'health: status is 200': (r) => r.status === 200,
      'health: response time < 200ms': (r) => r.timings.duration < 200,
    });

    if (success) {
      successfulRequests.add(1);
    } else {
      failedRequests.add(1);
      errorRate.add(1);
    }
  });

  sleep(randomIntBetween(1, 3));

  // Se tiver token, testar endpoints autenticados
  if (API_TOKEN) {
    group('Authenticated Endpoints', function () {
      // Listar documentos
      const docsRes = http.get(`${BASE_URL}/api/v1/documents`, {
        headers: headers,
        tags: { name: 'GET /api/v1/documents' },
      });

      const docsSuccess = check(docsRes, {
        'documents: status is 200': (r) => r.status === 200,
        'documents: response time < 500ms': (r) => r.timings.duration < 500,
        'documents: has content': (r) => r.body && r.body.length > 0,
      });

      apiDuration.add(docsRes.timings.duration, { endpoint: 'documents' });

      if (docsSuccess) {
        successfulRequests.add(1);
      } else {
        failedRequests.add(1);
        errorRate.add(1);
      }

      sleep(randomIntBetween(1, 2));

      // Status do usuario
      const userRes = http.get(`${BASE_URL}/api/v1/user/status`, {
        headers: headers,
        tags: { name: 'GET /api/v1/user/status' },
      });

      const userSuccess = check(userRes, {
        'user: status is 200 or 404': (r) => [200, 404].includes(r.status),
        'user: response time < 500ms': (r) => r.timings.duration < 500,
      });

      apiDuration.add(userRes.timings.duration, { endpoint: 'user' });

      if (userSuccess) {
        successfulRequests.add(1);
      } else {
        failedRequests.add(1);
        errorRate.add(1);
      }
    });
  }

  sleep(randomIntBetween(1, 3));
}

export function teardown(data) {
  console.log(`Teste finalizado. Iniciou em: ${data.startTime}`);
}

export function handleSummary(data) {
  const p95 = data.metrics.http_req_duration.values['p(95)'];
  const errorRateValue = data.metrics.errors ? data.metrics.errors.values.rate : 0;
  const passed = p95 < 500 && errorRateValue < 0.01;

  console.log('\n========================================');
  console.log(passed ? 'LOAD TEST PASSED' : 'LOAD TEST FAILED');
  console.log(`P95 Latency: ${p95.toFixed(2)}ms (threshold: <500ms)`);
  console.log(`Error Rate: ${(errorRateValue * 100).toFixed(2)}% (threshold: <1%)`);
  console.log('========================================\n');

  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    './results/load-test-summary.json': JSON.stringify(data, null, 2),
  };
}

// Funcao auxiliar
function randomIntBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1) + min);
}

import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.3/index.js';
