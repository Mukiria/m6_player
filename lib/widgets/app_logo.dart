import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../services/player_service.dart';
import 'logo_animation_data.dart';

/// The m6 player logo, in its light or dark version to match the theme.
/// While music, radio or a video is playing it animates like the animated
/// logo SVGs in branding/ (currently: the cable waves; other parts stay
/// still); when playback stops it goes back to the still logo.
class AppLogo extends StatefulWidget {
  final double height;

  const AppLogo({super.key, this.height = 40});

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> with SingleTickerProviderStateMixin {
  final PlayerService _service = PlayerService.instance;
  late final Ticker _ticker = createTicker((elapsed) => _seconds.value = elapsed.inMicroseconds / 1e6);
  final ValueNotifier<double> _seconds = ValueNotifier(0); // Time since the animation started
  StreamSubscription<PlayerState>? _playerState;
  bool _audioPlaying = false;

  bool get _isPlaying => _audioPlaying || _service.videoPlaying.value;

  @override
  void initState() {
    super.initState();
    _playerState = _service.player.playerStateStream.listen((state) {
      _audioPlaying = state.playing && state.processingState != ProcessingState.completed;
      _update();
    });
    _service.videoPlaying.addListener(_update);
  }

  /// Starts the animation from the beginning when playback starts, and stops it when it ends.
  void _update() {
    if (!mounted) return;
    if (_isPlaying && !_ticker.isActive) {
      _seconds.value = 0;
      _ticker.start();
    } else if (!_isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _playerState?.cancel();
    _service.videoPlaying.removeListener(_update);
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool dark = Theme.of(context).brightness == Brightness.dark;
    bool animate = _isPlaying && !MediaQuery.disableAnimationsOf(context); // Respects "remove animations"
    if (!animate) {
      return SvgPicture.asset(
        dark ? 'assets/branding/logo-dark.svg' : 'assets/branding/logo-light.svg',
        height: widget.height,
        semanticsLabel: 'M6 Player',
      );
    }
    LogoTheme theme = dark ? logoDark : logoLight;
    double width = widget.height * logoViewBox[2] / logoViewBox[3];
    return Semantics(
      label: 'M6 Player',
      child: SizedBox(
        width: width,
        height: widget.height,
        child: ValueListenableBuilder<double>(
          valueListenable: _seconds,
          builder: (context, t, _) => _AnimatedLogo(theme: theme, seconds: t, width: width, height: widget.height),
        ),
      ),
    );
  }
}

/// One frame of the animation, [seconds] after it started. Timings come from
/// the animated SVGs' CSS (see logo_animation_data.dart); a part without one
/// stays still.
class _AnimatedLogo extends StatelessWidget {
  final LogoTheme theme;
  final double seconds, width, height;

  const _AnimatedLogo({required this.theme, required this.seconds, required this.width, required this.height});

  /// Progress 0..1 of a step timed as [delay, duration, cubic-bezier x1, y1, x2, y2];
  /// 1 (finished) for a part that doesn't animate.
  double _progress(List<double>? timing) {
    if (timing == null) return 1;
    Cubic curve = Cubic(timing[2], timing[3], timing[4], timing[5]);
    return curve.transform(((seconds - timing[0]) / timing[1]).clamp(0.0, 1.0));
  }

  /// A point in the logo's (root SVG) coordinates, as a fraction of the widget.
  Alignment _align(double x, double y) => Alignment(
        (x - logoViewBox[0]) / logoViewBox[2] * 2 - 1,
        (y - logoViewBox[1]) / logoViewBox[3] * 2 - 1,
      );

  Widget _part(String svg) => SvgPicture.string(svg, width: width, height: height);

  /// An earbud scaling up from where it meets the cable.
  Widget _bud(String svg, double cableEndX, List<double>? timing) {
    if (timing == null) return _part(svg);
    double s = logoWaveTransform[2];
    return Transform.scale(
      scale: _progress(timing),
      alignment: _align(logoWaveTransform[0] + cableEndX * s, logoWaveTransform[1] + 120 * s),
      child: _part(svg),
    );
  }

  /// A word fading in while rising 24 units.
  Widget _word(String svg, List<double>? timing) {
    if (timing == null) return _part(svg);
    double p = _progress(timing);
    return Opacity(
      opacity: p,
      child: Transform.translate(offset: Offset(0, (1 - p) * 24 * height / logoViewBox[3]), child: _part(svg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          size: Size(width, height),
          painter: _WavePainter(theme: theme, seconds: seconds, reveal: _progress(logoCableDraw)),
        ),
        _bud(theme.budLeft, 162, logoBudLeftPop), // The left earbud's group is mirrored, so its cable end is at x 162
        _bud(theme.budRight, 538, logoBudRightPop),
        _word(theme.wordA, logoWordARise),
        _word(theme.wordB, logoWordBRise),
      ],
    );
  }
}

/// The cable: the wave keyframes blended for the current moment (looping every
/// [logoWaveSeconds]), drawn up to [reveal] of its length, with the logo's gradient.
class _WavePainter extends CustomPainter {
  final LogoTheme theme;
  final double seconds, reveal;

  _WavePainter({required this.theme, required this.seconds, required this.reveal});

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal <= 0) return;
    double scale = size.width / logoViewBox[2];
    double tx = logoWaveTransform[0], ty = logoWaveTransform[1], s = logoWaveTransform[2];
    Offset toCanvas(double x, double y) =>
        Offset((tx + x * s - logoViewBox[0]) * scale, (ty + y * s - logoViewBox[1]) * scale);

    // Position in the loop, between keyframe i and i + 1.
    int spans = logoWaveY.length - 1;
    double loop = (seconds % logoWaveSeconds) / logoWaveSeconds * spans;
    int i = loop.floor().clamp(0, spans - 1);
    double f = loop - i;
    List<double> a = logoWaveY[i], b = logoWaveY[i + 1];

    Path wave = Path();
    for (int p = 0; p < logoWaveX.length; p++) {
      Offset point = toCanvas(logoWaveX[p], a[p] + (b[p] - a[p]) * f);
      p == 0 ? wave.moveTo(point.dx, point.dy) : wave.lineTo(point.dx, point.dy);
    }
    if (reveal < 1) {
      ui.PathMetric metric = wave.computeMetrics().first;
      wave = metric.extractPath(0, metric.length * reveal);
    }

    canvas.drawPath(
      wave,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = logoWaveStrokeWidth * s * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          toCanvas(logoWaveGradientX[0], 0),
          toCanvas(logoWaveGradientX[1], 0),
          theme.waveColors,
          theme.waveStops,
        ),
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.seconds != seconds || old.reveal != reveal || old.theme != theme;
}
