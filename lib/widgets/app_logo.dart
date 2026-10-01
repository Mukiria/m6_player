import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The m6 player logo, in its light or dark version to match the current theme.
class AppLogo extends StatelessWidget {
  final double height;

  const AppLogo({super.key, this.height = 40});

  @override
  Widget build(BuildContext context) {
    bool dark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      dark ? 'assets/branding/logo-dark.svg' : 'assets/branding/logo-light.svg',
      height: height,
      semanticsLabel: 'm6 player',
    );
  }
}
