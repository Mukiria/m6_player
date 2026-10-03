import 'package:flutter/material.dart';
import '../theme.dart';

/// The tab buttons under a top bar: each a rounded pill with a very transparent
/// fill, the open one solid orange (no underline). Works with the surrounding
/// DefaultTabController, like TabBar.
class PillTabBar extends StatelessWidget implements PreferredSizeWidget {
  final List<String> labels;

  const PillTabBar({super.key, required this.labels});

  @override
  Size get preferredSize => Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    TabController controller = DefaultTabController.of(context);
    Brightness brightness = Theme.of(context).brightness;
    Color text = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: preferredSize.height,
      child: AnimatedBuilder(
        animation: controller.animation!,
        builder: (context, _) {
          int selected = controller.animation!.value.round();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
            itemCount: labels.length,
            separatorBuilder: (context, i) => SizedBox(width: 8),
            itemBuilder: (context, i) {
              bool on = i == selected;
              return Semantics(
                button: true,
                selected: on,
                child: Material(
                  color: on ? brandOrange : buttonFill(brightness),
                  shape: StadiumBorder(),
                  child: InkWell(
                    customBorder: StadiumBorder(),
                    onTap: () => controller.animateTo(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                            color: on ? Colors.white : text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
