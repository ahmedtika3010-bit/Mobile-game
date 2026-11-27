import type { GameModule } from './engine';
import { quizModule } from './quiz';
import { liarModule } from './liar';
import { spyModule } from './spy';
import { whoModule } from './who';
import { emojiModule } from './emoji';
import { stopModule } from './stop';
import { memoryModule } from './memory';

/**
 * Games playable in this build. The other three launch games are not
 * implemented yet and are deliberately absent, so nothing can start them.
 */
const GAMES: Record<string, GameModule<any, any, any>> = {
  quiz: quizModule,
  spy: spyModule,
  liar: liarModule,
  who: whoModule,
  emoji: emojiModule,
  stop: stopModule,
  memory: memoryModule,
};

export function getGame(id: string): GameModule<any, any, any> | undefined {
  return Object.prototype.hasOwnProperty.call(GAMES, id) ? GAMES[id] : undefined;
}

export function listGames() {
  return Object.values(GAMES).map((g) => ({ id: g.id, capabilities: g.capabilities }));
}
