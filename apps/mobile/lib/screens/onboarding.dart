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
    return Scaffold(
      appBar: AppBar(title: Text(S.of('onboardingTitle'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(Tokens.s24), children: [
          Text(S.of('chooseAvatar'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Tokens.s12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final (i, id) in ChibiAvatar.starterIds.indexed)
              Semantics(
                button: true,
                selected: _avatar == id,
                label: '${S.of('chooseAvatar')} ${i + 1}',
                child: GestureDetector(
                  onTap: () => setState(() => _avatar = id),
                  child: AnimatedContainer(
                    duration: Tokens.fast,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color:
                              _avatar == id ? Tokens.grape : Colors.transparent,
                          width: 3),
                    ),
                    child: ChibiAvatar(
                        avatarId: id, size: _avatar == id ? 72 : 60),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: Tokens.s24),
          TextField(
            key: const Key('displayName'),
            controller: _name,
            maxLength: 20,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: S.of('displayName'),
                helperText: S.of('displayNameHint')),
          ),
          if (!_dobKnown) ...[
            const SizedBox(height: Tokens.s16),
            Text(S.of('birthDate'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Tokens.s8),
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
            const SizedBox(height: Tokens.s8),
            Text(S.of('birthDateNote'),
                style: const TextStyle(color: Tokens.inkSoft, fontSize: 13)),
          ],
          if (_error != null) ...[
            const SizedBox(height: Tokens.s16),
            Text(_error!, style: const TextStyle(color: Tokens.danger)),
          ],
          const SizedBox(height: Tokens.s24),
          GameButton(
              key: const Key('onboardSubmit'),
              label: S.of('continue'),
              busy: _busy,
              onPressed: _valid ? _submit : null),
        ]),
      ),
    );
  }

  Widget _drop(String label, int? value, List<int> items,
          ValueChanged<int?> onChanged, String key) =>
      DropdownButtonFormField<int>(
        key: Key(key),
        initialValue: value,
        isExpanded: true,
        // Label always floats so short fields never truncate it to "الـ...".
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        hint: const Text('—'),
        items: [
          for (final i in items) DropdownMenuItem(value: i, child: Text('$i'))
        ],
        onChanged: onChanged,
      );
}
