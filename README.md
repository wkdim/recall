# Recall

An offline-first spaced-repetition flashcard app. No account, no ads, no
backend — everything lives on your device, including the AI features.

## Features

- **Decks & cards** — create, edit, delete, tag, search; cloze deletion
  cards; image and audio attachments.
- **Spaced repetition** — [FSRS](https://github.com/open-spaced-repetition/fsrs4anki)
  scheduling (a simplified, honestly-documented approximation — see
  `lib/scheduler/fsrs.dart`).
- **Focus Mode** — one home-screen card: greeting, due count, single Start
  button. No deck-picking required to study what's due.
- **Smart Collections** — Forgotten, Difficult, Recently Added, Mature —
  computed from existing card data, no extra bookkeeping.
- **Deck Health Score** — a rule-based quality signal per deck (duplicates,
  overlong cards, staleness, never-reviewed).
- **AI features, fully on-device** — "Generate from text" and "Improve with
  AI" run a small open-source model (Qwen3-0.6B) locally via
  [flutter_gemma](https://pub.dev/packages/flutter_gemma). One-time ~475MB
  model download, then fully offline. No flashcard content ever leaves the
  device.
- **Streaks, XP, levels, daily goal** — lightweight gamification layered on
  top of real study activity.
- **Dark mode, accessibility pass, CSV/JSON import-export, local due-review
  notifications, undo-last-rating.**

## Getting started

```bash
flutter pub get
flutter run
```

Requires Flutter 3.9+ (see `pubspec.yaml` for the exact SDK constraint).
The on-device AI features need Android `minSdkVersion 24`+ (already
configured) and download a model file on first use — nothing else to set
up.

## Testing

```bash
flutter test
flutter analyze
```

Widget/unit tests use Drift's `NativeDatabase.memory()` via
`AppDatabase.forTesting()` — never instantiate `AppDatabase()` directly in
a test, it hangs (no `path_provider` plugin registration in a bare test
host). External integrations (media pickers, notifications, the on-device
AI model) are abstracted behind injectable interfaces with fakes for
testing, since none of them have platform-channel support in `flutter
test`.

## Project structure

- `lib/database/` — Drift schema and generated code.
- `lib/scheduler/` — SM-2 (bookkeeping only) and FSRS (authoritative for
  scheduling) — see `lib/scheduler/fsrs.dart` for why both still exist.
- `lib/ai/` — the on-device flashcard generator/improver.
- `lib/gamification/` — XP, levels, daily goal.
- `lib/screens/` — UI.
- `test/` — mirrors `lib/` structure.

## Privacy & release info

- [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md) — also published at
  <https://wkdim.github.io/recall/privacy/> once GitHub Pages is enabled
  for this repo.
- [`SESSION_SUMMARY.md`](SESSION_SUMMARY.md) — a running log of what's been
  built and why, useful if you're picking this project back up after a
  break.

## Status

Version 2.0 of the roadmap (card features, FSRS, on-device AI, gamification)
is complete. Android release prep (app ID, signing, icon, crash reporting)
is done and verified with a real signed build; still open before an actual
Play Store submission: store listing assets, hosting the privacy policy
publicly, and backing up the release signing keystore somewhere outside
this machine. iOS build config is deferred (no Mac in the current dev
environment to verify against).
