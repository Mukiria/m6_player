import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/equalizer_screen.dart';
import '../screens/hidden_screen.dart';
import '../screens/search_screen.dart';
import '../screens/transfer_screen.dart';
import '../services/app_settings.dart';
import 'backup_sheet.dart';
import 'options_sheet.dart';
import 'pin_dialog.dart';

/// Where the legal pages live (on msixv.com, M6V's site).
const String privacyPolicyUrl = 'https://msixv.com/games/privacy-policy';
const String termsUrl = 'https://msixv.com/games/terms-of-service';

/// The magnifying glass in the top bar: opens the search page.
class SearchButton extends StatelessWidget {
  const SearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: "Search",
      icon: Icon(Icons.search),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SearchScreen())),
    );
  }
}

/// The ⋮ in the top bar of Music, Radio and Video: equalizer, light/dark mode,
/// hidden & filtered items, receiving files, and the privacy policy and terms.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: "More",
      onSelected: (action) => _open(context, action),
      itemBuilder: (context) => [
        if (Platform.isAndroid) _item("equalizer", Icons.equalizer, "Equalizer"),
        _item("theme", Icons.brightness_6_outlined, "Light / dark mode"),
        _item("hidden", Icons.visibility_off_outlined, "Hidden & filtered"),
        _item("backup", Icons.backup_outlined, "Back up & restore"),
        if (Platform.isAndroid) _item("receive", Icons.download_outlined, "Receive files"),
        PopupMenuDivider(),
        _item("privacy", Icons.privacy_tip_outlined, "Privacy policy"),
        _item("terms", Icons.description_outlined, "Terms of service (EULA)"),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) => PopupMenuItem(
        value: value,
        // Flexible: a long label (or large text setting) wraps instead of overflowing the menu.
        child: Row(children: [Icon(icon, size: 20), SizedBox(width: 12), Flexible(child: Text(label))]),
      );

  void _open(BuildContext context, String action) {
    switch (action) {
      case "equalizer":
        _push(context, const EqualizerScreen());
      case "theme":
        showThemeChooser(context);
      case "hidden":
        unlockWithPin(context).then((ok) {
          if (ok && context.mounted) _push(context, const HiddenScreen());
        });
      case "backup":
        showBackupSheet(context);
      case "receive":
        _push(context, const TransferScreen());
      case "privacy":
        _openLink(context, privacyPolicyUrl);
      case "terms":
        _openLink(context, termsUrl);
    }
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => screen));

  Future<void> _openLink(BuildContext context, String url) async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
    }
  }
}

/// Light / dark mode: follow the phone, or always light or dark. Saved.
Future<void> showThemeChooser(BuildContext context) {
  AppSettings settings = AppSettings.instance;
  ThemeMode current = settings.themeMode;
  IconData mark(ThemeMode mode) => mode == current ? Icons.radio_button_checked : Icons.radio_button_unchecked;
  return showOptionsSheet(
    context,
    title: "Light / dark mode",
    options: [
      SheetOption(
        icon: mark(ThemeMode.system),
        label: "Same as the phone",
        onTap: () => settings.setThemeMode(ThemeMode.system),
      ),
      SheetOption(icon: mark(ThemeMode.light), label: "Light", onTap: () => settings.setThemeMode(ThemeMode.light)),
      SheetOption(icon: mark(ThemeMode.dark), label: "Dark", onTap: () => settings.setThemeMode(ThemeMode.dark)),
    ],
  );
}
