import 'package:flutter/material.dart';

/// A tab's background photo, under a wash of the theme's background colour:
/// strong at the top where the lists are, lighter at the bottom so the
/// picture shows through. The tab's own Scaffold and AppBar must be transparent.
class TabBackground extends StatelessWidget {
  final String image;
  final Widget child;

  const TabBackground({super.key, required this.image, required this.child});

  @override
  Widget build(BuildContext context) {
    Color wash = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(image, fit: BoxFit.cover, alignment: Alignment.bottomCenter),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [wash.withValues(alpha: 0.88), wash.withValues(alpha: 0.78), wash.withValues(alpha: 0.45)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
