import 'package:sahra_client/sahra_client.dart';
import 'package:test/test.dart';

void main() {
  test('parses the shop with prices, unlock paths and the loadout', () {
    final s = ShopView.fromJson({
      'items': [
        {
          'id': 'frame_mint',
          'kind': 'frame',
          'name': 'نعناع',
          'rarity': 'common',
          'look': {'colors': ['#1FD1A5'], 'style': 'solid'},
          'price': {'currency': 'coins', 'amount': 300},
          'unlock': {'kind': 'level', 'level': 3},
          'owned': false,
          'equipped': false,
          'unlockedByPlay': false,
        },
        {
          'id': 'frame_champion',
          'kind': 'frame',
          'name': 'البطل',
          'rarity': 'epic',
          'look': {'colors': ['#FFC83D', '#FF5A7A'], 'style': 'double'},
          'price': null,
          'unlock': {'kind': 'achievement', 'achievementId': 'wins_25'},
          'owned': true,
          'equipped': true,
          'unlockedByPlay': true,
        },
      ],
      'loadout': {'frame': 'frame_champion'},
      'coins': 120,
      'gems': 5,
      'level': 2,
      'gemPurchasesAvailable': false,
    });
    expect(s.items.first.forSale, isTrue);
    expect(s.items.first.unlockLevel, 3);
    expect(s.items.last.forSale, isFalse);
    expect(s.items.last.unlockAchievement, 'wins_25');
    expect(s.equipped('frame')?.look.style, 'double');
    expect(s.coins, 120);
  });

  test('parses missions, the login track and leaderboards', () {
    final m = MissionsView.fromJson({
      'daily': [
        {
          'id': 'mission:d:2026-11-28:0',
          'period': 'daily',
          'kind': 'play_game',
          'gameId': 'spy',
          'target': 1,
          'progress': 1,
          'reward': {'coins': 50, 'xp': 20},
          'claimed': false,
        }
      ],
      'weekly': [],
      'dailyEndsAt': 1,
      'weeklyEndsAt': 2,
      'login': {
        'step': 3,
        'claimedToday': false,
        'rewards': [
          {'coins': 30}
        ],
        'welcomeBack': {'coins': 150, 'xp': 50},
      },
    });
    expect(m.daily.single.ready, isTrue);
    expect(m.daily.single.gameId, 'spy');
    expect(m.login.step, 3);
    expect(m.login.welcomeBack?.coins, 150);

    final lb = LeaderboardView.fromJson({
      'gameId': 'all',
      'period': 'week',
      'scope': 'global',
      'metric': 'points',
      'rows': [
        {
          'rank': 1,
          'playerId': 'a',
          'displayName': 'سارة',
          'avatarId': 'chibi_p_nour',
          'cosmetics': {
            'frame': {'colors': ['#FFFFFF'], 'style': 'solid'},
            'title': {'text': 'لسه جديد', 'colors': ['#FFFFFF']},
          },
          'points': 900,
          'matches': 9,
        }
      ],
      'you': null,
      'bestOf': 10,
    });
    expect(lb.rows.single.cosmetics?.title?.text, 'لسه جديد');
    expect(lb.you, isNull);
    expect(lb.bestOf, 10);
  });
}
