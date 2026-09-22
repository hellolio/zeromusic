import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:zeromusic/data/app_providers.dart';
import 'package:zeromusic/data/database/app_database.dart';
import 'package:zeromusic/main.dart';
import 'package:zeromusic/services/audio/audio_engine.dart';
import 'package:zeromusic/services/audio/audio_engine_provider.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/mini_player/mini_player.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';
import 'support/in_memory_preferences_store.dart';

/// 创建空的内存测试库。
Future<AppDatabase> createTestDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}

/// 包装整个应用。默认注入内存假播放引擎与内存偏好存储（同策略：不触达真实平台）。
/// 默认开启减弱动效，避免均衡动画在测试中无限循环。
/// [overrides] 注入数据库/音频等 provider。
/// 需要自定义播放引擎时使用 [audioEngine] 参数，需要自定义偏好存储时使用
/// [preferencesStore] 参数，不要通过 [overrides] 注入同名 provider。
Widget wrapApp({
  List<Override> overrides = const [],
  AudioEngine? audioEngine,
  PreferencesStore? preferencesStore,
}) {
  return ProviderScope(
    overrides: [
      audioEngineProvider.overrideWithValue(audioEngine ?? FakeAudioEngine()),
      preferencesStoreProvider
          .overrideWithValue(preferencesStore ?? InMemoryPreferencesStore()),
      ...overrides,
    ],
    child: const _NoAnimations(child: MyApp()),
  );
}

/// 复制媒体查询并开启减弱动效（保留尺寸等其它属性）。
class _NoAnimations extends StatelessWidget {
  const _NoAnimations({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.maybeOf(context);
    final next = data?.copyWith(disableAnimations: true) ?? const MediaQueryData();
    return MediaQuery(data: next, child: child);
  }
}

/// 数据库助记 override。
Override databaseOverride(AppDatabase db) =>
    databaseProvider.overrideWithValue(db);

/// 点按迷你条非按钮区（封面）推入全屏播放页。
///
/// 为什么不点几何中心：桌面胶囊加宽至 440 后控制行（五个 40×40 按钮、
/// 含命中扩展）占据右侧 220px，几何中心恰好落在 ⏮ 按钮命中区内，
/// 点中心会触发“上一首”而非打开播放页；封面（局部 x≈16-56）始终是安全热区。
Future<void> tapMiniPlayerToOpenPlayer(WidgetTester tester) async {
  final topLeft = tester.getTopLeft(find.byType(MiniPlayer));
  final centerDy = tester.getCenter(find.byType(MiniPlayer)).dy;
  await tester.tapAt(Offset(topLeft.dx + 36, centerDy));
}

/// 测试用内存假数据层 override：替换 repository，使 widget 测试完全不触达 drift。
List<Override> fakeDataLayerOverrides(FakeDataLayer layer) => [
      mediaRepositoryProvider.overrideWithValue(layer.mediaRepository),
      tagRepositoryProvider.overrideWithValue(layer.tagRepository),
      lyricsRepositoryProvider.overrideWithValue(layer.lyricsRepository),
    ];