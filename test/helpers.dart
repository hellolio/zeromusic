import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:zeromusic/data/app_providers.dart';
import 'package:zeromusic/data/database/app_database.dart';
import 'package:zeromusic/main.dart';

import 'support/fake_data_layer.dart';

/// 创建空的内存测试库。
Future<AppDatabase> createTestDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}

/// 包装整个应用。默认开启减弱动效，避免均衡动画在测试中无限循环。
/// [overrides] 注入数据库/音频等 provider。
Widget wrapApp({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
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

/// 测试用内存假数据层 override：替换 repository，使 widget 测试完全不触达 drift。
List<Override> fakeDataLayerOverrides(FakeDataLayer layer) => [
      mediaRepositoryProvider.overrideWithValue(layer.mediaRepository),
      tagRepositoryProvider.overrideWithValue(layer.tagRepository),
    ];