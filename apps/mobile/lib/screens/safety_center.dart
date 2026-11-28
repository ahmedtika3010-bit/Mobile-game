import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../l10n/strings.dart';

/// First version of the Safety and Privacy Center: explains the protections
/// that are actually enforced today. Settings and blocked list come next.
class SafetyCenterScreen extends StatelessWidget {
  const SafetyCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        '🛡️',
        'الوضع الآمن',
        'أي غرفة فيها لاعب أقل من 18 سنة بتشتغل بالوضع الآمن: عبارات جاهزة بس، من غير شات حر ولا صوت. ومحدش يقدر يقفله.'
      ),
      (
        '🎂',
        'تاريخ ميلادك',
        'بنستخدمه بس عشان نطبّق الحماية المناسبة. مش بيظهر لأي لاعب.'
      ),
      (
        '🚩',
        'الإبلاغ',
        'دوس على أي لاعب في الغرفة واختار "إبلاغ". البلاغات الخطيرة بتقيّد الحساب فوراً لحد ما فريقنا يراجعها.'
      ),
      ('⛔', 'الحظر', 'لما تحظر حد، مش هتتجمعوا مع بعض في اللعب العام.'),
      (
        '⚖️',
        'اللعب النظيف',
        'الخادم هو اللي بيحسب النقاط والمكافآت، ومحدش يقدر يغيّرها من جهازه.'
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(S.of('safetyCenter'))),
      body: ListView.separated(
        padding: const EdgeInsets.all(Tokens.s16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: Tokens.s12),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(Tokens.s16),
          decoration: const BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.all(Tokens.r16)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(items[i].$1, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(items[i].$2,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(items[i].$3,
                        style: const TextStyle(
                            color: Tokens.inkSoft, height: 1.5)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}
