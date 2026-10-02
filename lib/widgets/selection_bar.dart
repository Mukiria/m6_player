import 'package:flutter/material.dart';

/// The bar shown at the bottom of a list while items are selected (long-press
/// an item to start): how many are selected, and what to do with them.
class SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onFavourite;
  final VoidCallback onAddTo;
  final VoidCallback onHide;
  final VoidCallback? onDelete; // Songs only: videos are the phone's own files

  const SelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    required this.onSelectAll,
    required this.onFavourite,
    required this.onAddTo,
    required this.onHide,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 3,
      child: Row(
        children: [
          IconButton(tooltip: "Cancel", icon: Icon(Icons.close), onPressed: onClose),
          Expanded(child: Text("$count selected", style: TextStyle(fontWeight: FontWeight.w600))),
          IconButton(tooltip: "Select all", icon: Icon(Icons.select_all), onPressed: onSelectAll),
          IconButton(tooltip: "Favourite", icon: Icon(Icons.favorite_border), onPressed: onFavourite),
          IconButton(tooltip: "Add to…", icon: Icon(Icons.playlist_add), onPressed: onAddTo),
          IconButton(tooltip: "Hide", icon: Icon(Icons.visibility_off_outlined), onPressed: onHide),
          if (onDelete != null) IconButton(tooltip: "Delete", icon: Icon(Icons.delete_outline), onPressed: onDelete),
        ],
      ),
    );
  }
}
