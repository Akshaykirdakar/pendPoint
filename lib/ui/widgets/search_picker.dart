import 'package:flutter/material.dart';

import '../../utils/theme.dart';
import '../../utils/lang.dart';

/// One choice in a [showSearchPicker] list.
class PickerOption<T> {
  final T value;
  final String title;
  final String? subtitle;
  final String? badge; // short tag on the left, e.g. a party code
  final String? trailing;
  const PickerOption(this.value, this.title,
      {this.subtitle, this.badge, this.trailing});
}

/// Searchable combo box as a bottom sheet — the whole list is visible the
/// moment it opens, and typing filters it (via [search], so each caller
/// decides what "matches": code, name, mobile…). Works the same on a phone
/// (keyboard + list together) and on web. [onCreate] adds a "＋ New" action
/// that can return a freshly created value.
Future<T?> showSearchPicker<T>(
  BuildContext context, {
  required String title,
  required String hint,
  required List<PickerOption<T>> Function(String query) search,
  String? createLabel,
  Future<T?> Function(BuildContext context, String query)? onCreate,
  String emptyText = 'काही सापडले नाही · No match',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => _SearchPickerSheet<T>(
      title: title,
      hint: hint,
      search: search,
      createLabel: createLabel,
      onCreate: onCreate,
      emptyText: emptyText,
    ),
  );
}

class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final String hint;
  final List<PickerOption<T>> Function(String query) search;
  final String? createLabel;
  final Future<T?> Function(BuildContext context, String query)? onCreate;
  final String emptyText;
  const _SearchPickerSheet({
    required this.title,
    required this.hint,
    required this.search,
    required this.createLabel,
    required this.onCreate,
    required this.emptyText,
  });

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Whether [query] is exactly one of the names in [title] ("मराठी ·
  /// English" titles count either half) — then nothing new is offered.
  static bool _sameName(String title, String query) {
    final q = query.trim().toLowerCase();
    return title.split(' · ').any((t) => t.trim().toLowerCase() == q);
  }

  Future<void> _create() async {
    final created = await widget.onCreate!(context, _query.text.trim());
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final results = widget.search(_query.text);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
              child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                      color: c.line, borderRadius: BorderRadius.circular(9)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
            child: Row(children: [
              Expanded(
                  child: Text(tr(widget.title),
                      style: baloo(
                          size: 17, weight: FontWeight.w700, color: c.ink))),
              // Short "＋ New" here (the full "Add New …" wording is on the
              // row under the search box) so the title keeps its room.
              if (widget.onCreate != null)
                Tooltip(
                  message: widget.createLabel ?? tr('नवीन · New'),
                  child: TextButton.icon(
                    key: const ValueKey('picker-create'),
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(L('नवीन', 'New')),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('picker-search'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: tr(widget.hint),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_query.clear)),
              ),
              onChanged: (_) => setState(() {}),
              // Enter picks the best match — fast keyboard entry.
              onSubmitted: (_) {
                if (results.isNotEmpty) {
                  Navigator.pop(context, results.first.value);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Text(tr('${results.length} सापडले · found'),
                style: TextStyle(fontSize: 11.5, color: c.muted)),
          ),
          // "＋ Add new …" right in the list when the search found nothing —
          // the shopkeeper never has to leave the entry to create it.
          if (widget.onCreate != null &&
              _query.text.trim().isNotEmpty &&
              !results.any((o) => _sameName(o.title, _query.text)))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: FilledButton.tonalIcon(
                key: const ValueKey('picker-create-row'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    alignment: Alignment.centerLeft),
                onPressed: _create,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: Text(
                    '${widget.createLabel ?? tr('नवीन · New')}: "${_query.text.trim()}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(tr(widget.emptyText),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: c.line),
                    itemBuilder: (_, i) {
                      final o = results[i];
                      return ListTile(
                        key: ValueKey('picker-option-$i'),
                        onTap: () => Navigator.pop(context, o.value),
                        leading: o.badge == null || o.badge!.isEmpty
                            ? null
                            : Container(
                                constraints: const BoxConstraints(minWidth: 40),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                    color: c.brand.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(9)),
                                child: Text(o.badge!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: c.brand)),
                              ),
                        title: Text(o.title,
                            style: baloo(
                                size: 14.5,
                                weight: FontWeight.w700,
                                color: c.ink)),
                        subtitle: o.subtitle == null
                            ? null
                            : Text(o.subtitle!,
                                style: TextStyle(fontSize: 12, color: c.ink2)),
                        trailing: o.trailing == null
                            ? null
                            : Text(o.trailing!,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: c.ink2)),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Looks like a dropdown field; tapping it opens a searchable picker. Shows
/// [value] (or [placeholder]) and a clear button when [onClear] is set.
class PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final IconData icon;
  const PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'शोधा / निवडा · Search & select',
    this.onClear,
    this.icon = Icons.search_rounded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final empty = value == null || value!.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: tr(label),
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: !empty && onClear != null
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClear)
              : const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(empty ? tr(placeholder) : value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: empty ? c.muted : c.ink,
                fontWeight: empty ? FontWeight.w400 : FontWeight.w700)),
      ),
    );
  }
}
