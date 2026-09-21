import 'dart:async';

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lyric_bar_messenger.dart';
import 'lyric_window_desktop.dart';

/// 桌面歌词条窗口的抽象接口（构架 §6 铁律：平台细节全部藏在实现后）。
///
/// 业务层（控制器 / 设置页）只依赖本接口；测试注入 fake。
abstract class LyricWindowApi {
  /// 歌词条窗口当前是否处于打开（可见）状态。
  bool get isOpen;

  /// 打开（或显示）歌词条窗口；已打开时幂等（仅重新显示）。
  Future<void> open(LyricWindowConfig config);

  /// 关闭（隐藏）歌词条窗口；未打开时幂等。窗口复用，不销毁引擎。
  Future<void> close();

  /// 配置变化（字号 / 主题 / 语言 / 位置）时更新窗口；未变化时幂等跳过。
  Future<void> configure(LyricWindowConfig config);

  /// 推送当前展示状态（fire & forget；行变化 / 切歌时由控制器调用）。
  void pushState(LyricBarStateMessage state);

  /// 恢复默认位置（清掉自定义偏移，回到底部居中偏下）。
  Future<void> recenter();

  /// 歌词条回传事件流：✕ 关闭 / 拖动后位置。
  Stream<LyricBarHostEvent> get events;

  /// 当前平台点击歌词条是否会抢焦点（Win/Linux 已知限制，设置页提示用）。
  bool get stealsFocusOnClick;

  /// 释放资源（provider 销毁时调用）。
  void dispose();
}

/// 平台实现注入点。
///
/// - 桌面端：真实多窗口实现。
/// - 其余平台：永不打开的空实现（保持依赖可注入、测试零平台触碰）。
final lyricWindowApiProvider = Provider<LyricWindowApi>((ref) {
  final api = _createPlatformApi();
  ref.onDispose(api.dispose);
  return api;
});

LyricWindowApi _createPlatformApi() {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    return LyricWindowDesktop();
  }
  return _UnsupportedLyricWindowApi();
}

/// 非桌面平台的空实现：所有操作都是 no-op。
class _UnsupportedLyricWindowApi implements LyricWindowApi {
  final _events = StreamController<LyricBarHostEvent>.broadcast();

  @override
  bool get isOpen => false;

  @override
  Future<void> open(LyricWindowConfig config) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> configure(LyricWindowConfig config) async {}

  @override
  void pushState(LyricBarStateMessage state) {}

  @override
  Future<void> recenter() async {}

  @override
  Stream<LyricBarHostEvent> get events => _events.stream;

  @override
  bool get stealsFocusOnClick => false;

  @override
  void dispose() => unawaited(_events.close());
}
