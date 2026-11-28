/**
 * Acting and Guessing (مثّل وخمّن): players take turns acting out a secret
 * word with their Chibi avatar while everyone else types guesses.
 *
 * - No camera and no free text or voice from the actor: the actor can only
 *   play moves from ACT_MOVES (pre-approved avatar animations, feelings and
 *   gestures) and reveal the word's own approved hint cards. That makes the
 *   game usable in Safe Mode as is.
 * - Every word in the bank lists the moves that act it out and at least two
 *   hint cards, so every puzzle can be solved with what the actor has.
 * - Guesses are private (like Draw and Guess): wrong guesses only reach their
 *   author, so the guess box is not a chat.
 * - Every move is free: nothing about acting is sold or locked.
 */
export type ActStage = 'choose' | 'act' | 'reveal' | 'finished';

export type ActCategory = 'jobs' | 'animals' | 'sports' | 'daily' | 'transport' | 'places';
export const ACT_CATEGORIES: readonly ActCategory[] = ['jobs', 'animals', 'sports', 'daily', 'transport', 'places'];

/** How the avatar moves while a move plays (the client animates it). */
export type ActMotion =
  | 'bob' | 'jump' | 'shake' | 'spin' | 'sway' | 'float' | 'walk' | 'run' | 'nod'
  | 'stir' | 'still' | 'grow' | 'shrink' | 'push' | 'flap' | 'tilt' | 'low';

/** The avatar's face while a move plays (the art has these four). */
export type ActFace = 'happy' | 'neutral' | 'sad' | 'surprised';

export type ActGroup = 'action' | 'feeling' | 'gesture';

export interface ActMove {
  id: string;
  group: ActGroup;
  label: string;
  /** A prop or symbol shown next to the avatar (Emoji 11 or older). */
  emoji: string;
  motion: ActMotion;
  face: ActFace;
}

const m = (id: string, group: ActGroup, label: string, emoji: string, motion: ActMotion, face: ActFace = 'happy'): ActMove => ({
  id, group, label, emoji, motion, face,
});

/** Every move an actor can play. All of them are free for everyone. */
export const ACT_MOVES: readonly ActMove[] = [
  // Actions
  m('walk', 'action', 'يمشي', '👣', 'walk', 'neutral'),
  m('run', 'action', 'يجري', '💨', 'run'),
  m('jump', 'action', 'ينط', '⤴️', 'jump'),
  m('swim', 'action', 'يعوم', '🌊', 'sway'),
  m('fly', 'action', 'يطير', '☁️', 'float'),
  m('flap', 'action', 'يرفرف', '🌬️', 'flap'),
  m('crawl', 'action', 'يزحف', '〰️', 'low', 'neutral'),
  m('climb', 'action', 'يتسلق', '⬆️', 'jump', 'neutral'),
  m('drive', 'action', 'يسوق', '🚦', 'sway', 'neutral'),
  m('ride', 'action', 'يركب', '🏇', 'bob'),
  m('row', 'action', 'يجدف', '🛶', 'push', 'neutral'),
  m('eat', 'action', 'ياكل', '🍽️', 'nod'),
  m('drink', 'action', 'يشرب', '🥤', 'tilt'),
  m('cook', 'action', 'يطبخ', '🍳', 'stir'),
  m('sleep', 'action', 'ينام', '💤', 'still', 'neutral'),
  m('read', 'action', 'يقرا', '📖', 'nod', 'neutral'),
  m('write', 'action', 'يكتب', '✏️', 'nod', 'neutral'),
  m('teach', 'action', 'يشرح', '📝', 'push'),
  m('sing', 'action', 'يغني', '🎵', 'sway'),
  m('dance', 'action', 'يرقص', '🎶', 'spin'),
  m('play_music', 'action', 'يعزف', '🎸', 'sway'),
  m('paint', 'action', 'يلوّن', '🎨', 'stir'),
  m('kick', 'action', 'يشوط', '👟', 'push'),
  m('throw', 'action', 'يرمي', '💫', 'push'),
  m('catch', 'action', 'يمسك', '🧤', 'jump'),
  m('aim', 'action', 'ينشّن', '🎯', 'still', 'neutral'),
  m('hammer', 'action', 'يدق', '🔨', 'shake', 'neutral'),
  m('dig', 'action', 'يحفر', '⛏️', 'shake', 'neutral'),
  m('fix', 'action', 'يصلّح', '🔧', 'stir', 'neutral'),
  m('lift', 'action', 'يشيل', '📦', 'grow', 'neutral'),
  m('push', 'action', 'يزق', '➡️', 'push', 'neutral'),
  m('wash', 'action', 'يغسل', '🧼', 'stir'),
  m('cut', 'action', 'يقص', '✂️', 'shake', 'neutral'),
  m('sew', 'action', 'يخيّط', '🧵', 'nod', 'neutral'),
  m('phone', 'action', 'يكلم في التليفون', '📞', 'tilt'),
  m('photo', 'action', 'يصوّر', '📷', 'still'),
  m('fish', 'action', 'يصطاد', '🎣', 'still', 'neutral'),
  m('inject', 'action', 'يدّي حقنة', '💉', 'push', 'neutral'),
  m('sell', 'action', 'يبيع', '💰', 'nod'),
  m('count', 'action', 'يعد', '🔢', 'nod', 'neutral'),
  m('wave', 'action', 'يسلّم بإيده', '👋', 'sway'),
  m('clap', 'action', 'يصقف', '👏', 'jump'),
  m('point', 'action', 'يشاور', '👉', 'push', 'neutral'),
  m('look', 'action', 'يبص بعيد', '👀', 'tilt', 'neutral'),
  m('listen', 'action', 'يسمع', '👂', 'tilt', 'neutral'),
  m('smell', 'action', 'يشم', '👃', 'nod'),
  m('scratch', 'action', 'يخربش', '🐾', 'shake', 'neutral'),
  m('horns', 'action', 'ليه قرون', '🤘', 'push', 'neutral'),
  m('loud', 'action', 'صوته عالي', '📢', 'shake', 'surprised'),
  m('quiet', 'action', 'صوته واطي', '🤫', 'still', 'neutral'),
  m('whistle', 'action', 'يصفّر', '📣', 'push', 'surprised'),
  // Feelings
  m('happy', 'feeling', 'مبسوط', '😄', 'bob'),
  m('sad', 'feeling', 'زعلان', '😢', 'still', 'sad'),
  m('angry', 'feeling', 'متعصب', '😠', 'shake', 'sad'),
  m('scared', 'feeling', 'خايف', '😱', 'shake', 'surprised'),
  m('surprised', 'feeling', 'متفاجئ', '😮', 'jump', 'surprised'),
  m('tired', 'feeling', 'تعبان', '😩', 'low', 'sad'),
  m('cold', 'feeling', 'بردان', '❄️', 'shake', 'sad'),
  m('hot', 'feeling', 'حرّان', '🥵', 'sway', 'sad'),
  m('sick', 'feeling', 'عيان', '🤒', 'low', 'sad'),
  m('love', 'feeling', 'بيحب', '😍', 'bob'),
  m('proud', 'feeling', 'فخور', '😎', 'grow'),
  m('hungry', 'feeling', 'جعان', '🤤', 'nod', 'neutral'),
  m('thinking', 'feeling', 'بيفكر', '🤔', 'tilt', 'neutral'),
  // Gestures (size, shape, speed, where)
  m('big', 'gesture', 'كبير أوي', '🔼', 'grow'),
  m('small', 'gesture', 'صغير', '🔽', 'shrink'),
  m('tall', 'gesture', 'طويل', '↕️', 'grow', 'neutral'),
  m('wide', 'gesture', 'عريض', '↔️', 'grow', 'neutral'),
  m('round', 'gesture', 'مدوّر', '⭕', 'spin', 'neutral'),
  m('fast', 'gesture', 'سريع', '⚡', 'run'),
  m('slow', 'gesture', 'بطيء', '⏳', 'walk', 'neutral'),
  m('heavy', 'gesture', 'تقيل', '🧱', 'low', 'neutral'),
  m('light', 'gesture', 'خفيف', '🎈', 'float'),
  m('up', 'gesture', 'فوق', '⬆️', 'float', 'neutral'),
  m('down', 'gesture', 'تحت', '⬇️', 'low', 'neutral'),
  m('water', 'gesture', 'مية', '💧', 'sway', 'neutral'),
  m('fire', 'gesture', 'نار', '🔥', 'shake', 'surprised'),
  m('many', 'gesture', 'كتير', '➕', 'bob'),
  m('one', 'gesture', 'واحد بس', '☝️', 'still', 'neutral'),
  m('money', 'gesture', 'فلوس', '💵', 'nod'),
  m('time', 'gesture', 'وقت / ساعة', '⏰', 'tilt', 'neutral'),
  m('night', 'gesture', 'بالليل', '🌙', 'still', 'neutral'),
  m('day', 'gesture', 'بالنهار', '☀️', 'bob'),
];

export const ACT_MOVE_IDS: ReadonlySet<string> = new Set(ACT_MOVES.map((x) => x.id));

export const ACT_LIMITS = {
  movesPerTurn: 40,
  /** Minimum time between two moves, so each one is seen. */
  moveGapMs: 900,
  guessLength: 40,
  guessesPerTurn: 30,
  guessGapMs: 600,
};

export type ActAction =
  | { kind: 'choose'; turn: number; choice: number }
  /** Play a move from ACT_MOVES. */
  | { kind: 'move'; turn: number; move: string }
  /** Reveal one of the word's hint cards (by index). */
  | { kind: 'card'; turn: number; card: number }
  | { kind: 'guess'; turn: number; text: string; clientElapsedMs?: number };

/** One thing the actor did, in order: a move id or a card's text. */
export type ActBeat = { kind: 'move'; move: string; at: number } | { kind: 'card'; text: string; at: number };

export interface ActTurnView {
  turn: number;
  total: number;
  actor: string;
  chooseEndsAt: number;
  startedAt: number;
  deadline: number;
  /** Actor only, while choosing. */
  choices: { word: string; difficulty: string; points: number }[] | null;
  /** The word: actor while acting; guessers once they got it; everyone at the reveal. */
  word: string | null;
  category: string | null;
  difficulty: string | null;
  /** Letters for guessers ('' hidden, ' ' space, or a hint letter). */
  shape: string[] | null;
  /** Everything the actor did this turn, in order (everyone sees it). */
  beats: ActBeat[];
  /** Actor only: the word's hint cards and which are shown. */
  cards: { text: string; shown: boolean }[] | null;
  /** Actor only: the moves the word's reviewers suggest for it. */
  suggested: string[] | null;
  guessed: string[];
  youGuessed: boolean;
  yourGuesses: string[];
  close: boolean;
}

export interface ActReveal {
  word: string;
  points: Record<string, number>;
  guessed: string[];
  ended: 'all_guessed' | 'time' | 'actor_left' | 'skipped';
}

export interface ActView {
  stage: ActStage;
  turn: ActTurnView | null;
  reveal: ActReveal | null;
  scores: Record<string, number>;
  final: { ranking: { playerId: string; score: number; place: number; correct: number }[] } | null;
}
