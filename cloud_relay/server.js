/**
 * PTA Native Cloud Relay Server (Node.js)
 * 1-Click Free Deployment for Render / Glitch / Railway / VPS
 */

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  if (req.url === '/health' || req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', activeSessions: sessions.size }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

const wss = new WebSocketServer({ server });

// Map<pairingKey, { hosts: Set<WebSocket>, clients: Set<WebSocket> }>
const sessions = new Map();

function getOrCreateSession(key) {
  if (!sessions.has(key)) {
    sessions.set(key, { hosts: new Set(), clients: new Set() });
  }
  return sessions.get(key);
}

wss.on('connection', (socket) => {
  let currentKey = null;
  let currentRole = null;

  socket.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());

      if (msg.type === 'REGISTER_CLOUD_SESSION') {
        const { pairingKey = 'pta_native_default', role = 'client' } = msg.data || {};
        currentKey = pairingKey;
        currentRole = role;

        const session = getOrCreateSession(pairingKey);
        if (role === 'host') {
          session.hosts.add(socket);
        } else {
          session.clients.add(socket);
        }
        socket.send(JSON.stringify({ type: 'PONG', data: { registered: true, role } }));
        console.log(`[SESSION] Registered ${role} for key: ${pairingKey}`);
        return;
      }

      if (msg.type === 'PING') {
        socket.send(JSON.stringify({ type: 'PONG', data: {} }));
        return;
      }

      // Forward frames between host and clients
      if (currentKey && sessions.has(currentKey)) {
        const session = sessions.get(currentKey);
        if (currentRole === 'host') {
          for (const client of session.clients) {
            if (client.readyState === 1) client.send(raw.toString());
          }
        } else if (currentRole === 'client') {
          for (const host of session.hosts) {
            if (host.readyState === 1) host.send(raw.toString());
          }
        }
      }
    } catch (err) {
      console.error('[ERROR] Packet handle error:', err);
    }
  });

  socket.on('close', () => {
    if (currentKey && sessions.has(currentKey)) {
      const session = sessions.get(currentKey);
      if (currentRole === 'host') session.hosts.delete(socket);
      if (currentRole === 'client') session.clients.delete(socket);

      if (session.hosts.size === 0 && session.clients.size === 0) {
        sessions.delete(currentKey);
      }
    }
  });
});

server.listen(PORT, () => {
  console.log(`[PTA RELAY] Cloud Server listening on port ${PORT}`);
});
