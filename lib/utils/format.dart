/// Formats a duration as mm:ss (or h:mm:ss for an hour or longer).
String formatDuration(Duration duration) {
  String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  if (duration.inHours > 0) return "${duration.inHours}:$minutes:$seconds";
  return "$minutes:$seconds";
}
