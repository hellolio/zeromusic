import 'dart:async';
import 'dart:ui' show Size;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/desktop_lyrics/lyric_window_resize_gate.dart';

void main() {
  final s66 = Size(720, 66);
  final s70 = Size(720, 70);
  final s96 = Size(720, 96);

  test('TC-39 去抖窗口内多次变更：只应用最新值一次', () {
    fakeAsync((async) {
      final applied = <Size>[];
      final gate = LyricWindowResizeGate(
        apply: (size) async => applied.add(size),
      );
      addTearDown(gate.dispose);

      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 50));
      gate.schedule(s70); // 150ms 内变更 → 重置计时
      async.elapse(const Duration(milliseconds: 50));
      gate.schedule(s96);
      // 去抖窗口未过：尚未应用。
      async.elapse(const Duration(milliseconds: 100));
      expect(applied, isEmpty);
      async.elapse(const Duration(milliseconds: 100));
      expect(applied, [s96]);
    });
  });

  test('TC-39 去抖窗口无变更：恰好应用一次，不再重复', () {
    fakeAsync((async) {
      final applied = <Size>[];
      final gate = LyricWindowResizeGate(
        apply: (size) async => applied.add(size),
      );
      addTearDown(gate.dispose);

      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 500));
      expect(applied, [s66]);
      // 时间继续流逝不产生重复应用。
      async.elapse(const Duration(seconds: 2));
      expect(applied, [s66]);
    });
  });

  test('TC-39 在途串行：setSize 不并发，完成后排队项落地', () {
    fakeAsync((async) {
      final applied = <Size>[];
      final completers = <Completer<void>>[];
      final gate = LyricWindowResizeGate(
        apply: (size) {
          applied.add(size);
          final completer = Completer<void>();
          completers.add(completer);
          return completer.future;
        },
      );
      addTearDown(gate.dispose);

      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66]); // 第一笔在途（未 complete）

      // 在途期间新请求：不得并发发起。
      gate.schedule(s70);
      async.elapse(const Duration(milliseconds: 500));
      expect(applied, [s66]);

      // 第一笔完成 → 排队项去抖后落地。
      completers.first.complete();
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66, s70]);
    });
  });

  test('TC-39 幂等去重：与已应用值相同则忽略；reset 后强制重放', () {
    fakeAsync((async) {
      final applied = <Size>[];
      final gate = LyricWindowResizeGate(
        apply: (size) async => applied.add(size),
      );
      addTearDown(gate.dispose);

      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66]);

      // 与已应用值相同 → 忽略（复用路径 reconfigure 之外的常规节流）。
      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66]);

      // 窗口被外部改回档位尺寸后 reset → 同值也重放。
      gate.reset();
      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66, s66]);
    });
  });

  test('TC-39 apply 抛异常不影响后续调度', () {
    fakeAsync((async) {
      final applied = <Size>[];
      final gate = LyricWindowResizeGate(
        apply: (size) async {
          applied.add(size);
          throw Exception('platform unavailable');
        },
      );
      addTearDown(gate.dispose);

      gate.schedule(s66);
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66]);

      gate.schedule(s70);
      async.elapse(const Duration(milliseconds: 200));
      expect(applied, [s66, s70]);
    });
  });

  test('TC-39 dispose：取消待应用的定时器', () {
    fakeAsync((async) {
      final applied = <Size>[];
      final gate = LyricWindowResizeGate(
        apply: (size) async => applied.add(size),
      );
      gate.schedule(s66);
      gate.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(applied, isEmpty);
    });
  });
}
