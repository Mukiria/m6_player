import 'dart:ui';
import 'package:flutter/material.dart';

/// One button in an [OptionsSheet].
class SheetOption {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive; // Shown in red (Delete)

  const SheetOption({required this.icon, required this.label, required this.onTap, this.destructive = false});
}

/// Shows a sheet that slides up from the bottom: full width, rounded top
/// corners, a frosted see-through background, a title (and optional subtitle)
/// at the top and a list of icon buttons below. Tapping a button closes the
/// sheet, then runs it.
Future<void> showOptionsSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leading,
  required List<SheetOption> options,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // Lets the sheet grow to fit all the buttons
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    builder: (sheetContext) => OptionsSheet(
      title: title,
      subtitle: subtitle,
      leading: leading,
      options: [
        for (SheetOption option in options)
          SheetOption(
            icon: option.icon,
            label: option.label,
            destructive: option.destructive,
            onTap: () {
              Navigator.of(sheetContext).pop();
              option.onTap();
            },
          ),
      ],
    ),
  );
}

/// The sheet's look; see [showOptionsSheet].
class OptionsSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<SheetOption> options;

  const OptionsSheet({super.key, required this.title, this.subtitle, this.leading, required this.options});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        // Frosted glass: what's behind shows through, blurred, under a light tint.
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        // Material (not a coloured box) so the buttons' tap ripples show on the tint.
        child: Material(
          color: colors.surface.withValues(alpha: 0.72),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: leading,
                  title: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  subtitle: subtitle == null
                      ? null
                      : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Divider(height: 1, color: colors.outlineVariant.withValues(alpha: 0.6)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (SheetOption option in options)
                        ListTile(
                          leading: Icon(option.icon, color: option.destructive ? colors.error : colors.onSurface),
                          title: Text(option.label,
                              style: TextStyle(color: option.destructive ? colors.error : colors.onSurface)),
                          onTap: option.onTap,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A frosted sheet of details (label and value per row), such as a file's Info.
Future<void> showInfoSheet(BuildContext context, {required String title, required Map<String, String> rows}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    builder: (sheetContext) {
      ColorScheme colors = Theme.of(sheetContext).colorScheme;
      return ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: colors.surface.withValues(alpha: 0.72),
            child: SafeArea(
              top: false,
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  SizedBox(height: 12),
                  for (MapEntry<String, String> row in rows.entries)
                    if (row.value.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 96,
                              child: Text(row.key, style: TextStyle(color: colors.onSurfaceVariant)),
                            ),
                            Expanded(child: SelectableText(row.value)),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
