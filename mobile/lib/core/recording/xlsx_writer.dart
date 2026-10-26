import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A sheet: a name and rows of cells (String, num, bool or null).
class XlsxSheet {
  const XlsxSheet(this.name, this.rows, {this.rightToLeft = false});
  final String name;
  final List<List<Object?>> rows;

  /// Show the sheet right-to-left (Arabic).
  final bool rightToLeft;
}

/// Minimal, dependency-free Office Open XML (.xlsx) writer: inline strings, numbers,
/// booleans, a bold header row, frozen first row. Enough for exports that open in
/// Excel / LibreOffice / Google Sheets with Arabic text intact (UTF-8 XML).
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final a = Archive();
  void add(String path, String xml) => a.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));

  add('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');
  add('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
  add('xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(_sheetName(sheets[i].name, i))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
</workbook>''');
  add('xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join('\n')}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
  add('xl/styles.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''');

  for (var i = 0; i < sheets.length; i++) {
    final s = sheets[i];
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0"${s.rightToLeft ? ' rightToLeft="1"' : ''}>')
      ..write('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
      ..write('<sheetData>');
    for (var r = 0; r < s.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < s.rows[r].length; c++) {
        final v = s.rows[r][c];
        if (v == null) continue;
        final ref = '${_col(c)}${r + 1}';
        final style = r == 0 ? ' s="1"' : '';
        if (v is num && v.isFinite) {
          b.write('<c r="$ref"$style><v>$v</v></c>');
        } else if (v is bool) {
          b.write('<c r="$ref" t="b"$style><v>${v ? 1 : 0}</v></c>');
        } else {
          b.write('<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    add('xl/worksheets/sheet${i + 1}.xml', b.toString());
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(a));
}

/// Column letters: 0 → A, 25 → Z, 26 → AA.
String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// Excel sheet names: max 31 chars, no []:*?/\ characters.
String _sheetName(String name, int i) {
  final n = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final s = n.isEmpty ? 'Sheet${i + 1}' : n;
  return s.length > 31 ? s.substring(0, 31) : s;
}

final RegExp _invalidXml = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]');

String _esc(String s) => s
    .replaceAll(_invalidXml, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
