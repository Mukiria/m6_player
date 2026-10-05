import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the full M6 Player privacy policy lives (on msixv.com, M6V's site).
const String privacyPolicyUrl = 'https://msixv.com/games/m6-player/privacy-policy';

/// A short, offline summary of what stays on the phone and what goes online,
/// with a link to the full policy at the bottom.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text("Privacy policy")),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          Text("Your music stays on your phone", style: text.titleLarge),
          SizedBox(height: 12),
          Text(
            "M6 Player has no accounts, no ads, no analytics and no crash reporting. "
            "We never receive your information.",
          ),
          SizedBox(height: 20),
          Text("Stays on your phone", style: text.titleMedium),
          SizedBox(height: 8),
          _Point(Icons.library_music_outlined, "Your music, videos and playlists, with any cover photos you choose."),
          _Point(Icons.settings_outlined, "Favourites, play counts, settings and the PIN for Hidden (stored as a one-way hash)."),
          SizedBox(height: 20),
          Text("Goes online", style: text.titleMedium),
          SizedBox(height: 8),
          _Point(
            Icons.radio_outlined,
            "Radio only. Looking up stations sends the country (or genre you search) to radio-browser.info, "
            "and a playing station streams from its own server. Both can see your phone's IP address.",
          ),
          SizedBox(height: 20),
          Text("Only when you choose", style: text.titleMedium),
          SizedBox(height: 8),
          _Point(
            Icons.wifi_tethering,
            "File transfer goes straight to the other phone over Wi-Fi Direct, not the internet. "
            "Share and Back up send things only to the app you pick.",
          ),
          SizedBox(height: 28),
          FilledButton.icon(
            icon: Icon(Icons.open_in_new),
            label: Text("Read the full policy"),
            onPressed: () => _openFullPolicy(context),
          ),
          SizedBox(height: 8),
          Text("msixv.com/games/m6-player/privacy-policy", textAlign: TextAlign.center, style: text.bodySmall),
        ],
      ),
    );
  }

  Future<void> _openFullPolicy(BuildContext context) async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $privacyPolicyUrl")));
    }
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Icon(icon, size: 22), SizedBox(width: 12), Expanded(child: Text(text))],
      ),
    );
  }
}
