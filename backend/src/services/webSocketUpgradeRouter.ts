import type { Server as HttpServer } from 'http';
import { parse } from 'url';
import { WebSocketServer } from 'ws';

/**
 * Attach one path-scoped WebSocket server without letting it reject upgrades
 * intended for another WebSocket service on the same HTTP server.
 */
export function createPathWebSocketServer(
  server: HttpServer,
  path: string,
): WebSocketServer {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const requestPath = parse(request.url || '').pathname || '';
    if (requestPath !== path) {
      return;
    }

    wss.handleUpgrade(request, socket, head, (webSocket) => {
      wss.emit('connection', webSocket, request);
    });
  });

  return wss;
}
