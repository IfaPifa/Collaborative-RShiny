/**
 * Benchmark 9 — WebSocket Presence & STOMP Throughput
 *
 * Measures the performance of the STOMP-over-WebSocket presence system:
 *   1. Connect to /ws-shiny via raw WebSocket (SockJS protocol)
 *   2. Send STOMP CONNECT frame
 *   3. Subscribe to /topic/presence/{sessionId}
 *   4. Send JOIN message via /app/presence.join/{sessionId}
 *   5. Measure time until the broadcast is received back
 *   6. Send LEAVE and disconnect
 *
 * This tests the real-time messaging backbone that both REST and Kafka
 * architectures share. Under load, it reveals how the Spring WebSocket
 * broker handles concurrent connections and message fan-out.
 *
 * Scenarios:
 *   - ws_connect:  Ramp 1→50 concurrent WebSocket connections
 *   - ws_fanout:   10 users per session, measure broadcast latency
 *
 * Custom metrics:
 *   ws_connect_ms       — time to establish WebSocket + STOMP handshake
 *   ws_join_roundtrip_ms — time from sending JOIN to receiving broadcast
 *   ws_connections       — total successful connections
 *   ws_messages_received — total STOMP messages received
 *   ws_errors            — connection or protocol errors
 */

import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import ws from 'k6/ws';
import { USERS, login, createSession, joinSession, healthCheck, APPS } from './config.js';

const wsConnectTime   = new Trend('ws_connect_ms', true);
const wsJoinRoundtrip = new Trend('ws_join_roundtrip_ms', true);
const wsConnections   = new Counter('ws_connections');
const wsMsgReceived   = new Counter('ws_messages_received');
const wsErrors        = new Counter('ws_errors');

export const options = {
  scenarios: {
    ws_presence: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '20s', target: 10 },
        { duration: '30s', target: 25 },
        { duration: '30s', target: 50 },
        { duration: '20s', target: 25 },
        { duration: '20s', target: 1 },
      ],
    },
  },
  thresholds: {
    'ws_connect_ms':        ['p(95)<5000'],
    'ws_join_roundtrip_ms': ['p(95)<3000'],
  },
};

export function setup() {
  const hc = healthCheck();
  if (!hc.ok) throw new Error(`Health check failed: ${hc.error}`);

  // Pre-create sessions for the test
  const sessions = [];
  const hostToken = login(USERS[0]);
  if (!hostToken) throw new Error('Cannot login as host');

  for (let i = 0; i < APPS.length; i++) {
    const session = createSession(hostToken, APPS[i].id, `ws-bench-${i}-${Date.now()}`);
    if (session) {
      sessions.push({ sessionId: session.id, appName: APPS[i].appName });
    }
  }

  if (sessions.length === 0) throw new Error('No sessions created');
  return { sessions };
}

// Build a SockJS WebSocket URL from the base HTTP URL
function buildWsUrl(baseUrl) {
  const serverId = Math.floor(Math.random() * 1000);
  const sessionId = Math.random().toString(36).substring(2, 10);
  // SockJS WebSocket transport URL
  return baseUrl
    .replace('http://', 'ws://')
    .replace('https://', 'wss://')
    + `/ws-shiny/${serverId}/${sessionId}/websocket`;
}

// Parse a STOMP frame from a SockJS message
function parseStompFrame(data) {
  // SockJS wraps messages in arrays: a["STOMP_FRAME"]
  if (data.startsWith('a[')) {
    try {
      const arr = JSON.parse(data.substring(1));
      return arr[0] || '';
    } catch (_) {
      return '';
    }
  }
  // SockJS open frame
  if (data === 'o') return '__OPEN__';
  // SockJS heartbeat
  if (data === 'h') return '__HEARTBEAT__';
  return data;
}

// Encode a STOMP frame for SockJS transport
function stompFrame(command, headers, body) {
  let frame = command + '\n';
  for (const [k, v] of Object.entries(headers || {})) {
    frame += `${k}:${v}\n`;
  }
  frame += '\n' + (body || '') + '\u0000';
  // SockJS requires JSON-encoded array
  return JSON.stringify([frame]);
}

export default function (data) {
  const baseUrl = __ENV.BASE_URL || 'http://188.245.60.172:30002';
  const session = data.sessions[__VU % data.sessions.length];
  const user = USERS[__VU % USERS.length];
  const username = typeof user === 'string' ? user : user.username || user;

  const wsUrl = buildWsUrl(baseUrl);
  const tags = { app_name: session.appName };

  const connectStart = Date.now();
  let connected = false;
  let joinSentAt = 0;
  let joinReceived = false;

  const res = ws.connect(wsUrl, {}, function (socket) {
    socket.on('open', function () {
      // SockJS sends 'o' frame on open, wait for it
    });

    socket.on('message', function (msg) {
      const frame = parseStompFrame(msg);

      if (frame === '__OPEN__') {
        // Send STOMP CONNECT
        socket.send(stompFrame('CONNECT', {
          'accept-version': '1.2,1.1,1.0',
          'heart-beat': '0,0',
        }));
        return;
      }

      if (frame === '__HEARTBEAT__') return;

      // STOMP CONNECTED response
      if (frame.startsWith('CONNECTED')) {
        connected = true;
        wsConnections.add(1);
        wsConnectTime.add(Date.now() - connectStart, tags);

        // Subscribe to presence topic
        socket.send(stompFrame('SUBSCRIBE', {
          id: 'sub-0',
          destination: `/topic/presence/${session.sessionId}`,
        }));

        // Send JOIN
        joinSentAt = Date.now();
        socket.send(stompFrame('SEND', {
          destination: `/app/presence.join/${session.sessionId}`,
          'content-type': 'application/json',
        }, JSON.stringify({
          username: username,
          type: 'JOIN',
          sessionId: session.sessionId,
        })));

        return;
      }

      // STOMP MESSAGE — presence broadcast
      if (frame.startsWith('MESSAGE')) {
        wsMsgReceived.add(1, tags);

        if (joinSentAt > 0 && !joinReceived && frame.includes(username)) {
          joinReceived = true;
          wsJoinRoundtrip.add(Date.now() - joinSentAt, tags);
        }
        return;
      }

      // STOMP ERROR
      if (frame.startsWith('ERROR')) {
        wsErrors.add(1, tags);
      }
    });

    socket.on('error', function (e) {
      wsErrors.add(1, tags);
    });

    // Wait up to 10s for the roundtrip
    socket.setTimeout(function () {
      // Send LEAVE before closing
      if (connected) {
        socket.send(stompFrame('SEND', {
          destination: `/app/presence.leave/${session.sessionId}`,
          'content-type': 'application/json',
        }, JSON.stringify({
          username: username,
          type: 'LEAVE',
          sessionId: session.sessionId,
        })));

        // Small delay for LEAVE to process
        socket.setTimeout(function () {
          socket.send(stompFrame('DISCONNECT', {}));
          socket.close();
        }, 500);
      } else {
        socket.close();
      }
    }, 8000);
  });

  check(null, {
    'WebSocket connected': () => connected,
    'JOIN roundtrip received': () => joinReceived,
  });

  if (!connected) wsErrors.add(1, tags);

  sleep(1);
}
