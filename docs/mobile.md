# Mobile app (Flutter)

`apps/mobile` is the player app. It talks to the server through the pure-Dart
package `packages/sahra_client` (HTTP API + a small Colyseus 0.16 client), so the
networking can be tested without Flutter.

Arabic and right-to-left are the default. The look (night-sky background, Baloo
Bhaijaan 2 for game text with Cairo as fallback, 3D buttons, motion) lives in
`lib/design/`; all fonts are SIL Open Font License and bundled. All player-facing text lives in
`lib/l10n/strings.dart`; design tokens are in `lib/design/tokens.dart`.

## Build-time settings (`--dart-define`)

| Name | Default | Purpose |
| --- | --- | --- |
| `SERVER_URL` | web: same origin; Android emulator: `http://10.0.2.2:2567`; others: `http://localhost:2567` | Game server address |
| `GOOGLE_SERVER_CLIENT_ID` | empty (Google button disabled) | OAuth **Web** client id from Google Cloud; the server must list the same id in `GOOGLE_CLIENT_IDS` |
| `APP_NAME` | `سهرة` | Working title only |
| `DEV_SIGN_IN` | `false` | Shows developer sign-in in a non-debug build. For local testing only; the server also refuses it unless `DEV_AUTH=1` |

## Run against a local server

```bash
# terminal 1: server (see README) with DEV_AUTH=1
# terminal 2:
cd apps/mobile
flutter pub get
flutter run                     # debug builds show developer sign-in
```

### In a browser (used for automated UI checks)

```bash
cd apps/mobile
flutter build web --base-href /play/ --no-web-resources-cdn --dart-define=DEV_SIGN_IN=true
# open http://localhost:2567/play/  (served by the dev server only when DEV_AUTH=1)
```

`--no-web-resources-cdn` keeps the renderer self-hosted; the Cairo font is
bundled in `assets/fonts` (SIL Open Font License, see `assets/fonts/OFL.txt`).

## Tests

```bash
cd packages/sahra_client
dart test                                            # codec and models
SAHRA_SERVER=http://localhost:2567 dart test -t live # real server: match + reconnect
cd ../../apps/mobile
flutter analyze && flutter test
```

## Real sign-in setup (not done yet: needs your accounts)

Application id / bundle id today: `app.sahra.sahra`. Change it before creating
store listings, because it cannot change after publishing.

**Google**
1. In Google Cloud, create OAuth clients: one *Android* client (package name +
   SHA-1 of the signing key), one *iOS* client (bundle id), and one *Web* client.
2. Build with `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`.
3. iOS: add the iOS client's reversed client id as a URL scheme in
   `ios/Runner/Info.plist` (`CFBundleURLTypes`) and set `GIDClientID`.
4. Server: put all three client ids in `GOOGLE_CLIENT_IDS`.

**Apple** (iOS only in the app today)
1. Enable "Sign in with Apple" for the App ID and add the capability in Xcode.
2. Server: put the bundle id in `APPLE_BUNDLE_IDS`.
3. Sign in with Apple on Android needs a Services ID and a web redirect; not
   implemented, so the Apple button only appears on iOS.

## Known gaps

- No Android or iOS device build has been made from this environment (no Android
  SDK or Mac here). The app was verified with widget tests and as a web build
  driven by a browser through a full match against the real server.
- Characters are still images cut from the designer's sheets (`design/characters`
  → `assets/characters`). Animated versions (Rive) and more expressions are pending.
- Only the General Knowledge Quiz is playable; the other games show "قريباً".
