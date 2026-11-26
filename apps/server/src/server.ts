import http from 'node:http';
import { LocalPresence, Server } from '@colyseus/core';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { createApp } from './http/app';
import { GameRoom, ROOM_NAME } from './rooms/GameRoom';

export async function startServer(port: number) {
  // Local presence works for one process. For several game servers, switch to
  // @colyseus/redis-presence + redis-driver (see docs/deployment.md).
  const presence = new LocalPresence();
  const app = createApp(presence);
  const httpServer = http.createServer(app);
  const gameServer = new Server({
    transport: new WebSocketTransport({ server: httpServer, pingInterval: 5000, pingMaxRetries: 3 }),
    presence,
  });
  gameServer.define(ROOM_NAME, GameRoom).filterBy(['gameId', 'mode', 'ageBucket']);
  await gameServer.listen(port);
  return {
    port: (httpServer.address() as { port: number }).port,
    close: () => gameServer.gracefullyShutdown(false),
  };
}
