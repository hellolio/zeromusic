import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/pages/player/player_background.dart';

void main() {
  group('backgroundEffectConfig', () {
    test('三档模糊强度逐档增强（更朦胧的磨砂质感）', () {
      expect(
        backgroundEffectConfig(BackgroundEffectLevel.powerSaver).blurSigma,
        44,
      );
      expect(
        backgroundEffectConfig(BackgroundEffectLevel.balanced).blurSigma,
        96,
      );
      expect(
        backgroundEffectConfig(BackgroundEffectLevel.vivid).blurSigma,
        132,
      );
    });
  });

  group('pickPalette', () {
    test('同一种子恒得同一色板，不同种子得不同色板', () {
      expect(pickPalette(42), pickPalette(42));
      expect(pickPalette(42), isNot(equals(pickPalette(7))));
    });

    test('色板数量可由参数控制', () {
      expect(pickPalette(42, count: 4).length, 4);
      expect(pickPalette(42, count: 8).length, 8);
    });
  });

  group('pickBlobs', () {
    test('同一种子恒同，不同种子位置/相位不同', () {
      final palette = pickPalette(42);
      final a = pickBlobs(42, palette);
      final b = pickBlobs(42, palette);
      final c = pickBlobs(7, palette);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
        expect(a[i].size, b[i].size);
        expect(a[i].color, b[i].color);
        expect(a[i].phase, b[i].phase);
      }
      expect(a.first.x, isNot(equals(c.first.x)));
    });
  });
}
