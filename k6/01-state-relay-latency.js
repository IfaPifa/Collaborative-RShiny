/**
 * Benchmark 1 — Per-App State Relay Latency
 *
 * For EACH of the 8 Shiny apps, measures the round-trip time of:
 *   POST /api/collab/{sessionId}/state  (send state through the pipeline)
 *   GET  /api/collab/{sessionId}/state  (poll until updated state appears)
 *
 * Produces per-app tagged metrics so you can plot latency distributions
 * per app (e.g. Calculator vs Monte Carlo vs ML Trainer).
 *
 * Ramps 1 → 5 → 10 → 20 → 5 VUs over 4 minutes.
 * Each VU iterates through all 8 apps sequentially per iteration.
 *
 * Custom metrics (all tagged with app_name):
 *   relay_post_ms   — time for the POST to return
 *   relay_poll_ms   — time from POST return until GET shows updated state
 *   relay_total_ms  — end-to-end POST + poll
 *   relay_success   — counter of successful round-trips
 *   relay_failure   — counter of failed round-trips
 */

import { check, sleep, group } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import {
  APPS, login, userForVU, createSession, postState, getState, healthCheck,
  perAppThresholds, loadBucket,
} from './config.js';

const relayPostMs  = new Trend('relay_post_ms', true);
const relayPollMs  = new Trend('relay_poll_ms', true);
const relayTotalMs = new Trend('relay_total_ms', true);
const relaySuccess = new Counter('relay_success');
const relayFailure = new Counter('relay_failure');

// Client-side poll interval (ms). REST has no server push, so the observed
// relay latency partly reflects how often we poll. Sweep this across runs
// (e.g. POLL_MS=100/250/500/1000) to produce the latency/load trade-off curve
// rather than a single arbitrary point. Default 250 preserves prior behaviour.
const POLL_MS = Number(__ENV.POLL_MS || 250);
// Keep the total poll deadline constant regardless of interval so a tighter
// interval polls more often within the same window instead of timing out
// sooner. Prior budget was 40 iters * 250ms = 10s.
const POLL_BUDGET_MS = Number(__ENV.POLL_BUDGET_MS || 10000);
const POLL_MAX_ITERS = Math.max(1, Math.ceil(POLL_BUDGET_MS / POLL_MS));

export const options = {
  scenarios: {
    relay_latency: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '30s', target: 5 },
        { duration: '1m',  target: 10 },
        { duration: '1m',  target: 20 },
        { duration: '1m',  target: 10 },
        { duration: '30s', target: 1 },
      ],
    },
  },
  thresholds: Object.assign(
    { 'http_req_failed': ['rate<0.15'] },
    perAppThresholds('relay_total_ms', 'relay'),
  ),
};

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  console.log(`Health check passed. ${hc.appCount} apps registered.`);
  return {};
}

export default function () {
  const username = userForVU(__VU);
  const token = login(username);
  if (!token) { relayFailure.add(1); return; }

  for (const app of APPS) {
    // Tag with poll_ms so a sweep's runs stay distinguishable in the results.
    const tags = { app_name: app.appName, vu_bucket: loadBucket(), poll_ms: String(POLL_MS) };

    group(`relay_${app.appName}`, function () {
      const session = createSession(
        token, app.id, `relay-${app.appName}-${__VU}-${__ITER}-${Date.now()}`,
      );
      if (!session) {
        relayFailure.add(1, tags);
        return;
      }

      const payload = app.payload(__VU, __ITER);
      const marker = `m_${__VU}_${__ITER}_${Date.now()}`;
      payload._marker = marker;
      payload.sender = username;

      // POST state
      const t0 = Date.now();
      const postRes = postState(token, session.id, payload, tags);
      const postElapsed = Date.now() - t0;
      relayPostMs.add(postElapsed, tags);

      if (postRes.status !== 200) {
        relayFailure.add(1, tags);
        return;
      }

      // Poll GET until marker appears
      let found = false;
      const pollStart = Date.now();
      for (let i = 0; i < POLL_MAX_ITERS; i++) {
        const getRes = getState(token, session.id, tags);
        if (getRes.status === 200 && getRes.body && getRes.body.includes(marker)) {
          found = true;
          break;
        }
        sleep(POLL_MS / 1000);
      }
      const pollElapsed = Date.now() - pollStart;
      const totalElapsed = Date.now() - t0;

      relayPollMs.add(pollElapsed, tags);
      relayTotalMs.add(totalElapsed, tags);

      if (found) {
        relaySuccess.add(1, tags);
      } else {
        relayFailure.add(1, tags);
      }

      check(null, {
        [`${app.appName} relay ok`]: () => found,
      });
    });

    sleep(0.5);
  }
}
