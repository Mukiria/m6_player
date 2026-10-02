import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_settings.dart';

/// Asks for a PIN (4 to 8 digits). Returns it, or null if the user cancels.
Future<String?> askPin(BuildContext context, String title, {String? error}) {
  TextEditingController controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          if (controller.text.length < 4) {
            setState(() => error = "Use 4 to 8 digits");
          } else {
            Navigator.of(context).pop(controller.text);
          }
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            decoration: InputDecoration(errorText: error),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Cancel")),
            TextButton(onPressed: submit, child: Text("OK")),
          ],
        );
      },
    ),
  );
}

/// Checks the Hidden page's PIN, asking again after a wrong one. True when
/// there is no PIN or the right one was entered.
Future<bool> unlockWithPin(BuildContext context) async {
  AppSettings settings = AppSettings.instance;
  if (!settings.hasPin) return true;
  String? error;
  while (context.mounted) {
    String? pin = await askPin(context, "Enter PIN", error: error);
    if (pin == null) return false;
    if (settings.checkPin(pin)) return true;
    error = "Wrong PIN";
  }
  return false;
}

/// Sets a new PIN (typed twice), after checking the current one if there is one.
Future<void> changePin(BuildContext context) async {
  AppSettings settings = AppSettings.instance;
  if (!await unlockWithPin(context) || !context.mounted) return;
  String? first = await askPin(context, "New PIN");
  if (first == null || !context.mounted) return;
  String? second = await askPin(context, "Enter it again");
  if (second == null || !context.mounted) return;
  if (first != second) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("The PINs didn't match")));
    return;
  }
  await settings.setPin(first);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PIN set")));
}

Future<void> removePin(BuildContext context) async {
  if (!await unlockWithPin(context)) return;
  await AppSettings.instance.setPin(null);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PIN removed")));
}
