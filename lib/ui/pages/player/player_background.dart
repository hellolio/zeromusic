import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../services/preferences/preferences_controller.dart';

/// 由种子确定性派生的一组高饱和鲜艳色板。
///
/// 同一 [seed] 恒得同一色板（同曲播放过程中背景稳定），不同 [seed] 得不同色板
/// （切歌后换一批颜色 → 五彩斑斓）。纯函数，可单测。
List<Color> pickPalette(int seed, {int count = 6}) {
  final base = _fract(math.sin(seed * 0.61803) * 10000.0);
  final h1 = _fract(base + 0.61803);
  final h2 = _fract(base + 0.333);
  final sat = 0.70 + 0.25 * _fract(base + 0.17);
  final val = 0.86 + 0.14 * _fract(base + 0.71);
  return List.generate(count, (i) {
    final t = i / count;
    final hue = (h1 + t * 0.9 + h2 * 0.5 + i * 0.137) % 1.0 * 360.0;
    return HSVColor.fromAHSV(1.0, hue, sat - t * 0.18, val - t * 0.1).toColor();
  });
}

/// 单个彩色光斑：归一化位置 [x]/[y]（可略超 [0,1] 以覆盖边缘）、
/// 相对较小边的尺寸比例 [size]、颜色、漂移相位。
class PaletteBlob {
  const PaletteBlob({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.phase,
  });

  final double x;
  final double y;
  final double size;
  final Color color;
  final double phase;
}

/// 由种子确定性派生一组重叠彩色光斑（同一 [seed] 恒同，切歌即换一批）。
List<PaletteBlob> pickBlobs(int seed, List<Color> palette, {int count = 8}) {
  return List.generate(count, (i) {
    return PaletteBlob(
      x: _hash(seed, i) * 1.3 - 0.15,
      y: _hash(seed, i + 101) * 1.3 - 0.15,
      size: 0.6 + _hash(seed, i + 23) * 1.1,
      color: palette[(seed * 3 + i * 5) % palette.length],
      phase: _hash(seed, i + 61) * math.pi * 2,
    );
  });
}

/// 背景效果档位 → 渲染参数（效果与能耗权衡的配置中心）。
class BackgroundEffectConfig {
  const BackgroundEffectConfig({
    required this.paletteCount,
    required this.blobCount,
    required this.blurSigma,
    required this.hueShift,
    required this.wanderScale,
    required this.playingCycle,
    required this.pausedCycle,
  });

  /// 参与渲染的色板颜色数量。
  final int paletteCount;

  /// 彩色光斑数量。
  final int blobCount;

  /// 整层磨砂模糊强度（高斯 sigma）。
  final double blurSigma;

  /// 每动画周期色相整体漂移的量（圈数，0 表示不漂移）。
  final double hueShift;

  /// 光斑中心游走幅度（相对屏幕宽/高的比例）。
  final double wanderScale;

  /// 播放中一个变色周期时长。
  final Duration playingCycle;

  /// 暂停时一个变色周期时长（呼吸变慢）。
  final Duration pausedCycle;
}

/// 三档配置：省电最克制，绚彩最华丽，均衡（默认）居中。
BackgroundEffectConfig backgroundEffectConfig(BackgroundEffectLevel level) {
  switch (level) {
    case BackgroundEffectLevel.powerSaver:
      return const BackgroundEffectConfig(
        paletteCount: 4,
        blobCount: 5,
        blurSigma: 44,
        hueShift: 0.25,
        wanderScale: 0.02,
        playingCycle: Duration(seconds: 18),
        pausedCycle: Duration(seconds: 45),
      );
    case BackgroundEffectLevel.balanced:
      return const BackgroundEffectConfig(
        paletteCount: 6,
        blobCount: 8,
        blurSigma: 96,
        hueShift: 0.5,
        wanderScale: 0.06,
        playingCycle: Duration(seconds: 14),
        pausedCycle: Duration(seconds: 36),
      );
    case BackgroundEffectLevel.vivid:
      return const BackgroundEffectConfig(
        paletteCount: 8,
        blobCount: 12,
        blurSigma: 132,
        hueShift: 1.0,
        wanderScale: 0.10,
        playingCycle: Duration(seconds: 10),
        pausedCycle: Duration(seconds: 30),
      );
  }
}

double _fract(double x) => x - x.floorToDouble();

double _hash(int seed, int salt) =>
    _fract(math.sin((seed + salt) * 12.9898) * 43758.5453);

/// 把整个色板色相整体漂移 [degrees] 度。
List<Color> _hueShifted(List<Color> palette, double degrees) {
  if (degrees == 0) return palette;
  return palette.map((c) {
    final hsv = HSVColor.fromColor(c);
    return hsv.withHue((hsv.hue + degrees) % 360.0).toColor();
  }).toList();
}

/// 全屏变色背景（Apple Music 风格：彩色光斑被整层磨砂模糊）。
///
/// - 基座：按 [BackgroundEffectLevel] 生成 N 个重叠彩色光斑（径向渐变），
///   外包 [ImageFiltered] 高斯模糊 —— 颜色随之被模糊成毛玻璃质感；
///   色相缓慢整体漂移 + 光斑中心轻微游走 → 「一直在变化」。
/// - 有封面：上方叠加**半透明**模糊封面大图（光斑可透出）+
///   随节拍漂移的呼吸变色层。
/// - 动画循环速度按档位：播放中 10–18s/圈，暂停 30–45s/圈（呼吸变慢）；
///   无曲目或减弱动效时静态（模糊质地保留，仅不动画）。
class AnimatedPaletteBackground extends StatefulWidget {
  const AnimatedPaletteBackground({
    super.key,
    required this.seed,
    required this.isPlaying,
    required this.hasTrack,
    this.level = BackgroundEffectLevel.balanced,
    this.coverPath,
  });

  final int seed;
  final bool isPlaying;
  final bool hasTrack;

  /// 背景效果档位（设置页可调，均衡效果与能耗）。
  final BackgroundEffectLevel level;

  final String? coverPath;

  @override
  State<AnimatedPaletteBackground> createState() =>
      _AnimatedPaletteBackgroundState();
}

class _AnimatedPaletteBackgroundState extends State<AnimatedPaletteBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: backgroundEffectConfig(widget.level).playingCycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AnimatedPaletteBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.hasTrack != widget.hasTrack ||
        oldWidget.level != widget.level) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _syncAnimation() {
    if (_reduced || !widget.hasTrack) {
      _controller.stop();
      _controller.value = 0;
      return;
    }
    final cfg = backgroundEffectConfig(widget.level);
    _controller.duration = widget.isPlaying ? cfg.playingCycle : cfg.pausedCycle;
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  Widget _blobWidget(PaletteBlob b, Size size, double value, double wander) {
    final cx = b.x * size.width + math.sin(2 * math.pi * value + b.phase) * wander * size.width;
    final cy = b.y * size.height + math.cos(2 * math.pi * value + b.phase) * wander * size.height;
    final d = b.size * math.min(size.width, size.height);
    return Positioned(
      left: cx - d / 2,
      top: cy - d / 2,
      width: d,
      height: d,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              b.color.withValues(alpha: 0.65),
              b.color.withValues(alpha: 0.28),
              b.color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = pickPalette(
      widget.seed,
      count: backgroundEffectConfig(widget.level).paletteCount,
    );
    final hasCover =
        widget.coverPath != null && widget.coverPath!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final cfg = backgroundEffectConfig(widget.level);
            final value = _controller.value;
            final shifted =
                _hueShifted(palette, value * cfg.hueShift * 360.0);
            final blobs = pickBlobs(widget.seed, shifted, count: cfg.blobCount);
            return ImageFiltered(
              key: const ValueKey('palette-blur-layer'),
              imageFilter: ImageFilter.blur(
                sigmaX: cfg.blurSigma,
                sigmaY: cfg.blurSigma,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 底衬：色板首色的深色填充，保证全屏被色彩覆盖无空隙。
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(palette[0], Colors.black, 0.4),
                          ),
                        ),
                      ),
                      for (final blob in blobs)
                        _blobWidget(blob, size, value, cfg.wanderScale),
                    ],
                  );
                },
              ),
            );
          },
        ),
        if (hasCover)
          _CoverLayer(coverPath: widget.coverPath!, animation: _controller),
        // 底部暗化，保证文字可读。
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black26, Colors.black54],
              stops: [0.55, 0.82, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// 有封面时的半透明模糊大图 + 跟随节拍的呼吸变色层。
///
/// 封面以半透明（约 0.55）方式叠在动画光斑之上：既保留封面的模糊背景，
/// 又能让底层的光斑流动透出；上方的色相渐变层随 [animation] 漂移呼吸。
class _CoverLayer extends StatelessWidget {
  const _CoverLayer({required this.coverPath, required this.animation});

  /// 封面模糊图的整体不透明度（越低，底层光斑流动越明显）。
  static const double _coverOpacity = 0.55;

  /// 变色层每个周期的色相漂移量（圈数）。
  static const double _tintHueShift = 0.5;

  final String coverPath;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final palette = pickPalette(coverPath.hashCode);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 半透明模糊封面：底层彩色光斑可从其背后透出。
        Opacity(
          opacity: _coverOpacity,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        // 呼吸变色层：色相随动画整体漂移，与背景光斑同步流动。
        AnimatedBuilder(
          animation: animation,
          builder: (_, _) {
            final shifted =
                _hueShifted(palette, animation.value * _tintHueShift * 360.0);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    shifted[0].withValues(alpha: 0.32),
                    shifted[2].withValues(alpha: 0.28),
                    shifted[4].withValues(alpha: 0.32),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}