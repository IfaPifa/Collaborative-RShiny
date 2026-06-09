/**
 * Benchmark 2 — Collaboration Latency (Cross-User Propagation)
 *
 * Measures how long it takes for user B to see user A's state change
 * in a shared collaborative session. This is the core collaboration
 * metric — it captures the full pipeline latency including any
 * async processing (Kafka consumer lag, Redis write, etc.).
 *
 * Each VU:
 *   1. Login as user A (host)
 *   2. Create a collaborative session
 *   3. Login as user B (guest)
 *   4. User B joins the session
 *   5. User A POSTs state with a unique marker
 *   6. User B polls GET until the marker appears
 *   7. Measure the propagation time (step 5 → step 6)
 *
 * Tests all 8 apps by rotating per iteration.
 * Ramps 1 → 10 → 20 → 30 → 10 VUs over 4.5 minutes.
 *
 * Custom metrics (tagged with app_name):
 *   collab_propagation_ms — time from host POST return until guest sees it
 *   collab_host_post_ms   — host's POST response time
 *   collab_success         — successful propagation count
 *   collab_timeout         — guest never saw the update within 10s
 */

import { check, sleep, group } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import {
  APPS, USERS, login, createSession, joinSession,
  postState, getState, healthCheck,
} from './config.js';

const collabPropagation = new Trend('collab_propagation_ms', true);
const collabHostPost    = new Trend('collab_host_post_ms', true);
const collabSuccess     = new Counter('collab_success');
const collabTimeout     = new Counter('collab_timeout');

export const options = {
  scenarios: {
    collab_latency: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '1m',  target: 20 },
        { duration: '1m',  target: 30 },
        { duration: '1m',  target: 15 },
        { duration: '30s', target: 1 },
      ],
    },
  },
  thresholds: {
    'collab_propagation_ms': ['p(95)<10000'],
    'http_req_failed':       ['rate<0.2'],
  },
};

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  return {};
}

export default function () {
  // Pick two different users for host and guest
  const hostUser  = USERS[__VU % USERS.length];
  const guestUser = USERS[(__VU + 1) % USERS.length];

  // Rotate through apps per iteration
  const app = APPS[(__VU + __ITER) % APPS.length];
  const tags = { app_name: app.appName };

  group(`collab_${app.appName}`, function () {
    // 1. Login as host
    const hostToken = login(hostUser);
    if (!hostToken) { collabTimeout.add(1, tags); return; }

    // 2. Create session
    const session = createSession(
      hostToken, app.id,
      `collab-${app.appName}-${__VU}-${__ITER}-${Date.now()}`,
    );
    if (!session) { collabTimeout.add(1, tags); return; }

    // 3. Login as guest
    const guestToken = login(guestUser);
    if (!guestToken) { collabTimeout.add(1, tags); return; }

    // 4. Guest joins the session
    const joined = joinSession(guestToken, session.id);
    if (!joined) { collabTimeout.add(1, tags); return; }

    // 5. Host POSTs state with a unique marker
    const marker  = `collab_${__VU}_${__ITER}_${Date.now()}`;
    const payload = app.payload(__VU, __ITER);
    payload._marker = marker;
    payload.sender  = hostUser;

    const t0 = Date.now();
    const postRes = postState(hostToken, session.id, payload, tags);
    const postMs = Date.now() - t0;
    collabHostPost.add(postMs, tags);

    if (postRes.status !== 200) {
      collabTimeout.add(1, tags);
      return;
    }

    // 6. Guest polls GET until the marker appears
    const pollStart = Date.now();
    let found = false;
    for (let i = 0; i < 40; i++) {
      const getRes = getState(guestToken, session.id, tags);
      if (getRes.status === 200 && getRes.body && getRes.body.includes(marker)) {
        found = true;
        break;
      }
      sleep(0.25);
    }
    const propagation = Date.now() - pollStart;
    collabPropagation.add(propagation, tags);

    if (found) {
      collabSuccess.add(1, tags);
    } else {
      collabTimeout.add(1, tags);
    }

    check(null, {
      [`${app.appName} guest sees host state`]: () => found,
    });
  });

  sleep(1);
}
