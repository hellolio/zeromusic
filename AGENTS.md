# AGENTS.md

Flutter local music player (Dart 3.13 / Flutter 3.47). Single package, no monorepo. Riverpod + drift + just_audio, iOS-style UI, adaptive mobile/desktop.

## Commands
- `flutter pub get` — restore deps
- `flutter analyze` — lint/typecheck (lints only `lib/` and `test/`; platform dirs excluded in `analysis_options.yaml`). Must stay clean (repo DoD).
- `flutter test` — full suite must pass (repo DoD). Single file: `flutter test test/playlist_page_test.dart`.
- `dart run build_runner build --delete-conflicting-outputs` — drift codegen; run after editing `lib/data/database/tables.dart` or `app_database.dart`. Never hand-edit `app_database.g.dart`.
- `flutter run` — run app (VS Code launch configs exist, incl. `.widget_preview`).

## Workflow (需求文档/整体构架.md §9 — enforced repo convention)
Per feature: read the module's 需求文档 → write test cases FIRST (in `需求文档/测试用例/<功能名>_测试用例.md`, from `模板_测试用例.md`) → implement → all tests pass → write 开发心得 lessons/pitfalls doc (`需求文档/开发心得/<功能名>_开发心得.md`) → commit both docs with the code. Comments and docs are written in Chinese.

## Project layout
- `lib/core/theme/` — design tokens (`app_tokens.dart`) + light/dark themes (`app_theme.dart`, `AppThemeExtension`). All colors/spacing/radii come from tokens — no hardcoding.
- `lib/core/localization/` — 中/英/日 via `AppStrings`/`AppLanguage` (`app_strings.dart`, `strings_zh/en/ja.dart`, `localizations_delegate.dart`). Access via `context.strings`. Adding a getter requires updating all 3 language files + base class.
- `lib/core/platform/device_type.dart` — `DeviceType` + breakpoint (`AppBreakpoints.desktop` = 840).
- `lib/core/anim/` — unified curves (`app_curves.dart`) + page transition widget (`page_transitions.dart`, `AppPageTransition`).
- `lib/data/` — drift DB (`database/tables.dart`: Songs/Tags/SongsTags/QueueItems/LyricsCache, schemaVersion 1) + repositories (`media/tag/lyrics_repository.dart`) wired in `app_providers.dart`. `databaseProvider` is the injection point; tests use `databaseOverride(db)`.
- `lib/services/audio/` — **播放全部走抽象层**：业务代码只 import `audio_engine.dart`（`AudioEngine` 接口），实现为 `just_audio_engine.dart`；`audio_engine_provider.dart` 是**换引擎的唯一注入点**（新建一个 `implements AudioEngine` 的实现替换即可，业务零改动）。`audio_controller.dart`（Riverpod Notifier，编排队列/自动下一首并镜像引擎流）；`sleep_timer_controller.dart`（睡眠定时，归零自动暂停）；`track.dart`（`Track` 由 `Song` 经 `Track.fromSong` 构造）。
- `lib/services/import/` — sequential import pipeline: copy file → read metadata → save cover → insert into library → tag `来源:xxx`. File IO is injected via providers in `import_io.dart` (`importFilePickerProvider`/`importFileStoreProvider`/`importMetadataExtractorProvider`) — tests swap them for in-memory fakes.
- `lib/services/lyrics/` — LRC parser (`lrc_parser.dart`) + lyrics controller.
- `lib/ui/scaffold/adaptive_scaffold.dart` — responsive skeleton. Mobile: floating glass nav bar (播放列表/导入/设置) + swipeable PageView + mini player above. Desktop: `AppSideBar` (same 3 pages, settings pinned at bottom) + mini player bottom-right. Player page is a FULL-SCREEN ROUTE on both platforms (`opaque: false`, expands from the mini player's real rect) — the only entry is the mini player.
- `lib/ui/mini_player/` — global floating mini player capsule (+ `mini_player_bounce.dart`).
- `lib/ui/pages/` — playlist/player/import/settings are implemented; `video/` is still a placeholder and not in nav.

## Gotchas
- `lib/core/localization/app_strings.dart`: do NOT use `context.strings` above `MaterialApp` (Localizations unavailable) — read `AppLanguage.fromLocale(prefs.locale).strings` instead (as `main.dart` does).
- Production has no demo/fake data and starts with an empty library. Test-only fixtures live in `test/support/demo_fixtures.dart`.
- Playback is REAL: `AudioController` drives an `AudioEngine`; errors surface via `errorStream` and state falls back to paused (no crash). Format support = just_audio native codecs, varies by platform.
- Widget tests must not touch real audio/platform: `wrapApp()` in `test/helpers.dart` overrides `audioEngineProvider` (FakeAudioEngine) and `preferencesStoreProvider` (InMemoryPreferencesStore), and forces `disableAnimations`. To inject custom ones use the `audioEngine:` / `preferencesStore:` params — do NOT re-override them via the `overrides` list (duplicate-provider conflict).
- Widget tests run against the in-memory fake data layer (`fakeDataLayerOverrides()` + `test/support/fake_data_layer.dart`) and never open a drift database. Real drift behavior is covered by pure-Dart tests (`test/database_test.dart`, `test/repository_drift_test.dart`).
- Do NOT `await AppDatabase.close()` inside a `testWidgets` body after `pumpAndSettle`: drift's `StreamQueryStore.close()` awaits fake timers, deadlocking the widget-test (fake-async) environment. Keep drift DB work out of widget tests entirely.
- Test env locale defaults to English — widget tests locate nav destinations by icon, not text, to stay locale-independent.
- `.widget_preview/` is auto-generated by `flutter widget-preview` (gitignored). It is a separate nested Flutter package depending on `zeromusic` via path. Do not hand-edit; it is regenerated.
- Mini player: mobile swipes left/right to change track (drag-follow + spring-back) and swipes up to open the player page; desktop has ⏮/▶/⏭ buttons + scroll-wheel switching. The desktop capsule floats via `Positioned` right/bottom (unbounded width) — size it explicitly.
