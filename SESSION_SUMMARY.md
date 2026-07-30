# Recall — Session Summary (2026-07-27 → 2026-07-29)

This covers everything done across this working session, in order. It picks
up with Version 2.0 of the agreed roadmap (Image/Audio cards were already
in progress) and ends with Android release prep.

---

## 1. Image cards

- Schema bumped to `schemaVersion 4`: `Cards` gained `frontImagePath`,
  `backImagePath`, `frontAudioPath`, `backAudioPath`.
- `lib/media/media_storage.dart` — `MediaStorage.copyIntoAppStorage()` always
  copies a picked file into the app's own `media/` folder under a unique
  name, rather than trusting a picker plugin's own (often temporary) path.
- `lib/media/media_picker.dart` — abstracts `image_picker`/`file_picker`
  behind a `MediaPicker` interface, injectable into `EditDeckScreen` for
  testing (same pattern used throughout: `ReminderScheduler`,
  `FlashcardGenerator`, etc.).
- `_MediaAttachRow` widget in `EditDeckScreen`: "Add image" button or an
  attached-state `Chip` with a real thumbnail preview.
- Media files are deleted from disk when their card/deck is deleted.
- **Test-infra work** (this took real effort): testing a *real* `Image.file`
  decode of a freshly-written file on Windows is inherently flaky —
  antivirus/real-time protection can briefly lock a new file, and the
  decode failure is reported to Flutter's error system asynchronously, so a
  plain `tester.takeException()` right after a pump can miss it. Fixed with
  a `_settleAndDrainExceptions()` helper that gives the decode real
  wall-clock time before draining recorded exceptions.
- Also fixed a recurring environment issue: stray `dart.exe` processes from
  earlier interrupted test runs piling up and eventually crashing the Dart
  JIT compiler outright (`taskkill /F /IM dart.exe /T` clears it — this came
  up several more times later in the session too).

## 2. Audio cards

- Same pattern as image cards, but simpler: the audio "attached" indicator
  is a static icon, not a real file preview, so none of the image-decode
  flakiness applies.
- Playback wired into `StudyScreen` via the `audioplayers` package.

## 3. Scheduler simplified: FSRS-only (SM-2 toggle removed)

- User's own observation: the app carried both SM-2 and FSRS with a
  user-facing toggle, but since the app hasn't launched yet there's no real
  user history that justifies keeping SM-2 as a live *option*.
- Removed `lib/settings/scheduler_prefs.dart` and the SCHEDULER section in
  Settings. `StudyScreen` now always uses FSRS for the actual
  scheduling interval/next-review date.
- `lib/scheduler/sm2.dart` was **kept**, deliberately — its
  easeFactor/repetitions output still feeds Smart Collections and Deck
  Health, which key off those fields regardless of which algorithm sets the
  next-review date.

## 4. Build/tooling fixes found along the way

- `pubspec.yaml` was missing `flutter_lints` from `dev_dependencies`
  entirely — `flutter analyze` was failing outright until it was added
  back.
- Android build was failing on `flutter_local_notifications` needing core
  library desugaring — fixed in `android/app/build.gradle.kts`.
- Bumped AGP (8.9.1 → 8.11.1) and Kotlin (2.1.0 → 2.2.20) to clear Flutter
  deprecation warnings.

## 5. AI flashcard generation — on-device, zero cost

User was explicit: no ongoing cost, for any number of users. That ruled out
cloud LLM APIs outright (even a "free tier" shared across all users doesn't
stay free past a handful of active users hitting the same rate limit).

- **Model: Qwen3-0.6B**, not Gemma. Checked directly against Hugging Face:
  Gemma models there are **gated** (require an account + per-user license
  acceptance) — unworkable for a consumer app. Qwen3-0.6B is **ungated,
  Apache 2.0**, verified with a live `curl` request that it downloads
  without auth.
- Runs via `flutter_gemma` + `flutter_gemma_litertlm`, entirely on-device.
  ~475MB one-time download, fully offline after that.
- `lib/ai/flashcard_generator.dart`: abstract `FlashcardGenerator`
  interface (testable via a fake, same DI pattern as `MediaPicker`).
  `parseGeneratedCards()` is a **pure, fully unit-tested** function that
  tolerates markdown fences and stray preamble text models add despite
  being told not to.
- `lib/screens/generate_cards_screen.dart`: paste text → download progress
  (first use only) → reviewable checklist of generated cards → add selected
  ones. Reachable from a deck's "More options" menu.
- Android `minSdkVersion` bumped to 24 (flutter_gemma's requirement).

## 6. "Improve my flashcards"

- Reused the exact same model/plumbing: added `improveCard()` to
  `FlashcardGenerator`, a shared `_runSingleTurn()` helper so both prompts
  share one install/session lifecycle, and `parseImprovedCard()` (object
  shape, vs. generation's array shape).
- Surfaced as an "Improve with AI" button inside the existing card-edit
  dialog — shows a suggestion with "Use This"/"Dismiss".
- **Real bug the widget test caught before a device ever would**: the
  suggestion preview overflowed the dialog's fixed height. Fixed with a
  `SingleChildScrollView`.

## 7. XP, levels, daily goal (closes out Version 2.0)

- `lib/gamification/xp_tracker.dart`: every rating earns XP, *including*
  "Again" (2/5/10/15 for Again/Hard/Good/Easy) — deliberate, so the
  incentive stays "engage honestly" rather than "rate generously to see
  numbers go up," which would undermine the scheduler's accuracy. Flat
  100-XP-per-level curve.
- `lib/gamification/daily_goal.dart`: same pattern as the existing streak
  tracker, but increments on every card (not once per session) and resets
  each calendar day. Default 20 cards/day, adjustable in Settings.
- Wired into `StudyScreen._rateCard`; a level-up shows a `SnackBar`.
- Deliberately **not** reverted by undo — undo fixes a scheduling mistake,
  it doesn't erase that the user engaged with the card.
- Deck list home card gained a `Lv. N` badge and a goal-progress bar.

**Version 2.0 is now fully complete**: AI generation, "Improve my
flashcards," image/audio cards, and XP/levels/daily-goal are all shipped,
tested, and stable. Full suite: 200 tests, all green.

---

## 8. Release prep (Android)

User chose this over Version 2.5 (cloud sync) because the app can't reach
anyone yet regardless of feature set — this was the actual blocker.

### Application ID
`com.wkdim.recall` (not the work domain `conaktechnology.com` — this app is
personal, unrelated to the user's employer). Updated consistently across
Android (`build.gradle.kts`, moved the Kotlin source file to match), iOS
(`project.pbxproj`), macOS (`AppInfo.xcconfig` + its own `project.pbxproj`),
and Linux (`CMakeLists.txt`). macOS's internal `PRODUCT_NAME`/`.app` bundle
filename was deliberately left alone — too many interlinked references to
safely rename without a real macOS build to verify against, and macOS isn't
an actual target platform right now.

### App name
Unified to **"Recall"** everywhere — there were previously four different
display strings in play (`flashcard_app`, `Flashcard Mastery`, `Flashcard
App`, `flashcard_app`) across `main.dart`, the Android manifest, iOS
`Info.plist`, and the web manifest.

### Launcher icon
Was still the stock default Flutter logo. Generated a simple placeholder (a
bold white "R" on the app's actual Material 3 seed color, `#6750A4`) via a
small Python/Pillow script, wired up through the `flutter_launcher_icons`
package for all platforms. **This is a placeholder** — swap
`assets/icon/icon.png` and `icon_foreground.png` for a real design
whenever one exists, then re-run `dart run flutter_launcher_icons`.

### Signing keystore — READ THIS
Generated a real release keystore:
`android/app/upload-keystore.jks`, alias `recall_upload`.
Password (same for store and key): `tv8Q9PE65zAIRYGpQuDxBAwe`
(also saved in `android/key.properties`, which is gitignored).

**This project has no git repository at all** (verified — `git status`
fails). That means this keystore exists *only* as a local file on this one
machine, with zero backup anywhere. If this disk is lost before the app is
first published, the keystore is unrecoverable, and along with it the
ability to ever again publish an update to the app under this identity.

> **Action needed from you:** copy `android/app/upload-keystore.jks` and
> `android/key.properties` to a password manager or secure backup *before*
> ever uploading to Play Console. This has not been done yet.

`android/app/build.gradle.kts` now signs release builds with this keystore
when `key.properties` is present, falling back to the debug key otherwise
(so a fresh checkout without the secrets still builds locally).

### Privacy policy
Drafted at `PRIVACY_POLICY.md` — no account, all data local, the one-time
AI-model download sends no flashcard content anywhere, and Sentry crash
reports are described precisely (stack trace + device/OS/app version only).

> **Action needed from you:** this needs to be hosted somewhere with a
> public URL (GitHub Pages is a free option) — Play Console requires a URL
> in the listing, not just a file in the repo.

### Crash reporting (Sentry)
`sentry_flutter` is added and wired into `main.dart`, but with an **empty
DSN** — Sentry's SDK quietly no-ops with an empty DSN rather than failing,
so this ships safely as-is.

> **Action needed from you:** create a free account at sentry.io, grab the
> project DSN, and give it to me — I'll drop it into the `_kSentryDsn`
> constant in `lib/main.dart`. (A DSN is safe to hardcode in client code,
> unlike an API key — it only lets the SDK send events, not read anything.)

### A real build failure, fixed
`flutter build apk --release` failed on `sentry_flutter`'s own Kotlin
compile step: it hardcodes an old Kotlin "language version" (1.6) that the
newer Kotlin compiler (bumped earlier in this session to clear an unrelated
warning) no longer accepts *at all* — not just deprecated, a hard error.
Fixed by forcing a modern language version across every plugin module from
the root `android/build.gradle.kts`, overriding whatever each individual
plugin requests internally. If any other plugin hits the same "Language
version 1.6 is no longer supported" error later, this is already fixed by
that same override.

### Verified for real
`flutter build apk --release` succeeded (155.1MB — large partly from
bundling multiple ABIs of native libraries; worth using `--split-per-abi`
or an `.aab` for the actual Play Console upload to cut download size).
Confirmed with `apksigner verify --print-certs` that the APK is genuinely
signed with the real upload keystore (`CN=Recall, OU=wkdim`), not the debug
key. Full test suite (200 tests) and `flutter analyze` both still clean
after every change in this section.

### Still open
- Store listing content — description, screenshots, graphics. None of this
  exists yet.
- Hosting the privacy policy at a real URL.
- **Backing up the keystore** (see above — this is the important one).
- Getting a real Sentry DSN.
- iOS Podfile / deployment-target work — still deferred, since there's no
  Mac in this dev environment to build or verify against.
