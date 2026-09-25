// A minimal, dependency-light .xlsx (OOXML spreadsheet) writer.
//
// The project already resolves `archive` transitively (via `image`, pinned
// at ^4.9.2), but the `image` package requires archive ^4.x while every
// release of the `excel` package on pub.dev is hard-pinned to archive ^3.x —
// they cannot both be in the dependency graph at once. Rather than touch the
// pinned `image` version to make room for `excel`, this hand-builds the
// (quite simple) OOXML zip directly on top of `archive`, which is already
// present. See reviewed spec §14 ("inspect pubspec.yaml before adding a
// dependency; don't introduce unnecessary packages").
//
// Cells are written as inline strings / plain numbers — no shared-strings
// table, no styles — which is all a well-formed .xlsx needs to open cleanly
// in Excel, Google Sheets, and LibreOffice.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One worksheet: a name and its rows, each a list of `String`/`num`/`null`.
class XlsxSheet {
  final String name;
  final List<List<Object?>> rows;
  const XlsxSheet(this.name, this.rows);
}

/// Builds a valid .xlsx workbook from [sheets], returned as raw bytes ready
/// to share/save.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final archive = Archive();
  void addText(String path, String content) => archive.addFile(
      ArchiveFile(path, content.length, utf8.encode(content)));

  addText('[Content_Types].xml', _contentTypesXml(sheets.length));
  addText('_rels/.rels', _rootRelsXml);
  addText('xl/workbook.xml', _workbookXml(sheets));
  addText('xl/_rels/workbook.xml.rels', _workbookRelsXml(sheets.length));
  for (var i = 0; i < sheets.length; i++) {
    addText('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
  }
  return ZipEncoder().encodeBytes(archive);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Spreadsheet column letters: 0 -> A, 1 -> B, ..., 26 -> AA, ...
String _colLetters(int index) {
  var n = index + 1;
  var s = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

const _rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _contentTypesXml(int sheetCount) {
  final overrides = StringBuffer();
  for (var i = 1; i <= sheetCount; i++) {
    overrides.write(
        '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '$overrides'
      '</Types>';
}

String _workbookXml(List<XlsxSheet> sheets) {
  final sheetTags = StringBuffer();
  for (var i = 0; i < sheets.length; i++) {
    sheetTags.write(
        '<sheet name="${_xmlEscape(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>$sheetTags</sheets>'
      '</workbook>';
}

String _workbookRelsXml(int sheetCount) {
  final rels = StringBuffer();
  for (var i = 1; i <= sheetCount; i++) {
    rels.write(
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$rels'
      '</Relationships>';
}

String _sheetXml(XlsxSheet sheet) {
  final rowsXml = StringBuffer();
  for (var r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final cellsXml = StringBuffer();
    for (var col = 0; col < row.length; col++) {
      final ref = '${_colLetters(col)}${r + 1}';
      final value = row[col];
      if (value == null) continue;
      if (value is num) {
        cellsXml.write('<c r="$ref"><v>${value.toString()}</v></c>');
      } else {
        cellsXml.write(
            '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xmlEscape(value.toString())}</t></is></c>');
      }
    }
    rowsXml.write('<row r="${r + 1}">$cellsXml</row>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>$rowsXml</sheetData>'
      '</worksheet>';
}
