/**
 * Benchmark 8 — Multi-User Collaboration Scaling
 *
 * Measures how propagation latency degrades as more users join
 * the same collaborative session. This is a key differentiator
 * between REST (polling) and Kafka (pub/sub) architectures.
 *
 * For each group size (3, 5, 10 participants):
 *   1. Host creates a session
 *   2. N-1 guests join the session
 *   3. Host POSTs a state update
 *   4. ALL guests poll until they see the update
 *   5. Measure: time until the LAST guest sees the update
 *
 * This captures fan-out latency — how well each architecture
 * distributes state to many concurrent readers.
 *
 * Custom metrics (tagged with group_size, app_name):
 *   multi_propagation_all_ms  — time until ALL guests see the update
 *   multi_propagation_first_ms — time until FIRST guest sees the update
 *   multi_success              — all guests received the update
 *   multi_timeout              — at least one guest missed the update
 */

import { check, sleep, group } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import {
  APPS, USERS, login, createSession, joinSession,
  postState, getState, healthCheck, perAppThresholds,
} from './config.js';

const multiPropAll   = new Trend('multi_propagation_all_ms', true);
const multiPropFirst = new Trend('multi_propagation_first_ms', true);
const multiSuccess   = new Counter('multi_success');
const multiTimeout   = new Counter('multi_timeout');

const GROUP_SIZES = [3, 5, 10];

export const options = {
  scenarios: {
    multi_user: {
      executor: 'per-vu-iterations',
      vus: 3,           // one VU per group size
      iterations: 8,    // one iteration per app
      maxDuration: '5m',
    },
  },
  thresholds: Object.assign(
    { 'http_req_failed': ['rate<0.3'] },
    perAppThresholds('multi_propagation_all_ms', 'propagation'),
  ),
};

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  return {};
}

export default function () {
  const groupSize = GROUP_SIZES[__VU % GROUP_SIZES.length];
  const app = APPS[__ITER % APPS.length];
  const tags = { app_name: app.appName, group_size: String(groupSize) };

  group(`multi_${groupSize}users_${app.appName}`, function () {
    // 1. Login as host
    const hostUser = USERS[0];
    const hostToken = login(hostUser);
    if (!hostToken) { multiTimeout.add(1, tags); return; }

    // 2. Create session
    const session = createSession(
      hostToken, app.id,
      `multi-${groupSize}-${app.appName}-${__VU}-${__ITER}-${Date.now()}`,
    );
    if (!session) { multiTimeout.add(1, tags); return; }

    // 3. Login and join as N-1 guests
    const guestTokens = [];
    for (let i = 1; i < groupSize; i++) {
      const guestUser = USERS[i % USERS.length];
      const guestToken = login(guestUser);
      if (!guestToken) continue;
      const joined = joinSession(guestToken, session.id);
      if (joined) guestTokens.push(guestToken);
    }

    if (guestTokens.length === 0) {
      multiTimeout.add(1, tags);
      return;
    }

    // 4. Host POSTs state with a unique marker
    const marker = `multi_${groupSize}_${__VU}_${__ITER}_${Date.now()}`;
    const payload = app.payload(__VU, __ITER);
    payload._marker = marker;
    payload.sender = hostUser;

    const postRes = postState(hostToken, session.id, payload, tags);
    if (postRes.status !== 200) {
      multiTimeout.add(1, tags);
      return;
    }

    // 5. All guests poll until they see the marker
    const pollStart = Date.now();
    const guestSeen = new Array(guestTokens.length).fill(false);
    let firstSeenAt = null;
    let allSeenAt = null;

    for (let attempt = 0; attempt < 60; attempt++) {
      for (let g = 0; g < guestTokens.length; g++) {
        if (guestSeen[g]) continue;
        const getRes = getState(guestTokens[g], session.id, tags);
        if (getRes.status === 200 && getRes.body && getRes.body.includes(marker)) {
          guestSeen[g] = true;
          if (!firstSeenAt) firstSeenAt = Date.now() - pollStart;
        }
      }

      if (guestSeen.every(Boolean)) {
        allSeenAt = Date.now() - pollStart;
        break;
      }
      sleep(0.25);
    }

    // 6. Record metrics
    if (firstSeenAt !== null) {
      multiPropFirst.add(firstSeenAt, tags);
    }

    if (allSeenAt !== null) {
      multiPropAll.add(allSeenAt, tags);
      multiSuccess.add(1, tags);
    } else {
      // Record partial — how long we waited
      multiPropAll.add(Date.now() - pollStart, tags);
      multiTimeout.add(1, tags);
    }

    const allSeen = guestSeen.every(Boolean);
    const seenCount = guestSeen.filter(Boolean).length;

    check(null, {
      [`${app.appName} all ${groupSize} guests see update`]: () => allSeen,
      [`${app.appName} at least one guest sees update`]: () => seenCount > 0,
    });
  });

  sleep(1);
}
