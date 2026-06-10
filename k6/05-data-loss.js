/**
 * Benchmark 5 — Data Loss Under Load
 *
 * For each of the 8 apps, sends N uniquely tagged state saves in rapid
 * succession, then verifies all N are retrievable from the database.
 * The difference = data loss rate.
 *
 * Each VU:
 *   1. Creates a session per app
 *   2. Fires BATCH_SIZE rapid state POSTs + save-to-DB calls
 *   3. Only counts saves that returned HTTP 200
 *   4. Waits for processing
 *   5. Lists saved states and counts how many survived
 *
 * Uses 15 VUs × 1 iteration each = 15 parallel users hammering all 8 apps.
 * Total saves attempted: 15 VUs × 8 apps × 30 saves = 3,600 state saves.
 *
 * Custom metrics (tagged with app_name):
 *   dataloss_sent       — total saves accepted by the API (HTTP 200)
 *   dataloss_received   — total saves confirmed in DB
 *   dataloss_lost       — total saves missing from DB
 *   dataloss_pct        — loss percentage per VU per app
 */

import { check, sleep, group } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import {
  APPS, login, userForVU, healthCheck,
  createSession, postState, saveSessionState, getMySavedStates,
} from './config.js';

const sent     = new Counter('dataloss_sent');
const received = new Counter('dataloss_received');
const lost     = new Counter('dataloss_lost');
const lossPct  = new Trend('dataloss_pct', true);

const BATCH_SIZE = 30;

export const options = {
  scenarios: {
    data_loss: {
      executor: 'per-vu-iterations',
      vus: 15,
      iterations: 1,
    },
  },
  thresholds: {
    'dataloss_pct': ['p(95)<5'],
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
  if (!token) return;

  for (const app of APPS) {
    const tags = { app_name: app.appName };
    const runId = `${__VU}_${Date.now()}`;

    group(`dataloss_${app.appName}`, function () {
      const session = createSession(
        token, app.id, `dataloss-${app.appName}-${runId}`,
      );
      if (!session) return;

      // Fire rapid state POSTs followed by save-to-DB
      const acceptedNames = [];
      for (let i = 0; i < BATCH_SIZE; i++) {
        const payload = app.payload(__VU, i);
        payload._marker = `dl_${runId}_${i}`;
        payload.sender = username;

        // POST state to populate the pipeline
        const postRes = postState(token, session.id, payload, tags);
        if (postRes.status !== 200) continue;

        // Save to DB — only count if the API accepted it
        const saveName = `dl-${app.appName}-${runId}-${i}`;
        const saveRes = saveSessionState(token, session.id, saveName);
        if (saveRes.status === 200) {
          acceptedNames.push(saveName);
          sent.add(1, tags);
        }
      }

      // Wait for all writes to flush
      sleep(5);

      // Verify: list saved states and count matches
      const listRes = getMySavedStates(token, app.id);
      if (listRes.status !== 200) {
        lost.add(acceptedNames.length, tags);
        lossPct.add(100, tags);
        return;
      }

      const savedNames = JSON.parse(listRes.body).map(s => s.name);
      let found = 0;
      let missing = 0;

      for (const name of acceptedNames) {
        if (savedNames.includes(name)) {
          found++;
          received.add(1, tags);
        } else {
          missing++;
          lost.add(1, tags);
        }
      }

      const pct = acceptedNames.length > 0
        ? (missing / acceptedNames.length) * 100
        : 0;
      lossPct.add(pct, tags);

      check(null, {
        [`${app.appName} zero data loss`]: () => missing === 0,
      });

      console.log(
        `VU${__VU} ${app.appName}: accepted=${acceptedNames.length} found=${found} lost=${missing} (${pct.toFixed(1)}%)`,
      );
    });
  }
}
