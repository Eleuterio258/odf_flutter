import '../data/odf/odf_xml.dart' show fmtNum;
import '../domain/entities/odf_workbook.dart';

/// Valor de célula em forma simples: o resultado da fórmula, o número da moeda
/// ou da porcentagem (como fração).
Object? _plain(OdfCellValue value) => switch (value) {
      OdfFormula(:final result) => result == null ? null : _plain(result),
      _ => value.dartValue,
    };

// ===========================================================================
// CSV
// ===========================================================================

/// Grava uma aba em CSV (RFC 4180). Datas saem em ISO 8601 e números sem
/// separador de milhar; com [decimalComma], usa vírgula decimal (e o padrão
/// do separador passa a ser `;`, como no Excel em português).
String worksheetToCsv(
  OdfWorksheet sheet, {
  String? separator,
  bool decimalComma = false,
  String lineEnding = '\r\n',
}) {
  final sep = separator ?? (decimalComma ? ';' : ',');
  final columns = sheet.columnCount;
  String field(Object? v) {
    final text = switch (v) {
      null => '',
      final num n => decimalComma ? fmtNum(n).replaceAll('.', ',') : fmtNum(n),
      final bool b => b ? 'TRUE' : 'FALSE',
      final DateTime d =>
        d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0
            ? d.toIso8601String().substring(0, 10)
            : d.toIso8601String().replaceFirst(RegExp(r'\.0+$'), ''),
      final Duration d => [d.inHours, d.inMinutes % 60, d.inSeconds % 60]
          .map((n) => n.toString().padLeft(2, '0'))
          .join(':'),
      _ => v.toString(),
    };
    final quote = text.contains(sep) ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r') ||
        text != text.trim();
    return quote ? '"${text.replaceAll('"', '""')}"' : text;
  }

  final out = StringBuffer();
  for (final row in sheet.rows) {
    final cells = [
      for (var c = 0; c < columns; c++)
        c < row.cells.length ? _plain(row.cells[c].value) : null
    ];
    out
      ..write(cells.map(field).join(sep))
      ..write(lineEnding);
  }
  return out.toString();
}

/// Lê CSV (RFC 4180, aspas e quebras de linha dentro de campos).
///
/// Sem [separator], escolhe entre `,`, `;` e tabulação pela primeira linha.
/// Com [inferTypes], números, `TRUE`/`FALSE` e datas ISO viram valores
/// tipados; textos como `007` continuam texto para não perder zeros.
OdfWorksheet worksheetFromCsv(
  String csv, {
  String name = 'Planilha1',
  String? separator,
  bool decimalComma = false,
  bool inferTypes = true,
  OdfCellStyle? headerStyle,
}) {
  var text = csv;
  if (text.startsWith('﻿')) text = text.substring(1);
  final sep = separator ?? _detectSeparator(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        field.write(c);
      }
      i++;
      continue;
    }
    if (c == '"' && field.isEmpty) {
      quoted = true;
    } else if (text.startsWith(sep, i)) {
      row.add(field.toString());
      field.clear();
      i += sep.length;
      continue;
    } else if (c == '\r' || c == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = [];
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }

  return OdfWorksheet(name, rows: [
    for (var r = 0; r < rows.length; r++)
      OdfRow([
        for (final value in rows[r])
          OdfCell(
              inferTypes
                  ? _infer(value, decimalComma)
                  : OdfCellValue.from(value.isEmpty ? null : value),
              style: r == 0 ? headerStyle : null),
      ]),
  ]);
}

String _detectSeparator(String text) {
  final firstLine = text.split(RegExp(r'\r?\n')).first;
  final counts = {
    for (final s in const [',', ';', '\t']) s: s.allMatches(firstLine).length
  };
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).value == 0
      ? ','
      : counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

OdfCellValue _infer(String value, bool decimalComma) {
  if (value.isEmpty) return const OdfEmptyValue();
  final v = value.trim();
  if (v == 'TRUE' || v == 'true') return const OdfBooleanValue(true);
  if (v == 'FALSE' || v == 'false') return const OdfBooleanValue(false);
  final numeric = decimalComma ? v.replaceAll('.', '').replaceAll(',', '.') : v;
  final leadingZero = RegExp(r'^-?0\d').hasMatch(v);
  if (!leadingZero &&
      RegExp(r'^-?\d+(\.\d+)?([eE][-+]?\d+)?$').hasMatch(numeric)) {
    final n = num.parse(numeric);
    return OdfNumberValue(n is double &&
            n == n.truncateToDouble() &&
            !numeric.contains(RegExp('[.eE]'))
        ? n.toInt()
        : n);
  }
  if (RegExp(r'^-?\d+(\.\d+)?%$').hasMatch(numeric)) {
    return OdfPercentageValue(
        num.parse(numeric.substring(0, numeric.length - 1)) / 100);
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?)?$')
      .hasMatch(v)) {
    final date = DateTime.tryParse(v);
    if (date != null) return OdfDateValue(date, includeTime: v.length > 10);
  }
  return OdfStringValue(value);
}

// ===========================================================================
// JSON
// ===========================================================================

Object? _jsonSafe(Object? value) => switch (value) {
      final DateTime d => d.toIso8601String(),
      final Duration d => d.inMilliseconds / 1000,
      final double d when d.isNaN || d.isInfinite => null,
      _ => value,
    };

/// `{nomeDaAba: [[...], ...]}` com valores aceitos por `jsonEncode`
/// (datas em ISO 8601, durações em segundos).
Map<String, Object?> workbookToJson(OdfWorkbook workbook) => {
      for (final sheet in workbook.sheets)
        sheet.name: [
          for (final row in sheet.rows)
            [for (final c in row.cells) _jsonSafe(_plain(c.value))],
        ],
    };

/// Linhas como mapas, usando a linha [headerRow] como nomes das colunas.
/// Colunas sem nome recebem a letra (`D`); linhas totalmente vazias são ignoradas.
List<Map<String, Object?>> worksheetToRecords(OdfWorksheet sheet,
    {int headerRow = 0, bool jsonSafe = false}) {
  if (sheet.rows.length <= headerRow) return const [];
  final columns = sheet.columnCount;
  final header = sheet.rows[headerRow].cells;
  final keys = [
    for (var c = 0; c < columns; c++)
      c < header.length && _plain(header[c].value) != null
          ? '${_plain(header[c].value)}'
          : OdfCellRef.columnName(c),
  ];
  final records = <Map<String, Object?>>[];
  for (final row in sheet.rows.skip(headerRow + 1)) {
    final values = [
      for (var c = 0; c < columns; c++)
        c < row.cells.length ? _plain(row.cells[c].value) : null
    ];
    if (values.every((v) => v == null)) continue;
    records.add({
      for (var c = 0; c < columns; c++)
        keys[c]: jsonSafe ? _jsonSafe(values[c]) : values[c]
    });
  }
  return records;
}

/// Cria uma aba a partir de mapas: as chaves (na ordem em que aparecem) viram
/// o cabeçalho. Strings em ISO 8601 não são convertidas; passe `DateTime`.
OdfWorksheet worksheetFromRecords(
    String name, List<Map<String, Object?>> records,
    {OdfCellStyle? headerStyle}) {
  final keys = <String>{for (final r in records) ...r.keys}.toList();
  return OdfWorksheet.fromValues(
      name,
      [
        keys,
        for (final r in records) [for (final k in keys) r[k]],
      ],
      headerStyle: headerStyle);
}
