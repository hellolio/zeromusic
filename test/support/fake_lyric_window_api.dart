import 'dart:async';

import 'package:flutter/animation.dart' show Offset;

import 'package:zeromusic/services/desktop_lyrics/lyric_bar_messenger.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_window_api.dart';

/// 测试用假歌词条窗口 API：记录每次调用，支持手动发出回传事件。
class FakeLyricWindowApi implements LyricWindowApi {
  bool openState = false;

  /// 每次 open 收到的配置（按调用顺序）。
  final List<LyricWindowConfig> openedConfigs = [];

  /// 每次 configure 收到的配置（含被幂等跳过前的调用）。
  final List<LyricWindowConfig> configuredConfigs = [];

  /// 每次 pushState 收到的状态（按调用顺序）。
  final List<LyricBarStateMessage> pushedStates = [];

  int closeCount = 0;
  int recenterCount = 0;

  /// 模拟当前平台点击是否抢焦点（设置页提示文案开关）。
  bool stealsFocus = false;

  final _events = StreamController<LyricBarHostEvent>.broadcast();

  @override
  bool get isOpen => openState;

  @override
  Future<void> open(LyricWindowConfig config) async {
    openState = true;
    openedConfigs.add(config);
  }

  @override
  Future<void> close() async {
    openState = false;
    closeCount++;
  }

  @override
  Future<void> configure(LyricWindowConfig config) async {
    configuredConfigs.add(config);
  }

  @override
  void pushState(LyricBarStateMessage state) => pushedStates.add(state);

  @override
  Future<void> recenter() async => recenterCount++;

  @override
  Stream<LyricBarHostEvent> get events => _events.stream;

  @override
  bool get stealsFocusOnClick => stealsFocus;

  /// 模拟歌词条内 ✕ 被点击。
  void emitClosed() => _events.add(const LyricBarClosedEvent());

  /// 模拟歌词条子窗口引擎就绪（push handler 已注册）。
  void emitReady() => _events.add(const LyricBarReadyEvent());

  /// 模拟歌词条拖动结束回传位置。
  void emitPosition(Offset position) =>
      _events.add(LyricBarPositionSavedEvent(position));

  /// 模拟歌词条内播放/暂停按钮被点击。
  void emitTogglePlay() => _events.add(const LyricBarTogglePlayEvent());

  /// 模拟歌词条内下一曲按钮被点击。
  void emitNext() => _events.add(const LyricBarNextEvent());

  /// 模拟歌词条内上一曲按钮被点击。
  void emitPrevious() => _events.add(const LyricBarPreviousEvent());

  /// 模拟歌词条音量滑杆提交。
  void emitVolume(double volume) =>
      _events.add(LyricBarVolumeChangedEvent(volume));

  @override
  void dispose() => unawaited(_events.close());
}
