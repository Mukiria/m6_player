import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One of the m6 player's own icons (assets/icons/, from branding/m6-player-icons):
/// home, music, radio, videos, heart or new. In the brand blue gradient, or in
/// one flat [color] (for sitting on a coloured background).
class M6Icon extends StatelessWidget {
  final String name; // 'home', 'music', 'radio', 'videos', 'heart' or 'new'
  final double size;
  final Color? color;

  const M6Icon(this.name, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    Color? flat = color;
    return SvgPicture.asset(
      'assets/icons/m6-$name-${flat == null ? 'light' : 'mono'}.svg',
      width: size,
      height: size,
      colorFilter: flat == null ? null : ColorFilter.mode(flat, BlendMode.srcIn),
    );
  }
}
