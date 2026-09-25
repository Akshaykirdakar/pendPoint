// ExportFileService is the one place that talks to a platform file API
// (file_picker for "Download", share_plus for "Share") — most of its
// behavior needs a real platform channel, which a plain `flutter test` run
// doesn't have. This covers what's testable without one: it must never
// report success for an empty file (an empty PDF/XLSX would mean generation
// silently failed upstream), for either the save or the share path.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pend_point/services/export_file_service.dart';

void main() {
  final emptyBytes = Uint8List(0);

  group('ExportFileService rejects empty files before touching the platform', () {
    test('saveFile reports failed, not saved, for empty bytes', () async {
      final result = await ExportFileService.saveFile(
        bytes: emptyBytes,
        fileName: 'pendpoint_sales_report_2026-09-13.pdf',
        mimeType: 'application/pdf',
      );
      expect(result.outcome, ExportOutcome.failed);
      expect(result.isSuccess, isFalse);
    });

    test('shareFile reports failed, not saved, for empty bytes', () async {
      final result = await ExportFileService.shareFile(
        bytes: emptyBytes,
        fileName: 'pendpoint_sales_report_2026-09-13.pdf',
        mimeType: 'application/pdf',
      );
      expect(result.outcome, ExportOutcome.failed);
      expect(result.isSuccess, isFalse);
    });
  });
}
