import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Matches the web `AudioPlayingIndicator` + `.subscriber-audio-bar` animation:
/// 6 bars, 750ms ease-in-out loop, stagger ~95ms (`globals.css`).
class SubscriberAudioBars extends StatefulWidget {
  const SubscriberAudioBars({
    super.key,
    required this.playing,
    this.maxBarHeight = 28,
    this.barWidth = 6,
    this.gap = 6,
  });

  final bool playing;
  final double maxBarHeight;
  final double barWidth;
  final double gap;

  @override
  State<SubscriberAudioBars> createState() => _SubscriberAudioBarsState();
}

class _SubscriberAudioBarsState extends State<SubscriberAudioBars>
    with SingleTickerProviderStateMixin {
  static const int _n = 6;
  static const Duration _period = Duration(milliseconds: 750);
  static const double _staggerFrac = 95 / 750;

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
    if (widget.playing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SubscriberAudioBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !oldWidget.playing) {
      _controller.repeat();
    } else if (!widget.playing && oldWidget.playing) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Same shape as CSS keyframes: 0%/100% → 0.35, 50% → 1.0, ease-in-out.
  double _scaleY(double phase) {
    final p = phase % 1.0;
    if (p < 0.5) {
      final t = Curves.easeInOut.transform(p * 2);
      return lerpDouble(0.35, 1.0, t)!;
    }
    final t = Curves.easeInOut.transform((p - 0.5) * 2);
    return lerpDouble(1.0, 0.35, t)!;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.playing ? 'Sound playing' : 'Sound muted or idle',
      child: SizedBox(
        height: 64,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final v = widget.playing ? _controller.value : 0.0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_n, (i) {
                final phase = v + i * _staggerFrac;
                final scale = widget.playing ? _scaleY(phase) : 1.0;
                final h = widget.playing
                    ? (widget.maxBarHeight * scale).clamp(8.0, widget.maxBarHeight)
                    : 8.0;
                final color = widget.playing
                    ? AppColors.primary
                    : AppColors.mutedForeground.withValues(alpha: 0.35);
                return Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : widget.gap / 2,
                    right: i == _n - 1 ? 0 : widget.gap / 2,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: widget.barWidth,
                      height: h,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(widget.barWidth / 2),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
