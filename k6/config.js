/**
 * Shared configuration for all k6 benchmarks.
 *
 * Set BASE_URL via environment:
 *   k6 run -e BASE_URL=http://server:30001 test.js
 *
 * Architecture note:
 *   REST  — POST state → Spring Boot → Plumber → Redis → GET state
 *   Kafka — POST state → Kafka input → R consumer → Kafka output → GET state
 *   Both expose identical /api/collab/{sessionId}/state endpoints.
 */

import http from 'k6/http';

// ---------------------------------------------------------------------------
// URLs
// ---------------------------------------------------------------------------
export const BASE_URL = __ENV.BASE_URL || 'http://localhost:4201';
export const API      = `${BASE_URL}/api`;

// ---------------------------------------------------------------------------
// Seeded users (from DataInitializer). All share password "password".
// 20 users — enough to avoid per-user caching artifacts at 100 VUs.
// ---------------------------------------------------------------------------
export const PASSWORD = 'password';
export const USERS    = [
  'alice', 'bob', 'charlie', 'diana', 'eve',
  'frank', 'grace', 'heidi', 'ivan', 'judy',
  'karl', 'laura', 'mallory', 'niaj', 'oscar',
  'peggy', 'quinn', 'rupert', 'sybil', 'trent',
];

// ---------------------------------------------------------------------------
// App definitions. IDs match the DataInitializer insertion order (both REST
// and Kafka use the same order). The appName field is the routing key used
// in the state relay JSON body (maps to APP_ROUTES in REST, or consumed
// by the R Plumber worker in Kafka).
//
// Each payload function returns a realistic state object for that app.
// ---------------------------------------------------------------------------
export const APPS = [
  {
    id: 1,
    name: 'Collaborative Calculator',
    appName: 'Calculator',
    payload: (vu, iter) => ({
      appName: 'Calculator',
      num1: 10 + vu,
      num2: 20 + iter,
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 2,
    name: 'Visual Analytics',
    appName: 'Analytics',
    payload: (vu, iter) => ({
      appName: 'Analytics',
      dataset: 'iris',
      x_var: 'Sepal.Length',
      y_var: 'Sepal.Width',
      color_var: 'Species',
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 3,
    name: 'Advanced Visual Analytics',
    appName: 'Advanced',
    payload: (vu, iter) => ({
      appName: 'Advanced',
      dataset: 'mtcars',
      x_var: 'mpg',
      y_var: 'hp',
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 4,
    name: 'Data Exchange',
    appName: 'DataExchange',
    payload: (vu, iter) => ({
      appName: 'DataExchange',
      text: `benchmark_row_${vu}_${iter}`,
      operation: 'toupper',
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 5,
    name: 'Monte Carlo Simulator',
    appName: 'MonteCarlo',
    payload: (vu, iter) => ({
      appName: 'MonteCarlo',
      command: 'START_SIMULATION',
      n_simulations: 1000,
      distribution: 'normal',
      mean: 0,
      sd: 1,
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 6,
    name: 'Geospatial Editor',
    appName: 'Geospatial',
    payload: (vu, iter) => ({
      appName: 'Geospatial',
      type: 'NEW_SENSOR',
      lat: 48.137 + vu * 0.001,
      lng: 11.576 + iter * 0.001,
      sensor_type: 'temperature',
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 7,
    name: 'Climate Anomaly Detector',
    appName: 'ClimateAnomaly',
    payload: (vu, iter) => ({
      appName: 'ClimateAnomaly',
      action: 'ANALYZE_CLIMATE',
      file: 'bench-climate-data.csv',
      station_id: `ST_${vu}`,
      threshold: 2.5,
      window_size: 30,
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
  {
    id: 8,
    name: 'Habitat Suitability AI',
    appName: 'MLTrainer',
    payload: (vu, iter) => ({
      appName: 'MLTrainer',
      command: 'TRAIN_MODEL',
      trees: 500,
      mtry: 2,
      sender: `user_${vu}`,
      timestamp: Date.now() / 1000,
    }),
  },
];

// ---------------------------------------------------------------------------
// Per-app thresholds (calibrate by running 00-baseline.js, then set to 5×
// the baseline median). Values are in milliseconds unless noted.
//
// After running the baseline:
//   k6 run -e BASE_URL=http://... --summary-export=k6/results/baseline.json k6/00-baseline.js
// Read baseline_relay_ms, baseline_post_ms, baseline_save_ms per app_name
// and multiply the median by 5 to fill in these values.
// ---------------------------------------------------------------------------
export const APP_THRESHOLDS = {
  Calculator:     { relay: 5000,  post: 3000,  save: 3000,  restore: 3000,  propagation: 5000,  lifecycle: 3000  },
  Analytics:      { relay: 5000,  post: 3000,  save: 3000,  restore: 3000,  propagation: 5000,  lifecycle: 3000  },
  Advanced:       { relay: 5000,  post: 3000,  save: 3000,  restore: 3000,  propagation: 5000,  lifecycle: 3000  },
  DataExchange:   { relay: 5000,  post: 3000,  save: 3000,  restore: 3000,  propagation: 5000,  lifecycle: 3000  },
  MonteCarlo:     { relay: 15000, post: 10000, save: 5000,  restore: 3000,  propagation: 15000, lifecycle: 10000 },
  Geospatial:     { relay: 10000, post: 5000,  save: 5000,  restore: 3000,  propagation: 10000, lifecycle: 5000  },
  ClimateAnomaly: { relay: 30000, post: 20000, save: 10000, restore: 5000,  propagation: 30000, lifecycle: 20000 },
  MLTrainer:      { relay: 60000, post: 45000, save: 10000, restore: 5000,  propagation: 60000, lifecycle: 45000 },
};

// Build k6 threshold entries for a metric tagged with {app_name:X}.
// Returns an object like: { 'metric{app_name:Calculator}': ['p(95)<5000'], ... }
export function perAppThresholds(metricName, thresholdKey, op = 'p(95)') {
  const result = {};
  for (const [app, limits] of Object.entries(APP_THRESHOLDS)) {
    const limit = limits[thresholdKey];
    if (limit !== undefined) {
      result[`${metricName}{app_name:${app}}`] = [`${op}<${limit}`];
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Login and return JWT token, or null on failure. */
export function login(username) {
  const res = http.post(
    `${API}/auth/login`,
    JSON.stringify({ username, password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' }, tags: { operation: 'login' } },
  );
  if (res.status !== 200) return null;
  return JSON.parse(res.body).token;
}

/** Build Authorization + Content-Type headers from a JWT token. */
export function authHeaders(token) {
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };
}

/** Pick a user deterministically from VU number. */
export function userForVU(vu) {
  return USERS[vu % USERS.length];
}

/** Pick an app deterministically from VU + iteration. */
export function appForVU(vu, iter) {
  return APPS[(vu + iter) % APPS.length];
}

/** Create a collaboration session, return session object or null. */
export function createSession(token, appId, name) {
  const res = http.post(
    `${API}/collab/start`,
    JSON.stringify({ name, appId }),
    { headers: authHeaders(token), tags: { operation: 'create_session' } },
  );
  if (res.status !== 200) return null;
  return JSON.parse(res.body);
}

/** Join an existing session, return session object or null. */
export function joinSession(token, sessionId) {
  const res = http.post(
    `${API}/collab/join`,
    JSON.stringify({ sessionId }),
    { headers: authHeaders(token), tags: { operation: 'join_session' } },
  );
  if (res.status !== 200) return null;
  return JSON.parse(res.body);
}

/** POST state to the relay endpoint and return the response. */
export function postState(token, sessionId, payload, extraTags) {
  return http.post(
    `${API}/collab/${sessionId}/state`,
    JSON.stringify(payload),
    { headers: authHeaders(token), tags: Object.assign({ operation: 'post_state' }, extraTags || {}) },
  );
}

/** GET current live state for a session. */
export function getState(token, sessionId, extraTags) {
  return http.get(`${API}/collab/${sessionId}/state`, {
    headers: authHeaders(token),
    tags: Object.assign({ operation: 'get_state' }, extraTags || {}),
  });
}

/** Save current session state to the database (snapshot). */
export function saveSessionState(token, sessionId, name) {
  return http.post(
    `${API}/collab/${sessionId}/save`,
    JSON.stringify({ name }),
    { headers: authHeaders(token), tags: { operation: 'save_session_state' } },
  );
}

/** Save state via the solo /api/states endpoint. */
export function saveSoloState(token, appId, name, sessionId) {
  return http.post(
    `${API}/states`,
    JSON.stringify({ appId, name, sessionId }),
    { headers: authHeaders(token), tags: { operation: 'save_solo_state' } },
  );
}

/** Get saved states for the authenticated user. */
export function getMySavedStates(token, appId) {
  const url = appId ? `${API}/states?appId=${appId}` : `${API}/states`;
  return http.get(url, {
    headers: authHeaders(token),
    tags: { operation: 'list_saved_states' },
  });
}

/** Restore a saved state by ID into a session. */
export function restoreState(token, stateId, sessionId) {
  const qs = sessionId ? `?sessionId=${sessionId}` : '';
  return http.post(`${API}/states/${stateId}/restore${qs}`, null, {
    headers: authHeaders(token),
    tags: { operation: 'restore_state' },
  });
}

/**
 * Verify the API is reachable and apps are seeded. Call from setup().
 * Returns { ok, appCount, error }.
 */
export function healthCheck() {
  try {
    const token = login('alice');
    if (!token) return { ok: false, error: 'Login failed for alice' };

    const res = http.get(`${API}/apps`, {
      headers: authHeaders(token),
      tags: { operation: 'health_check' },
    });
    if (res.status !== 200) return { ok: false, error: `GET /api/apps returned ${res.status}` };

    const apps = JSON.parse(res.body);
    return { ok: true, appCount: apps.length };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}
