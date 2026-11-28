/// Acting and Guessing: the move library, mirrored from
/// packages/shared/src/acting.ts (a test checks the two stay in sync).
library;

class ActMove {
  const ActMove(
      this.id, this.group, this.label, this.emoji, this.motion, this.face);
  final String id;

  /// action | feeling | gesture
  final String group;
  final String label;
  final String emoji;

  /// How the avatar moves (see ActMotion in acting.ts).
  final String motion;

  /// happy | neutral | sad | surprised
  final String face;
}

const actMoves = <ActMove>[
  ActMove('walk', 'action', 'يمشي', '👣', 'walk', 'neutral'),
  ActMove('run', 'action', 'يجري', '💨', 'run', 'happy'),
  ActMove('jump', 'action', 'ينط', '⤴️', 'jump', 'happy'),
  ActMove('swim', 'action', 'يعوم', '🌊', 'sway', 'happy'),
  ActMove('fly', 'action', 'يطير', '☁️', 'float', 'happy'),
  ActMove('flap', 'action', 'يرفرف', '🌬️', 'flap', 'happy'),
  ActMove('crawl', 'action', 'يزحف', '〰️', 'low', 'neutral'),
  ActMove('climb', 'action', 'يتسلق', '⬆️', 'jump', 'neutral'),
  ActMove('drive', 'action', 'يسوق', '🚦', 'sway', 'neutral'),
  ActMove('ride', 'action', 'يركب', '🏇', 'bob', 'happy'),
  ActMove('row', 'action', 'يجدف', '🛶', 'push', 'neutral'),
  ActMove('eat', 'action', 'ياكل', '🍽️', 'nod', 'happy'),
  ActMove('drink', 'action', 'يشرب', '🥤', 'tilt', 'happy'),
  ActMove('cook', 'action', 'يطبخ', '🍳', 'stir', 'happy'),
  ActMove('sleep', 'action', 'ينام', '💤', 'still', 'neutral'),
  ActMove('read', 'action', 'يقرا', '📖', 'nod', 'neutral'),
  ActMove('write', 'action', 'يكتب', '✏️', 'nod', 'neutral'),
  ActMove('teach', 'action', 'يشرح', '📝', 'push', 'happy'),
  ActMove('sing', 'action', 'يغني', '🎵', 'sway', 'happy'),
  ActMove('dance', 'action', 'يرقص', '🎶', 'spin', 'happy'),
  ActMove('play_music', 'action', 'يعزف', '🎸', 'sway', 'happy'),
  ActMove('paint', 'action', 'يلوّن', '🎨', 'stir', 'happy'),
  ActMove('kick', 'action', 'يشوط', '👟', 'push', 'happy'),
  ActMove('throw', 'action', 'يرمي', '💫', 'push', 'happy'),
  ActMove('catch', 'action', 'يمسك', '🧤', 'jump', 'happy'),
  ActMove('aim', 'action', 'ينشّن', '🎯', 'still', 'neutral'),
  ActMove('hammer', 'action', 'يدق', '🔨', 'shake', 'neutral'),
  ActMove('dig', 'action', 'يحفر', '⛏️', 'shake', 'neutral'),
  ActMove('fix', 'action', 'يصلّح', '🔧', 'stir', 'neutral'),
  ActMove('lift', 'action', 'يشيل', '📦', 'grow', 'neutral'),
  ActMove('push', 'action', 'يزق', '➡️', 'push', 'neutral'),
  ActMove('wash', 'action', 'يغسل', '🧼', 'stir', 'happy'),
  ActMove('cut', 'action', 'يقص', '✂️', 'shake', 'neutral'),
  ActMove('sew', 'action', 'يخيّط', '🧵', 'nod', 'neutral'),
  ActMove('phone', 'action', 'يكلم في التليفون', '📞', 'tilt', 'happy'),
  ActMove('photo', 'action', 'يصوّر', '📷', 'still', 'happy'),
  ActMove('fish', 'action', 'يصطاد', '🎣', 'still', 'neutral'),
  ActMove('inject', 'action', 'يدّي حقنة', '💉', 'push', 'neutral'),
  ActMove('sell', 'action', 'يبيع', '💰', 'nod', 'happy'),
  ActMove('count', 'action', 'يعد', '🔢', 'nod', 'neutral'),
  ActMove('wave', 'action', 'يسلّم بإيده', '👋', 'sway', 'happy'),
  ActMove('clap', 'action', 'يصقف', '👏', 'jump', 'happy'),
  ActMove('point', 'action', 'يشاور', '👉', 'push', 'neutral'),
  ActMove('look', 'action', 'يبص بعيد', '👀', 'tilt', 'neutral'),
  ActMove('listen', 'action', 'يسمع', '👂', 'tilt', 'neutral'),
  ActMove('smell', 'action', 'يشم', '👃', 'nod', 'happy'),
  ActMove('scratch', 'action', 'يخربش', '🐾', 'shake', 'neutral'),
  ActMove('horns', 'action', 'ليه قرون', '🤘', 'push', 'neutral'),
  ActMove('loud', 'action', 'صوته عالي', '📢', 'shake', 'surprised'),
  ActMove('quiet', 'action', 'صوته واطي', '🤫', 'still', 'neutral'),
  ActMove('whistle', 'action', 'يصفّر', '📣', 'push', 'surprised'),
  ActMove('happy', 'feeling', 'مبسوط', '😄', 'bob', 'happy'),
  ActMove('sad', 'feeling', 'زعلان', '😢', 'still', 'sad'),
  ActMove('angry', 'feeling', 'متعصب', '😠', 'shake', 'sad'),
  ActMove('scared', 'feeling', 'خايف', '😱', 'shake', 'surprised'),
  ActMove('surprised', 'feeling', 'متفاجئ', '😮', 'jump', 'surprised'),
  ActMove('tired', 'feeling', 'تعبان', '😩', 'low', 'sad'),
  ActMove('cold', 'feeling', 'بردان', '❄️', 'shake', 'sad'),
  ActMove('hot', 'feeling', 'حرّان', '🥵', 'sway', 'sad'),
  ActMove('sick', 'feeling', 'عيان', '🤒', 'low', 'sad'),
  ActMove('love', 'feeling', 'بيحب', '😍', 'bob', 'happy'),
  ActMove('proud', 'feeling', 'فخور', '😎', 'grow', 'happy'),
  ActMove('hungry', 'feeling', 'جعان', '🤤', 'nod', 'neutral'),
  ActMove('thinking', 'feeling', 'بيفكر', '🤔', 'tilt', 'neutral'),
  ActMove('big', 'gesture', 'كبير أوي', '🔼', 'grow', 'happy'),
  ActMove('small', 'gesture', 'صغير', '🔽', 'shrink', 'happy'),
  ActMove('tall', 'gesture', 'طويل', '↕️', 'grow', 'neutral'),
  ActMove('wide', 'gesture', 'عريض', '↔️', 'grow', 'neutral'),
  ActMove('round', 'gesture', 'مدوّر', '⭕', 'spin', 'neutral'),
  ActMove('fast', 'gesture', 'سريع', '⚡', 'run', 'happy'),
  ActMove('slow', 'gesture', 'بطيء', '⏳', 'walk', 'neutral'),
  ActMove('heavy', 'gesture', 'تقيل', '🧱', 'low', 'neutral'),
  ActMove('light', 'gesture', 'خفيف', '🎈', 'float', 'happy'),
  ActMove('up', 'gesture', 'فوق', '⬆️', 'float', 'neutral'),
  ActMove('down', 'gesture', 'تحت', '⬇️', 'low', 'neutral'),
  ActMove('water', 'gesture', 'مية', '💧', 'sway', 'neutral'),
  ActMove('fire', 'gesture', 'نار', '🔥', 'shake', 'surprised'),
  ActMove('many', 'gesture', 'كتير', '➕', 'bob', 'happy'),
  ActMove('one', 'gesture', 'واحد بس', '☝️', 'still', 'neutral'),
  ActMove('money', 'gesture', 'فلوس', '💵', 'nod', 'happy'),
  ActMove('time', 'gesture', 'وقت / ساعة', '⏰', 'tilt', 'neutral'),
  ActMove('night', 'gesture', 'بالليل', '🌙', 'still', 'neutral'),
  ActMove('day', 'gesture', 'بالنهار', '☀️', 'bob', 'happy'),
];

final Map<String, ActMove> actMoveById = {for (final m in actMoves) m.id: m};
