/**
 * Benchmark 7 — Session Lifecycle Stress
 *
 * Exercises the full collaboration lifecycle under load:
 *   1. Login as host + guest
 *   2. Create session on a rotating app
 *   3. Invite guest
 *   4. Guest joins
 *   5. Host POSTs state
 *   6. Guest POSTs state
 *   7. Host reads state (should see guest's update)
 *   8. Update permissions (EDITOR → VIEWER)
 *   9. Save session state
 *  10. Guest checks notifications
 *  11. Dismiss notification
 *  12. List host's sessions
 *
 * Measures per-operation latency so you can identify bottlenecks in the
 * session management layer vs the state relay layer.
 *
 * Ramps 1 → 10 → 30 → 50 → 20 VUs over 5 minutes.
 *
 * Custom metrics (tagged with operation and app_name):
 *   lifecycle_op_ms   — per-operation response time
 *   lifecycle_errors  — error rate
 *   lifecycle_ops     — total operations completed
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import {
  API, APPS, USERS, login, authHeaders, appForVU, healthCheck,
  createSession, joinSession, postState, getState, saveSessionState,
} from './config.js';

const opMs     = new Trend('lifecycle_op_ms', true);
const errors   = new Rate('lifecycle_errors');
const opsTotal = new Counter('lifecycle_ops');

export const options = {
  scenarios: {
    lifecycle: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '1m',  target: 30 },
        { duration: '1m',  target: 50 },
        { duration: '1m',  target: 30 },
        { duration: '30s', target: 5 },
      ],
    },
  },
  thresholds: {
    'lifecycle_errors':  ['rate<0.25'],
    'http_req_duration': ['p(95)<15000'],
  },
};

function trackOp(res, operation, appName) {
  const tags = { operation, app_name: appName };
  opMs.add(res.timings.duration, tags);
  const ok = res.status >= 200 && res.status < 300;
  errors.add(!ok, tags);
  opsTotal.add(1, tags);
  return ok;
}

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  return {};
}

export default function () {
  const app = appForVU(__VU, __ITER);
  const appTag = app.appName;

  const hostUser  = USERS[__VU % USERS.length];
  const guestUser = USERS[(__VU + 1) % USERS.length];

  group(`lifecycle_${appTag}`, function () {
    // 1. Login as host
    const hostToken = login(hostUser);
    if (!hostToken) { errors.add(true); sleep(1); return; }

    // 2. Login as guest
    const guestToken = login(guestUser);
    if (!guestToken) { errors.add(true); sleep(1); return; }

    // 3. Create session
    const t1 = Date.now();
    const session = createSession(
      hostToken, app.id, `lc-${appTag}-${__VU}-${__ITER}-${Date.now()}`,
    );
    if (!session) { errors.add(true); sleep(1); return; }
    opMs.add(Date.now() - t1, { operation: 'create_session', app_name: appTag });
    opsTotal.add(1, { operation: 'create_session', app_name: appTag });

    // 4. Invite guest
    const inviteRes = http.post(
      `${API}/collab/${session.id}/invite`,
      JSON.stringify({ username: guestUser, permission: 'EDITOR' }),
      { headers: authHeaders(hostToken), tags: { operation: 'invite', app_name: appTag } },
    );
    trackOp(inviteRes, 'invite', appTag);

    // 5. Guest joins
    const t3 = Date.now();
    const joinRes = joinSession(guestToken, session.id);
    if (joinRes) {
      opMs.add(Date.now() - t3, { operation: 'join_session', app_name: appTag });
      opsTotal.add(1, { operation: 'join_session', app_name: appTag });
    }

    // 6. Host posts state
    const hostPayload = app.payload(__VU, __ITER);
    hostPayload.sender = hostUser;
    const hostPostRes = postState(hostToken, session.id, hostPayload, { app_name: appTag });
    trackOp(hostPostRes, 'host_post_state', appTag);

    sleep(0.3);

    // 7. Guest posts state
    const guestPayload = app.payload(__VU + 100, __ITER);
    guestPayload.sender = guestUser;
    const guestPostRes = postState(guestToken, session.id, guestPayload, { app_name: appTag });
    trackOp(guestPostRes, 'guest_post_state', appTag);

    // 8. Host reads state
    const getRes = getState(hostToken, session.id, { app_name: appTag });
    trackOp(getRes, 'get_state', appTag);

    // 9. Update permissions: demote guest to VIEWER
    const permRes = http.put(
      `${API}/collab/${session.id}/permissions`,
      JSON.stringify({ username: guestUser, permission: 'VIEWER' }),
      { headers: authHeaders(hostToken), tags: { operation: 'update_permission', app_name: appTag } },
    );
    trackOp(permRes, 'update_permission', appTag);

    // 10. Save session state
    sleep(0.5);
    const saveRes = saveSessionState(hostToken, session.id, `lc-save-${__VU}-${__ITER}`);
    trackOp(saveRes, 'save_session', appTag);

    // 11. Guest checks notifications
    const notifRes = http.get(`${API}/collab/notifications`, {
      headers: authHeaders(guestToken),
      tags: { operation: 'list_notifications', app_name: appTag },
    });
    trackOp(notifRes, 'list_notifications', appTag);

    // 12. Dismiss first notification if any
    if (notifRes.status === 200) {
      const notifs = JSON.parse(notifRes.body);
      if (notifs.length > 0) {
        const dismissRes = http.post(
          `${API}/collab/notifications/${notifs[0].id}/dismiss`,
          null,
          { headers: authHeaders(guestToken), tags: { operation: 'dismiss_notification', app_name: appTag } },
        );
        trackOp(dismissRes, 'dismiss_notification', appTag);
      }
    }

    // 13. List host's sessions
    const listRes = http.get(`${API}/collab`, {
      headers: authHeaders(hostToken),
      tags: { operation: 'list_sessions', app_name: appTag },
    });
    trackOp(listRes, 'list_sessions', appTag);

    check(null, {
      [`${appTag} lifecycle complete`]: () => true,
    });
  });

  sleep(0.5);
}
