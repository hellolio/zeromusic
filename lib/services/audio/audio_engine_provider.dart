import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine.dart';
import 'just_audio_engine.dart';

/// 播放引擎注入点 —— 换引擎只改这里。
///
/// 例：未来接入 media_kit：
/// ```dart
/// final audioEngineProvider =
///     Provider<AudioEngine>((ref) => MediaKitEngine());
/// ```
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioEngine();
  // 统一在此完成引擎级初始化（just_audio 为 no-op；media_kit 等需要原生初始化）。
  unawaited(engine.init());
  ref.onDispose(() => engine.dispose());
  return engine;
});