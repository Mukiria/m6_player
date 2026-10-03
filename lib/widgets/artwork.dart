import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'm6_icon.dart';

/// A song's cover art, or a placeholder in the brand colours when it has none:
/// a music note for songs, a radio for stations.
class Artwork extends StatelessWidget {
  final double size;
  final bool isRadio;
  final bool round;

  /// The placeholder's icon when there's no cover (default: a note, or a radio).
  final IconData? icon;

  /// An m6 icon name (see M6Icon) to use in the placeholder instead.
  final String? m6Icon;

  /// Cover image saved from the song's tags, if any.
  final String? coverPath;

  const Artwork({super.key, required this.size, this.isRadio = false, this.round = false, this.coverPath, this.icon, this.m6Icon});

  @override
  Widget build(BuildContext context) {
    BorderRadius? radius = round ? null : BorderRadius.circular(size * 0.08);
    String? cover = coverPath;
    if (cover != null) {
      int pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
      Widget image = Image.file(
        File(cover),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: pixels, // Decode at display size, not the full (often huge) cover
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _placeholder(radius),
      );
      return round ? ClipOval(child: image) : ClipRRect(borderRadius: radius!, child: image);
    }
    return _placeholder(radius);
  }

  Widget _placeholder(BorderRadius? radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brandNavyRaised, brandBlueDark, Color(0xFF38BDF8)],
        ),
      ),
      child: m6Icon != null
          ? Center(child: M6Icon(m6Icon!, size: size * 0.55, color: Colors.white))
          : Icon(
              icon ?? (isRadio ? Icons.radio : Icons.music_note),
              color: Colors.white,
              size: size * 0.5,
            ),
    );
  }
}
