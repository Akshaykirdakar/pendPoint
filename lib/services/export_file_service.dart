// Platform-independent "save" and "share" primitives for report exports.
//
// This is the one place that talks to a platform file API. ReportExportService
// only ever generates PDF/XLSX bytes — identical on every platform — and
// hands them here. Neither this file nor ReportExportService branches on
// platform (no `if (Platform.isAndroid)`, no `dart:html`); both `file_picker`
// and `share_plus` are federated plugins that already pick the right
// implementation for Web/Android/Windows/iOS internally.
//
// Why not just `share_plus` for "Download" too: on Web, share_plus falls back
// to a real browser download when there's no native share target, so it
// looks like "Download" works there — but on Android it always opens the
// share sheet, never a direct save, which is why a "Download PDF" button
// wired to `share_plus` alone behaves inconsistently across platforms. Using
// `file_picker`'s `saveFile()` (Android Storage Access Framework / Windows
// native save dialog / Web download) for the explicit "Download" action gives
// the same, correct "the user chose to keep this file" behavior everywhere,
// with no storage permission needed on Android (SAF grants access per-file).
//
// Why `share_plus` alone loses the filename on Android: `XFile.fromData(...,
// name: 'foo.pdf')` — cross_file's `io.dart` (used on Android/Windows/iOS/
// Linux/macOS, not Web) explicitly ignores `name` when there's no `path`
// (see cross_file's `XFile.fromData` doc comment). Without a real name,
// share_plus invents a random UUID filename before opening the share sheet.
// `ShareParams.fileNameOverrides` is the documented fix — it's read by both
// share_plus's Android/desktop method channel and its Web implementation.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

enum ExportOutcome { saved, cancelled, failed }

/// The result of a save or share attempt — never collapsed to a plain bool,
/// so callers can tell "the user backed out of the save dialog" (no error,
/// no message needed) apart from "it actually failed" (show an error) apart
/// from "it worked" (only then show a success message).
class ExportResult {
  final ExportOutcome outcome;
  final String? location;
  final Object? error;
  const ExportResult(this.outcome, {this.location, this.error});

  bool get isSuccess => outcome == ExportOutcome.saved;
}

class ExportFileService {
  const ExportFileService._();

  /// Explicit "Download" — the user picks (or implicitly confirms, on Web)
  /// where the file goes. Never reports success unless the platform actually
  /// confirms a save; a cancelled system dialog is reported as cancelled, not
  /// as an error and not as success.
  static Future<ExportResult> saveFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) {
      return const ExportResult(ExportOutcome.failed,
          error: 'Generated file is empty');
    }
    try {
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        dialogTitle: 'अहवाल जतन करा · Save report',
      );
      // On Web, file_picker's saveFile always returns null (a browser
      // download has no confirmable destination to report back) even when
      // the download was triggered successfully — only Android/Windows use
      // null to mean "the user cancelled the dialog". See file_picker_web's
      // saveFile source: it never returns anything but null.
      if (uri == null && !kIsWeb) {
        return const ExportResult(ExportOutcome.cancelled);
      }
      return ExportResult(ExportOutcome.saved,
          location: uri == null ? null : _describeLocation(uri));
    } catch (e) {
      return ExportResult(ExportOutcome.failed, error: e);
    }
  }

  static String? _describeLocation(Uri uri) {
    // Android SAF hands back a content:// URI, not a filesystem path — it
    // isn't human-readable, so don't pretend it is.
    if (uri.scheme == 'content') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return uri.toString();
    }
  }

  /// "Share" — hands the bytes to another app via the OS share sheet, under
  /// the exact filename given (see file header for why `fileNameOverrides`
  /// is required, not optional, here).
  static Future<ExportResult> shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
  }) async {
    if (bytes.isEmpty) {
      return const ExportResult(ExportOutcome.failed,
          error: 'Generated file is empty');
    }
    try {
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        fileNameOverrides: [fileName],
        subject: subject,
      ));
      if (result.status == ShareResultStatus.dismissed) {
        return const ExportResult(ExportOutcome.cancelled);
      }
      return const ExportResult(ExportOutcome.saved);
    } catch (e) {
      return ExportResult(ExportOutcome.failed, error: e);
    }
  }
}
