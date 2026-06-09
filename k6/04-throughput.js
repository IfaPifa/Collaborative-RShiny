/**
 * Benchmark 4 — Throughput Under Load
 *
 * Ramps from 0 → 100 VUs performing a full user workflow across all 8 apps:
 *   login → list apps → create session → POST state → GET state → save
 *
 * Each VU rotates through apps so all 8 backends are hit concurrently.
 * Measures requests/sec, error rate, and response times at each load level.
 *
 * Custom metrics (tagged with app_name and operation):
 *   throughput_response_ms — per-operation response time
 *   throughput_errors      — error rate across all operations
 *   throughput_ops         — total operations completed
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import {
  API, login, authHeaders, userForVU, appForVU, healthCheck,
  createSession, postState, getState, saveSessionState,
} from './config.js';

const responseMs = new Trend('throughput_response_ms', true);
const errorRate  = new Rate('throughput_errors');
const opsTotal   = new Counter('throughput_ops');

export const options = {
  scenarios: {
    throughput_ramp: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '1m',  target: 25 },
        { duration: '1m',  target: 50 },
        { duration: '1m',  target: 75 },
        { duration: '1m',  target: 100 },
        { duration: '30s', target: 50 },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<15000'],
    'throughput_errors': ['rate<0.3'],
  },
};

function track(res, op, appName) {
  const tags = { operation: op, app_name: appName };
  responseMs.add(res.timings.duration, tags);
  const ok = res.status >= 200 && res.status < 300;
  errorRate.add(!ok, tags);
  opsTotal.add(1, tags);
  return ok;
}

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  return {};
}

export default function () {
  const username = userForVU(__VU);
  const app = appForVU(__VU, __ITER);
  const appTag = app.appName;

  group(`throughput_${appTag}`, function () {
    // 1. Login
    const token = login(username);
    if (!token) {
      errorRate.add(true, { operation: 'login', app_name: appTag });
      sleep(1);
      return;
    }

    // 2. List apps
    const listRes = http.get(`${API}/apps`, {
      headers: authHeaders(token),
      tags: { operation: 'list_apps', app_name: appTag },
    });
    track(listRes, 'list_apps', appTag);

    // 3. Create session
    const session = createSession(token, app.id, `tp-${appTag}-${__VU}-${__ITER}`);
    if (!session) {
      errorRate.add(true, { operation: 'create_session', app_name: appTag });
      sleep(0.5);
      return;
    }

    // 4. POST state (relay through pipeline)
    const payload = app.payload(__VU, __ITER);
    const postRes = postState(token, session.id, payload, { app_name: appTag });
    track(postRes, 'post_state', appTag);

    // 5. GET state (read from cache)
    const getRes = getState(token, session.id, { app_name: appTag });
    track(getRes, 'get_state', appTag);

    // 6. Save state to DB
    sleep(0.5);
    const saveRes = saveSessionState(token, session.id, `tp-save-${__VU}-${__ITER}`);
    track(saveRes, 'save_state', appTag);

    // 7. List my sessions
    const sessionsRes = http.get(`${API}/collab`, {
      headers: authHeaders(token),
      tags: { operation: 'list_sessions', app_name: appTag },
    });
    track(sessionsRes, 'list_sessions', appTag);

    check(null, {
      [`${appTag} full workflow ok`]: () =>
        postRes.status === 200 && getRes.status === 200,
    });
  });

  sleep(0.5);
}
