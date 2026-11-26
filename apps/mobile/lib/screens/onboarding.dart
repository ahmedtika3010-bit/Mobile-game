import 'package:flutter/material.dart';
import 'package:sahra_client/sahra_client.dart';

import '../app_state.dart';
import '../design/chibi_avatar.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../l10n/strings.dart';

/// Name, neutral date-of-birth entry (no default age pre-selected, no hint
/// about which answer unlocks what), and a starter Chibi.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  int? _day, _month, _year;
  String _avatar = ChibiAvatar.starterIds.first;
  bool _busy = false;
  String? _error;

  bool get _dobKnown => AppScope.read(context).user?.ageBand != 'unknown';
  bool get _valid =>
      _name.text.trim().length >= 2 &&
      (_dobKnown || (_day != null && _month != null && _year != null));

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.read(context);
    final dob = _dobKnown
        ? ''
        : '${_year!.toString().padLeft(4, '0')}-${_month!.toString().padLeft(2, '0')}-${_day!.toString().padLeft(2, '0')}';
    try {
      await app.onboard(
          displayName: _name.text.trim(), dob: dob, avatarId: _avatar);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error =
          e.code == 'below_minimum_age' ? S.of('tooYoung') : S.of('error'));
    } catch (_) {
      setState(() => _error = S.of('error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final accent = ChibiAvatar.colorFor(_avatar);
    return NightScaffold(
      glow: accent,
      title: Text(S.of('onboardingTitle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.s24, Tokens.s8, Tokens.s24, Tokens.s32),
        children: [
          // Big preview of the chosen character.
          Center(
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.55),
                      blurRadius: 40,
                      spreadRadius: 4)
                ]),
              ),
              AnimatedSwitcher(
                duration: Tokens.medium,
                transitionBuilder: (c, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                    child: c),
                child: Bob(
                  key: ValueKey(_avatar),
                  child: ChibiFullBody(avatarId: _avatar, height: 240),
                ),
              ),
            ]),
          ),
          if (ChibiAvatar.artFor(_avatar) != null)
            Center(
              child: Pill(
                  text: ChibiAvatar.artFor(_avatar)!.name,
                  color: accent,
                  solid: true),
            ),
          const SizedBox(height: Tokens.s16),
          Text(S.of('chooseAvatar'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Tokens.s12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Tokens.s12,
            runSpacing: Tokens.s12,
            children: [
              for (final (i, id) in ChibiAvatar.starterIds.indexed)
                Semantics(
                  button: true,
                  selected: _avatar == id,
                  label: '${S.of('chooseAvatar')} ${i + 1}',
                  onTap: () => setState(() => _avatar = id),
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () => setState(() => _avatar = id),
                    child: AnimatedContainer(
                      duration: Tokens.fast,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _avatar == id
                                ? Tokens.sun
                                : Colors.white.withValues(alpha: 0.15),
                            width: 3),
                      ),
                      child: ChibiAvatar(avatarId: id, size: 60),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s24),
          TextField(
            key: const Key('displayName'),
            controller: _name,
            maxLength: 20,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: S.of('displayName'),
                prefixIcon:
                    const Icon(Icons.badge_rounded, color: Tokens.textDim),
                helperText: S.of('displayNameHint')),
          ),
          if (!_dobKnown) ...[
            const SizedBox(height: Tokens.s16),
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Text('🎂', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: Tokens.s8),
                      Text(S.of('birthDate'),
                          style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: Tokens.s12),
                    Row(children: [
                      Expanded(
                          child: _drop(
                              S.of('day'),
                              _day,
                              List.generate(31, (i) => i + 1),
                              (v) => setState(() => _day = v),
                              'dobDay')),
                      const SizedBox(width: Tokens.s8),
                      Expanded(
                          child: _drop(
                              S.of('month'),
                              _month,
                              List.generate(12, (i) => i + 1),
                              (v) => setState(() => _month = v),
                              'dobMonth')),
                      const SizedBox(width: Tokens.s8),
                      Expanded(
                        flex: 2,
                        child: _drop(
                            S.of('year'),
                            _year,
                            List.generate(100, (i) => now - i),
                            (v) => setState(() => _year = v),
                            'dobYear'),
                      ),
                    ]),
                    const SizedBox(height: Tokens.s12),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_rounded,
                              size: 16, color: Tokens.textFaint),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(S.of('birthDateNote'),
                                style: const TextStyle(
                                    color: Tokens.textFaint,
                                    fontSize: 13,
                                    height: 1.5)),
                          ),
                        ]),
                  ]),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Tokens.s16),
            Shake(
              key: ValueKey(_error),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Tokens.coral, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: Tokens.s24),
          GameButton(
              key: const Key('onboardSubmit'),
              label: S.of('continue'),
              icon: Icons.rocket_launch_rounded,
              color: Tokens.sun,
              busy: _busy,
              onPressed: _valid ? _submit : null),
        ],
      ),
    );
  }

  Widget _drop(String label, int? value, List<int> items,
          ValueChanged<int?> onChanged, String key) =>
      DropdownButtonFormField<int>(
        key: Key(key),
        initialValue: value,
        isExpanded: true,
        dropdownColor: Tokens.night,
        borderRadius: const BorderRadius.all(Tokens.r16),
        menuMaxHeight: 320,
        icon: const Icon(Icons.expand_more_rounded, color: Tokens.textDim),
        style: const TextStyle(
            fontFamily: Tokens.display,
            fontFamilyFallback: [Tokens.body],
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white),
        // Label always floats so short fields never truncate it to "الـ...".
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        hint: const Text('—', style: TextStyle(color: Tokens.textFaint)),
        items: [
          for (final i in items) DropdownMenuItem(value: i, child: Text('$i'))
        ],
        onChanged: onChanged,
      );
}
