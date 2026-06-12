/**
 * Benchmark 0 — Per-App Baseline (Single User, No Load)
 *
 * Measures each app's natural response time with 1 VU and no concurrency.
 * Results are used to calibrate per-app thresholds for benchmarks 01–09.
 *
 * For each of the 8 apps, performs:
 *   1. Login
 *   2. Create session
 *   3. POST state (full pipeline: Spring → Plumber → Redis)
 *   4. GET state (read from Redis)
 *   5. Poll until processed state appears (relay round-trip)
 *   6. Save to DB
 *   7. Restore from DB
 *
 * Repeats 5 times per app to get stable medians.
 *
 * Output: per-app metrics tagged with app_name. After running, use the
 * summary JSON to set thresholds at 5× the baseline median.
 *
 * Usage:
 *   k6 run -e BASE_URL=http://localhost:30001 \
 *     --summary-export=k6/results/baseline.json k6/00-baseline.js
 */

import { check, sleep, group } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import {
  APPS, login, userForVU, healthCheck,
  createSession, postState, getState,
  saveSessionState, getMySavedStates, restoreState,
} from './config.js';

// Per-app metrics
const baselinePostMs    = new Trend('baseline_post_ms', true);
const baselineGetMs     = new Trend('baseline_get_ms', true);
const baselineRelayMs   = new Trend('baseline_relay_ms', true);
const baselineSaveMs    = new Trend('baseline_save_ms', true);
const baselineRestoreMs = new Trend('baseline_restore_ms', true);
const baselineTotalMs   = new Trend('baseline_total_ms', true);
const baselineOk        = new Counter('baseline_ok');
const baselineFail      = new Counter('baseline_fail');

const REPEATS = 5;

export const options = {
  scenarios: {
    baseline: {
      executor: 'per-vu-iterations',
      vus: 1,
      iterations: 1,
      maxDuration: '30m',
    },
  },
  // No thresholds — this is a measurement run
};

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  console.log(`Health check passed. ${hc.appCount} apps registered.`);
  console.log('Running baseline: 1 VU, 5 repeats per app, no concurrency.');
  return {};
}

export default function () {
  const username = userForVU(__VU);
  const token = login(username);
  if (!token) {
    console.error('Login failed');
    return;
  }

  for (const app of APPS) {
    const tags = { app_name: app.appName };

    for (let rep = 0; rep < REPEATS; rep++) {
      group(`baseline_${app.appName}_rep${rep}`, function () {
        const totalStart = Date.now();

        // 1. Create session
        const session = createSession(
          token, app.id,
          `baseline-${app.appName}-${rep}-${Date.now()}`,
        );
        if (!session) {
          baselineFail.add(1, tags);
          console.error(`${app.appName} rep${rep}: session creation failed`);
          return;
        }

        // 2. POST state with marker
        const marker = `bl_${app.appName}_${rep}_${Date.now()}`;
        const payload = app.payload(__VU, rep);
        payload._marker = marker;
        payload.sender = username;

        const postStart = Date.now();
        const postRes = postState(token, session.id, payload, tags);
        const postMs = Date.now() - postStart;
        baselinePostMs.add(postMs, tags);

        if (postRes.status !== 200) {
          baselineFail.add(1, tags);
          console.error(`${app.appName} rep${rep}: POST failed (${postRes.status})`);
          return;
        }

        // 3. GET state (raw read, no waiting for marker)
        const getStart = Date.now();
        const getRes = getState(token, session.id, tags);
        const getMs = Date.now() - getStart;
        baselineGetMs.add(getMs, tags);

        // 4. Poll until marker appears (relay round-trip)
        const relayStart = Date.now();
        let found = false;
        for (let i = 0; i < 120; i++) {
          const pollRes = getState(token, session.id, tags);
          if (pollRes.status === 200 && pollRes.body && pollRes.body.includes(marker)) {
            found = true;
            break;
          }
          sleep(0.5);
        }
        const relayMs = Date.now() - relayStart;
        baselineRelayMs.add(relayMs, tags);

        if (!found) {
          baselineFail.add(1, tags);
          console.error(`${app.appName} rep${rep}: relay timeout after ${relayMs}ms`);
          return;
        }

        // 5. Save to DB
        const saveName = `bl-save-${app.appName}-${rep}-${Date.now()}`;
        const saveStart = Date.now();
        const saveRes = saveSessionState(token, session.id, saveName);
        const saveMs = Date.now() - saveStart;
        baselineSaveMs.add(saveMs, tags);

        if (saveRes.status !== 200) {
          baselineFail.add(1, tags);
          console.error(`${app.appName} rep${rep}: save failed (${saveRes.status})`);
          return;
        }

        // 6. Restore from DB
        const listRes = getMySavedStates(token, app.id);
        if (listRes.status !== 200) {
          baselineFail.add(1, tags);
          return;
        }
        const states = JSON.parse(listRes.body);
        const saved = states.find(s => s.name === saveName);
        if (!saved) {
          baselineFail.add(1, tags);
          console.error(`${app.appName} rep${rep}: saved state not found in list`);
          return;
        }

        const restoreStart = Date.now();
        const restoreRes = restoreState(token, saved.id, session.id);
        const restoreMs = Date.now() - restoreStart;
        baselineRestoreMs.add(restoreMs, tags);

        const totalMs = Date.now() - totalStart;
        baselineTotalMs.add(totalMs, tags);

        baselineOk.add(1, tags);

        console.log(
          `${app.appName} rep${rep}: post=${postMs}ms relay=${relayMs}ms save=${saveMs}ms restore=${restoreMs}ms total=${totalMs}ms`,
        );
      });

      sleep(1); // Cool down between repeats
    }

    sleep(2); // Cool down between apps
  }

  // Print summary
  console.log('\n=== BASELINE COMPLETE ===');
  console.log('Use --summary-export to get per-app medians for threshold calibration.');
  console.log('Set thresholds at 5x the baseline median for each app.');
}
