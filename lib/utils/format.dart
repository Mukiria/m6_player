/// Formats a duration as mm:ss (or h:mm:ss for an hour or longer).
String formatDuration(Duration duration) {
  String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  if (duration.inHours > 0) return "${duration.inHours}:$minutes:$seconds";
  return "$minutes:$seconds";
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A date as "Sep 20, 2026".
String formatDate(DateTime date) => "${_months[date.month - 1]} ${date.day}, ${date.year}";
