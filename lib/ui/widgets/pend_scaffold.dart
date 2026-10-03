import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../utils/lang.dart';
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

  /// Pinned below the body (above the keyboard) — used by the entry grids to
  /// keep the running total and Save button visible while rows scroll.
  final Widget? bottomBar;

  /// Replaces the Marathi/English title (e.g. Home: the shop's name).
  final Widget? title;

  const PendScaffold({
    required this.titleMr,
    required this.titleEn,
    required this.body,
    this.actions = const [],
    this.scroll = true,
    this.floatingActionButton,
    this.bottomBar,
    this.padding = const EdgeInsets.fromLTRB(15, 16, 15, 28),
    this.title,
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
        title: title ?? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // One language → one big title; both → Marathi + small English.
            Text(appLang == AppLang.en ? titleEn : tr(titleMr),
                style: baloo(
                    size: appLang == AppLang.both ? 19 : 21,
                    weight: FontWeight.w800,
                    color: c.brandInk)),
            if (appLang == AppLang.both)
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
      bottomNavigationBar: bottomBar == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.line))),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                    child: bottomBar,
                  ),
                ),
              ),
            ),
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
              Text(tr(label),
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
