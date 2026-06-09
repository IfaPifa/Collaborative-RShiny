/**
 * Benchmark 6 — Cross-Contamination (Session Isolation)
 *
 * Creates 60 concurrent collaborative sessions (spread across all 8 apps)
 * and verifies that state from one session NEVER leaks into another.
 *
 * Each VU:
 *   1. Creates 2 sessions on the SAME app (session A and session B)
 *   2. Saves 15 uniquely tagged states to each session
 *   3. Verifies session A's live state contains ONLY its own markers
 *   4. Verifies session B's live state contains ONLY its own markers
 *   5. Saves final state to DB and cross-checks DB-level isolation
 *
 * 30 VUs × 2 sessions = 60 concurrent sessions.
 * 60 sessions × 15 saves = 900 state writes being checked for isolation.
 *
 * Custom metrics (tagged with app_name):
 *   contamination_events — number of leaked states (should be 0)
 *   isolation_checks     — total cross-checks performed
 *   isolation_ok         — sessions that passed isolation check
 */

import { check, sleep, group } from 'k6';
import { Counter } from 'k6/metrics';
import {
  APPS, login, userForVU, healthCheck,
  createSession, postState, getState, saveSessionState, getMySavedStates,
} from './config.js';

const contaminations  = new Counter('contamination_events');
const isolationChecks = new Counter('isolation_checks');
const isolationOk     = new Counter('isolation_ok');

const SAVES_PER_SESSION = 15;

export const options = {
  scenarios: {
    isolation: {
      executor: 'per-vu-iterations',
      vus: 30,
      iterations: 1,
    },
  },
  thresholds: {
    'contamination_events': ['count==0'],
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

  const app = APPS[__VU % APPS.length];
  const tags = { app_name: app.appName };
  const runId = `${__VU}_${Date.now()}`;

  group(`isolation_${app.appName}`, function () {
    const sessionA = createSession(token, app.id, `iso-A-${app.appName}-${runId}`);
    const sessionB = createSession(token, app.id, `iso-B-${app.appName}-${runId}`);
    if (!sessionA || !sessionB) return;

    const markerA = `ONLY_A_${runId}`;
    const markerB = `ONLY_B_${runId}`;

    // Interleave writes to both sessions
    for (let i = 0; i < SAVES_PER_SESSION; i++) {
      const payloadA = app.payload(__VU, i);
      payloadA._marker = `${markerA}_${i}`;
      payloadA.sender = username;
      postState(token, sessionA.id, payloadA, tags);
      sleep(0.1);

      const payloadB = app.payload(__VU, i + 100);
      payloadB._marker = `${markerB}_${i}`;
      payloadB.sender = username;
      postState(token, sessionB.id, payloadB, tags);
      sleep(0.1);
    }

    sleep(3);

    // Cross-check live state
    const stateA = getState(token, sessionA.id, tags);
    const stateB = getState(token, sessionB.id, tags);

    if (stateA.status === 200 && stateA.body) {
      isolationChecks.add(1, tags);
      const aContainsB = stateA.body.includes('ONLY_B_');
      if (aContainsB) {
        contaminations.add(1, tags);
        console.error(`CONTAMINATION: Session A (${sessionA.id}) contains B's marker`);
      } else {
        isolationOk.add(1, tags);
      }
      check(null, { [`${app.appName} session A clean`]: () => !aContainsB });
    }

    if (stateB.status === 200 && stateB.body) {
      isolationChecks.add(1, tags);
      const bContainsA = stateB.body.includes('ONLY_A_');
      if (bContainsA) {
        contaminations.add(1, tags);
        console.error(`CONTAMINATION: Session B (${sessionB.id}) contains A's marker`);
      } else {
        isolationOk.add(1, tags);
      }
      check(null, { [`${app.appName} session B clean`]: () => !bContainsA });
    }

    // DB-level isolation check
    saveSessionState(token, sessionA.id, `iso-final-A-${runId}`);
    saveSessionState(token, sessionB.id, `iso-final-B-${runId}`);
    sleep(1);

    const allStates = getMySavedStates(token, app.id);
    if (allStates.status === 200) {
      const stateList = JSON.parse(allStates.body);
      const finalA = stateList.find(s => s.name === `iso-final-A-${runId}`);
      const finalB = stateList.find(s => s.name === `iso-final-B-${runId}`);

      if (finalA && finalA.stateData) {
        isolationChecks.add(1, tags);
        const dbLeakA = finalA.stateData.includes('ONLY_B_');
        if (dbLeakA) contaminations.add(1, tags);
        else isolationOk.add(1, tags);
        check(null, { [`${app.appName} DB save A clean`]: () => !dbLeakA });
      }

      if (finalB && finalB.stateData) {
        isolationChecks.add(1, tags);
        const dbLeakB = finalB.stateData.includes('ONLY_A_');
        if (dbLeakB) contaminations.add(1, tags);
        else isolationOk.add(1, tags);
        check(null, { [`${app.appName} DB save B clean`]: () => !dbLeakB });
      }
    }

    console.log(
      `VU${__VU} ${app.appName}: isolation check complete (${sessionA.id}, ${sessionB.id})`,
    );
  });
}
