/// Cosmetics, shop, missions, achievements and leaderboards.
/// Mirrors packages/shared/src/progress.ts.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

/// How an item looks, described as data (colors as #RRGGBB).
class CosmeticLook {
  const CosmeticLook(
      {this.colors = const [], this.style, this.text, this.emojis = const []});
  CosmeticLook.fromJson(Map<String, dynamic> j)
      : colors = ((j['colors'] as List?) ?? const []).cast<String>(),
        style = j['style'] as String?,
        text = j['text'] as String?,
        emojis = ((j['emojis'] as List?) ?? const []).cast<String>();
  final List<String> colors;
  final String? style;
  final String? text;
  final List<String> emojis;

  static CosmeticLook? maybe(Object? v) {
    final m = _map(v);
    return m == null ? null : CosmeticLook.fromJson(m);
  }
}

/// What other players see: equipped frame, title and victory effect.
class PublicCosmetics {
  const PublicCosmetics({this.frame, this.title, this.effect});
  PublicCosmetics.fromJson(Map<String, dynamic> j)
      : frame = CosmeticLook.maybe(j['frame']),
        title = CosmeticLook.maybe(j['title']),
        effect = CosmeticLook.maybe(j['effect']);
  final CosmeticLook? frame;
  final CosmeticLook? title;
  final CosmeticLook? effect;

  static PublicCosmetics? maybe(Object? v) {
    final m = _map(v);
    return m == null ? null : PublicCosmetics.fromJson(m);
  }
}

class Reward {
  const Reward({this.coins = 0, this.gems = 0, this.xp = 0, this.item});
  Reward.fromJson(Map<String, dynamic> j)
      : coins = _int(j['coins']),
        gems = _int(j['gems']),
        xp = _int(j['xp']),
        item = j['item'] as String?;
  final int coins;
  final int gems;
  final int xp;
  final String? item;
  bool get isEmpty => coins == 0 && gems == 0 && xp == 0 && item == null;
}

class ShopItem {
  ShopItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        kind = j['kind'] as String,
        name = j['name'] as String,
        rarity = j['rarity'] as String? ?? 'common',
        look = CosmeticLook.fromJson(_map(j['look']) ?? const {}),
        priceCurrency = _map(j['price'])?['currency'] as String?,
        priceAmount = _int(_map(j['price'])?['amount']),
        unlockKind = _map(j['unlock'])?['kind'] as String? ?? 'default',
        unlockLevel = _int(_map(j['unlock'])?['level']),
        unlockAchievement = _map(j['unlock'])?['achievementId'] as String?,
        event = j['event'] as String?,
        owned = j['owned'] == true,
        equipped = j['equipped'] == true,
        unlockedByPlay = j['unlockedByPlay'] == true;
  final String id;

  /// frame | title | theme | effect
  final String kind;
  final String name;

  /// common | rare | epic | legendary
  final String rarity;
  final CosmeticLook look;

  /// coins | gems; null when the item cannot be bought.
  final String? priceCurrency;
  final int priceAmount;

  /// default | level | achievement
  final String unlockKind;
  final int unlockLevel;
  final String? unlockAchievement;
  final String? event;
  final bool owned;
  final bool equipped;
  final bool unlockedByPlay;
  bool get forSale => priceCurrency != null;
}

class ShopView {
  ShopView.fromJson(Map<String, dynamic> j)
      : items = ((j['items'] as List?) ?? const [])
            .map((e) => ShopItem.fromJson((e as Map).cast()))
            .toList(),
        loadout = (_map(j['loadout']) ?? const {}).cast<String, String>(),
        coins = _int(j['coins']),
        gems = _int(j['gems']),
        level = _int(j['level']),
        gemPurchasesAvailable = j['gemPurchasesAvailable'] == true;
  final List<ShopItem> items;

  /// kind -> equipped item id.
  final Map<String, String> loadout;
  final int coins;
  final int gems;
  final int level;
  final bool gemPurchasesAvailable;

  ShopItem? equipped(String kind) {
    final id = loadout[kind];
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }
}

class Mission {
  Mission.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        period = j['period'] as String,
        kind = j['kind'] as String,
        gameId = j['gameId'] as String?,
        target = _int(j['target']),
        progress = _int(j['progress']),
        reward = Reward.fromJson(_map(j['reward']) ?? const {}),
        claimed = j['claimed'] == true;
  final String id;

  /// daily | weekly
  final String period;

  /// play_any | play_distinct | win | play_game | perf | private | night
  final String kind;
  final String? gameId;
  final int target;
  final int progress;
  final Reward reward;
  final bool claimed;
  bool get ready => !claimed && progress >= target;
}

class LoginTrack {
  LoginTrack.fromJson(Map<String, dynamic> j)
      : step = _int(j['step']),
        claimedToday = j['claimedToday'] == true,
        rewards = ((j['rewards'] as List?) ?? const [])
            .map((e) => Reward.fromJson((e as Map).cast()))
            .toList(),
        welcomeBack = _map(j['welcomeBack']) == null
            ? null
            : Reward.fromJson(_map(j['welcomeBack'])!);

  /// The step today's claim gives (1..7). A missed day never resets it.
  final int step;
  final bool claimedToday;
  final List<Reward> rewards;
  final Reward? welcomeBack;
}

class MissionsView {
  MissionsView.fromJson(Map<String, dynamic> j)
      : daily = _missions(j['daily']),
        weekly = _missions(j['weekly']),
        dailyEndsAt = _int(j['dailyEndsAt']),
        weeklyEndsAt = _int(j['weeklyEndsAt']),
        login = LoginTrack.fromJson(_map(j['login']) ?? const {});
  static List<Mission> _missions(Object? v) => ((v as List?) ?? const [])
      .map((e) => Mission.fromJson((e as Map).cast()))
      .toList();
  final List<Mission> daily;
  final List<Mission> weekly;
  final int dailyEndsAt;
  final int weeklyEndsAt;
  final LoginTrack login;
}

class Achievement {
  Achievement.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        gameId = j['gameId'] as String?,
        kind = j['kind'] as String,
        target = _int(j['target']),
        progress = _int(j['progress']),
        reward = Reward.fromJson(_map(j['reward']) ?? const {}),
        claimed = j['claimed'] == true;
  final String id;
  final String? gameId;

  /// matches | wins | distinct | level | friends | nights
  final String kind;
  final int target;
  final int progress;
  final Reward reward;
  final bool claimed;
  bool get ready => !claimed && progress >= target;
}

class LeaderboardRow {
  LeaderboardRow.fromJson(Map<String, dynamic> j)
      : rank = _int(j['rank']),
        playerId = j['playerId'] as String,
        displayName = j['displayName'] as String? ?? '',
        avatarId = j['avatarId'] as String? ?? '',
        cosmetics = PublicCosmetics.maybe(j['cosmetics']),
        points = _int(j['points']),
        matches = _int(j['matches']);
  final int rank;
  final String playerId;
  final String displayName;
  final String avatarId;
  final PublicCosmetics? cosmetics;
  final int points;
  final int matches;
}

class LeaderboardView {
  LeaderboardView.fromJson(Map<String, dynamic> j)
      : gameId = j['gameId'] as String? ?? 'all',
        period = j['period'] as String? ?? 'week',
        scope = j['scope'] as String? ?? 'global',
        metric = j['metric'] as String? ?? 'points',
        rows = ((j['rows'] as List?) ?? const [])
            .map((e) => LeaderboardRow.fromJson((e as Map).cast()))
            .toList(),
        you = _map(j['you']) == null
            ? null
            : LeaderboardRow.fromJson(_map(j['you'])!),
        bestOf = _int(j['bestOf']);
  final String gameId;
  final String period;
  final String scope;

  /// points | rating
  final String metric;
  final List<LeaderboardRow> rows;
  final LeaderboardRow? you;
  final int bestOf;
}

class ProgressSummary {
  ProgressSummary.fromJson(Map<String, dynamic> j)
      : missionsReady = _int(j['missionsReady']),
        achievementsReady = _int(j['achievementsReady']),
        loginReady = j['loginReady'] == true;
  const ProgressSummary.empty()
      : missionsReady = 0,
        achievementsReady = 0,
        loginReady = false;
  final int missionsReady;
  final int achievementsReady;
  final bool loginReady;
}
