/**
 * Benchmark 3 — Save & Restore Latency
 *
 * Measures the full save-to-database and restore-from-database cycle
 * for each of the 8 apps:
 *
 *   1. Create session → POST state with unique marker (populate pipeline)
 *   2. POST /api/collab/{sessionId}/save  → measure DB write time
 *   3. GET  /api/states                   → measure DB read time
 *   4. POST /api/states/{id}/restore      → measure restore-to-session time
 *   5. GET  /api/collab/{sessionId}/state → verify restored state contains marker
 *
 * Custom metrics (tagged with app_name):
 *   save_to_db_ms      — time to persist current state to PostgreSQL
 *   list_states_ms     — time to list saved states from PostgreSQL
 *   restore_from_db_ms — time to restore a saved state back into the session
 *   restore_verify_ms  — time until restored state is visible via GET
 *   save_restore_ok    — successful full cycles
 *   save_restore_fail  — failed cycles
 */

import { check, sleep, group } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import {
  APPS, login, userForVU, healthCheck,
  createSession, postState, getState,
  saveSessionState, getMySavedStates, restoreState,
} from './config.js';

const saveToDbMs      = new Trend('save_to_db_ms', true);
const listStatesMs    = new Trend('list_states_ms', true);
const restoreDbMs     = new Trend('restore_from_db_ms', true);
const restoreVerifyMs = new Trend('restore_verify_ms', true);
const saveRestoreOk   = new Counter('save_restore_ok');
const saveRestoreFail = new Counter('save_restore_fail');

export const options = {
  scenarios: {
    save_restore: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '30s', target: 3 },
        { duration: '1m',  target: 8 },
        { duration: '1m',  target: 15 },
        { duration: '1m',  target: 8 },
        { duration: '30s', target: 1 },
      ],
    },
  },
  thresholds: {
    'save_to_db_ms':      ['p(95)<5000'],
    'restore_from_db_ms': ['p(95)<5000'],
    'http_req_failed':    ['rate<0.2'],
  },
};

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);
  return {};
}

export default function () {
  const username = userForVU(__VU);
  const token = login(username);
  if (!token) { saveRestoreFail.add(1); return; }

  for (const app of APPS) {
    const tags = { app_name: app.appName };

    group(`save_restore_${app.appName}`, function () {
      // 1. Create session and populate state with a unique marker
      const session = createSession(
        token, app.id, `sr-${app.appName}-${__VU}-${__ITER}-${Date.now()}`,
      );
      if (!session) { saveRestoreFail.add(1, tags); return; }

      const marker = `sr_${__VU}_${__ITER}_${Date.now()}`;
      const payload = app.payload(__VU, __ITER);
      payload._marker = marker;
      payload.sender = username;
      const postRes = postState(token, session.id, payload, tags);
      if (postRes.status !== 200) { saveRestoreFail.add(1, tags); return; }

      // Wait for state to settle in the pipeline
      sleep(1.5);

      // 2. Save to DB
      const saveName = `bench-save-${app.appName}-${__VU}-${__ITER}`;
      const t1 = Date.now();
      const saveRes = saveSessionState(token, session.id, saveName);
      saveToDbMs.add(Date.now() - t1, tags);

      if (saveRes.status !== 200) {
        saveRestoreFail.add(1, tags);
        return;
      }

      // 3. List saved states and find the one we just saved
      const t2 = Date.now();
      const listRes = getMySavedStates(token, app.id);
      listStatesMs.add(Date.now() - t2, tags);

      if (listRes.status !== 200) { saveRestoreFail.add(1, tags); return; }

      const states = JSON.parse(listRes.body);
      const saved = states.find(s => s.name === saveName);
      if (!saved) { saveRestoreFail.add(1, tags); return; }

      // 4. Restore from DB back into the session
      const t3 = Date.now();
      const restoreRes = restoreState(token, saved.id, session.id);
      restoreDbMs.add(Date.now() - t3, tags);

      if (restoreRes.status !== 200) { saveRestoreFail.add(1, tags); return; }

      // 5. Verify restored state appears in GET and contains our marker
      const t4 = Date.now();
      let verified = false;
      for (let i = 0; i < 20; i++) {
        const getRes = getState(token, session.id, tags);
        if (getRes.status === 200 && getRes.body && getRes.body.includes(marker)) {
          verified = true;
          break;
        }
        sleep(0.25);
      }
      restoreVerifyMs.add(Date.now() - t4, tags);

      if (verified) {
        saveRestoreOk.add(1, tags);
      } else {
        saveRestoreFail.add(1, tags);
      }

      check(null, {
        [`${app.appName} save+restore ok`]: () => verified,
      });
    });

    sleep(0.5);
  }
}
