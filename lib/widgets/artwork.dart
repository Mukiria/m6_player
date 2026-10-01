import 'package:flutter/material.dart';
import '../theme.dart';

/// Placeholder cover art in the brand colours: a music note for songs, a radio
/// for stations. (Reading real cover art from the MP3s can replace this later.)
class Artwork extends StatelessWidget {
  final double size;
  final bool isRadio;
  final bool round;

  const Artwork({super.key, required this.size, this.isRadio = false, this.round = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(size * 0.08),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brandNavyRaised, brandBlueDark, Color(0xFF38BDF8)],
        ),
      ),
      child: Icon(
        isRadio ? Icons.radio : Icons.music_note,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}
