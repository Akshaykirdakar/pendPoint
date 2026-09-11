import 'package:flutter/material.dart';

import '../../utils/theme.dart';

/// Shared page chrome: an emerald app bar with a Marathi title + English
/// subtitle, and a padded (optionally scrolling) body. Pushed screens get an
/// automatic back button.
class PendScaffold extends StatelessWidget {
  final String titleMr;
  final String titleEn;
  final List<Widget> actions;
  final Widget body;
  final bool scroll;
  final Widget? floatingActionButton;
  final EdgeInsets padding;

  const PendScaffold({
    required this.titleMr,
    required this.titleEn,
    required this.body,
    this.actions = const [],
    this.scroll = true,
    this.floatingActionButton,
    this.padding = const EdgeInsets.fromLTRB(15, 16, 15, 28),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        elevation: 0,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titleMr,
                style: baloo(
                    size: 19, weight: FontWeight.w800, color: c.brandInk)),
            Text(titleEn,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: c.brandInk.withValues(alpha: 0.82))),
          ],
        ),
        actions: [...actions, const SizedBox(width: 6)],
      ),
      floatingActionButton: floatingActionButton,
      body: scroll
          ? SingleChildScrollView(padding: padding, child: body)
          : Padding(padding: padding, child: body),
    );
  }
}

/// A pill-style app-bar action button.
class BarAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const BarAction(this.label, {this.icon, required this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: c.brandInk.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: c.brandInk),
                const SizedBox(width: 5)
              ],
              Text(label,
                  style: TextStyle(
                      color: c.brandInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}
