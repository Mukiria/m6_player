import 'package:flutter/material.dart';

/// Brand colours, taken from the m6 player logo.
const Color brandBlue = Color(0xFF3B82F6);
const Color brandBlueDark = Color(0xFF2563EB); // Accent on light backgrounds (better contrast)
const Color brandBlueLight = Color(0xFF60A5FA); // Accent on dark backgrounds
const Color brandNavy = Color(0xFF0B1533);
const Color brandNavyRaised = Color(0xFF131F45); // Bars and sheets in dark mode
const Color brandOrange = Color(0xFFF1552C); // The bottom navigation block and the active buttons

/// The fill of an idle button or tab pill: a very transparent white on dark
/// backgrounds, a very transparent black on light ones. Active ones are solid [brandOrange].
Color buttonFill(Brightness brightness) =>
    brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06);

/// Clean light theme: white background, black text, blue only for what is selected or playing.
ThemeData lightTheme() {
  ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    primary: brandBlueDark,
    surface: Colors.white,
  );
  return _base(scheme).copyWith(scaffoldBackgroundColor: Colors.white);
}

/// Dark theme on the logo's navy.
ThemeData darkTheme() {
  ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: Brightness.dark,
    primary: brandBlueLight,
    surface: brandNavy,
    surfaceContainer: brandNavyRaised,
  );
  return _base(scheme).copyWith(scaffoldBackgroundColor: brandNavy);
}

ThemeData _base(ColorScheme scheme) {
  return ThemeData(
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(),
      side: BorderSide.none,
      showCheckmark: false,
      color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brandOrange : buttonFill(scheme.brightness)),
      labelStyle: TextStyle(color: scheme.onSurface),
    ),
    // Orange bar with white icons in both themes; the selected tab gets a soft white pill.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: brandOrange,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.white24,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? Colors.white : Colors.white.withValues(alpha: 0.8),
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? Colors.white : Colors.white.withValues(alpha: 0.8),
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.normal,
          )),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
  );
}
