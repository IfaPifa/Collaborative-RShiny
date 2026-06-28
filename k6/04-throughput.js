/**
 * Benchmark 4 — Throughput Under Load
 *
 * Ramps from 0 → 100 VUs performing a full user workflow across all 8 apps:
 *   login → list apps → create session → POST state → GET state → save
 *
 * Each VU rotates through apps so all 8 backends are hit concurrently.
 * Measures requests/sec, error rate, and response times at each load level.
 *
 * Custom metrics (tagged with app_name, operation, and vu_bucket):
 *   throughput_response_ms — per-operation response time
 *   throughput_errors      — error rate across all operations
 *   throughput_ops         — total operations completed
 *
 * vu_bucket tags each data point with the active concurrent-user level
 * (5-VU buckets: "01-05", "06-10", ...), so you can compare latency/error
 * rate at each load step — e.g. how things degrade around ~20 users.
 * The ramp uses stepped plateaus so each bucket holds steady before measuring.
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import {
  API, login, authHeaders, userForVU, appForVU, healthCheck,
  createSession, postState, getState, saveSessionState,
  perAppThresholds, loadBucket,
} from './config.js';

const responseMs = new Trend('throughput_response_ms', true);
const errorRate  = new Rate('throughput_errors');
const opsTotal   = new Counter('throughput_ops');

export const options = {
  scenarios: {
    throughput_ramp: {
      executor: 'ramping-vus',
      startVUs: 0,
      // Stepped plateaus (not a smooth ramp) so each load level holds steady
      // long enough for vu_bucket-tagged metrics to be stable. Fine 5-VU steps
      // through the ~20-user breakdown zone, coarser above it.
      stages: [
        { duration: '10s', target: 5  }, { duration: '40s', target: 5  },
        { duration: '10s', target: 10 }, { duration: '40s', target: 10 },
        { duration: '10s', target: 15 }, { duration: '40s', target: 15 },
        { duration: '10s', target: 20 }, { duration: '40s', target: 20 },
        { duration: '10s', target: 25 }, { duration: '40s', target: 25 },
        { duration: '10s', target: 50 }, { duration: '40s', target: 50 },
        { duration: '10s', target: 75 }, { duration: '40s', target: 75 },
        { duration: '10s', target: 100 }, { duration: '40s', target: 100 },
        { duration: '20s', target: 0 },
      ],
    },
  },
  thresholds: Object.assign(
    { 'throughput_errors': ['rate<0.3'] },
    perAppThresholds('throughput_response_ms', 'throughput'),
  ),
};

function track(res, op, appName) {
  const tags = { operation: op, app_name: appName, vu_bucket: loadBucket() };
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
  const bucket = loadBucket();

  group(`throughput_${appTag}`, function () {
    // 1. Login
    const token = login(username);
    if (!token) {
      errorRate.add(true, { operation: 'login', app_name: appTag, vu_bucket: bucket });
      sleep(1);
      return;
    }

    // 2. List apps
    const listRes = http.get(`${API}/apps`, {
      headers: authHeaders(token),
      tags: { operation: 'list_apps', app_name: appTag, vu_bucket: bucket },
    });
    track(listRes, 'list_apps', appTag);

    // 3. Create session
    const session = createSession(token, app.id, `tp-${appTag}-${__VU}-${__ITER}`);
    if (!session) {
      errorRate.add(true, { operation: 'create_session', app_name: appTag, vu_bucket: bucket });
      sleep(0.5);
      return;
    }

    // 4. POST state (relay through pipeline)
    const payload = app.payload(__VU, __ITER);
    payload.sender = username;
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
      tags: { operation: 'list_sessions', app_name: appTag, vu_bucket: bucket },
    });
    track(sessionsRes, 'list_sessions', appTag);

    check(null, {
      [`${appTag} full workflow ok`]: () =>
        postRes.status === 200 && getRes.status === 200,
    });
  });

  sleep(0.5);
}
