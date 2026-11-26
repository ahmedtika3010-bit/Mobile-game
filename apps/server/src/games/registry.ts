import type { GameModule } from './engine';
import { quizModule } from './quiz';

/**
 * Games playable in this build. The other nine launch games are not
 * implemented yet and are deliberately absent, so nothing can start them.
 */
const GAMES: Record<string, GameModule<any, any, any>> = {
  quiz: quizModule,
};

export function getGame(id: string): GameModule<any, any, any> | undefined {
  return Object.prototype.hasOwnProperty.call(GAMES, id) ? GAMES[id] : undefined;
}

export function listGames() {
  return Object.values(GAMES).map((g) => ({ id: g.id, capabilities: g.capabilities }));
}
