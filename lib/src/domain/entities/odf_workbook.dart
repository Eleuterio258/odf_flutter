import 'odf_color.dart';
import 'odf_metadata.dart';
import 'odf_rich_text.dart';

// ---------------------------------------------------------------------------
// Valores de célula
// ---------------------------------------------------------------------------

sealed class OdfCellValue {
  const OdfCellValue();

  /// Converte valores Dart comuns: `String`, `num`, `bool`, `DateTime`,
  /// `Duration` e `null`. Fórmulas devem ser criadas com [OdfFormula].
  factory OdfCellValue.from(Object? value) => switch (value) {
        null => const OdfEmptyValue(),
        final OdfCellValue v => v,
        final String v => OdfStringValue(v),
        final num v => OdfNumberValue(v),
        final bool v => OdfBooleanValue(v),
        final DateTime v => OdfDateValue(v,
            includeTime: v.hour != 0 || v.minute != 0 || v.second != 0),
        final Duration v => OdfTimeValue(v),
        _ => OdfStringValue(value.toString()),
      };

  /// Valor Dart equivalente (`String`, `num`, `bool`, `DateTime`, `Duration` ou `null`).
  Object? get dartValue;
}

final class OdfEmptyValue extends OdfCellValue {
  const OdfEmptyValue();

  @override
  Object? get dartValue => null;

  @override
  bool operator ==(Object other) => other is OdfEmptyValue;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'OdfEmptyValue()';
}

final class OdfStringValue extends OdfCellValue {
  const OdfStringValue(this.value);
  final String value;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfStringValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OdfStringValue("$value")';
}

final class OdfNumberValue extends OdfCellValue {
  const OdfNumberValue(this.value);
  final num value;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfNumberValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OdfNumberValue($value)';
}

final class OdfCurrencyValue extends OdfCellValue {
  const OdfCurrencyValue(this.value, {this.currency = 'BRL'});
  final num value;

  /// Código ISO 4217 (BRL, USD, EUR...).
  final String currency;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfCurrencyValue &&
      other.value == value &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(value, currency);

  @override
  String toString() => 'OdfCurrencyValue($value $currency)';
}

/// Porcentagem como fração: `0.25` é exibido como 25%.
final class OdfPercentageValue extends OdfCellValue {
  const OdfPercentageValue(this.value);
  final num value;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfPercentageValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OdfPercentageValue($value)';
}

/// Data (e hora, com [includeTime]) como aparece na planilha.
///
/// O ODF não guarda fuso horário: são gravados os campos de [value] (ano, mês,
/// dia, hora...) sem conversão, inclusive para `DateTime` em UTC, e a leitura
/// devolve sempre um `DateTime` local com esses mesmos campos. Para gravar a
/// hora local de um instante UTC, use `value.toLocal()` antes.
final class OdfDateValue extends OdfCellValue {
  const OdfDateValue(this.value, {this.includeTime = false});
  final DateTime value;
  final bool includeTime;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfDateValue &&
      other.value == value &&
      other.includeTime == includeTime;

  @override
  int get hashCode => Object.hash(value, includeTime);

  @override
  String toString() => 'OdfDateValue($value)';
}

final class OdfTimeValue extends OdfCellValue {
  const OdfTimeValue(this.value);
  final Duration value;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfTimeValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OdfTimeValue($value)';
}

final class OdfBooleanValue extends OdfCellValue {
  const OdfBooleanValue(this.value);
  final bool value;

  @override
  Object? get dartValue => value;

  @override
  bool operator ==(Object other) =>
      other is OdfBooleanValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OdfBooleanValue($value)';
}

/// Fórmula no estilo das planilhas: `=SUM(A1:A3)`, `=Dados!B2*2`,
/// `=IF(A1>10,"alto","baixo")`. Argumentos podem ser separados por `,` ou `;`.
///
/// [result] é o valor já calculado (opcional). Sem ele, o LibreOffice
/// recalcula ao abrir o arquivo.
final class OdfFormula extends OdfCellValue {
  const OdfFormula(this.expression, {this.result});
  final String expression;
  final OdfCellValue? result;

  @override
  Object? get dartValue => result?.dartValue;

  @override
  bool operator ==(Object other) =>
      other is OdfFormula &&
      other.expression == expression &&
      other.result == result;

  @override
  int get hashCode => Object.hash(expression, result);

  @override
  String toString() =>
      'OdfFormula($expression${result == null ? '' : ' = ${result!.dartValue}'})';
}

// ---------------------------------------------------------------------------
// Formatação
// ---------------------------------------------------------------------------

enum OdfNumberFormatKind { number, percentage, currency, date, time }

/// Formato de exibição numérico (gera um *data style* ODF).
final class OdfNumberFormat {
  const OdfNumberFormat.number({this.decimals = 2, this.grouping = true})
      : kind = OdfNumberFormatKind.number,
        currency = null,
        pattern = null;

  const OdfNumberFormat.percentage({this.decimals = 0})
      : kind = OdfNumberFormatKind.percentage,
        grouping = false,
        currency = null,
        pattern = null;

  const OdfNumberFormat.currency(String this.currency, {this.decimals = 2})
      : kind = OdfNumberFormatKind.currency,
        grouping = true,
        pattern = null;

  /// Padrão com `d`, `dd`, `M`, `MM`, `MMM`, `MMMM`, `yy`, `yyyy`, `H`, `HH`, `mm`, `ss`.
  const OdfNumberFormat.date([String this.pattern = 'dd/MM/yyyy'])
      : kind = OdfNumberFormatKind.date,
        decimals = 0,
        grouping = false,
        currency = null;

  const OdfNumberFormat.time([String this.pattern = 'HH:mm:ss'])
      : kind = OdfNumberFormatKind.time,
        decimals = 0,
        grouping = false,
        currency = null;

  final OdfNumberFormatKind kind;
  final int decimals;
  final bool grouping;
  final String? currency;
  final String? pattern;

  @override
  bool operator ==(Object other) =>
      other is OdfNumberFormat &&
      other.kind == kind &&
      other.decimals == decimals &&
      other.grouping == grouping &&
      other.currency == currency &&
      other.pattern == pattern;

  @override
  int get hashCode => Object.hash(kind, decimals, grouping, currency, pattern);

  @override
  String toString() =>
      'OdfNumberFormat.${kind.name}(${pattern ?? currency ?? decimals})';
}

enum OdfVerticalAlign { top, middle, bottom }

final class OdfCellStyle {
  const OdfCellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontSize,
    this.color,
    this.backgroundColor,
    this.align,
    this.verticalAlign,
    this.wrap = false,
    this.border = false,
    this.numberFormat,
  });

  static const header = OdfCellStyle(
      bold: true, backgroundColor: OdfColor.lightGray, border: true);

  final bool bold;
  final bool italic;
  final bool underline;
  final double? fontSize;
  final OdfColor? color;
  final OdfColor? backgroundColor;
  final OdfTextAlign? align;
  final OdfVerticalAlign? verticalAlign;
  final bool wrap;

  /// Borda fina em todos os lados.
  final bool border;
  final OdfNumberFormat? numberFormat;

  bool get isDefault => this == const OdfCellStyle();

  OdfCellStyle withNumberFormat(OdfNumberFormat? format) => OdfCellStyle(
        bold: bold,
        italic: italic,
        underline: underline,
        fontSize: fontSize,
        color: color,
        backgroundColor: backgroundColor,
        align: align,
        verticalAlign: verticalAlign,
        wrap: wrap,
        border: border,
        numberFormat: format,
      );

  @override
  bool operator ==(Object other) =>
      other is OdfCellStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.backgroundColor == backgroundColor &&
      other.align == align &&
      other.verticalAlign == verticalAlign &&
      other.wrap == wrap &&
      other.border == border &&
      other.numberFormat == numberFormat;

  @override
  int get hashCode => Object.hash(bold, italic, underline, fontSize, color,
      backgroundColor, align, verticalAlign, wrap, border, numberFormat);
}

// ---------------------------------------------------------------------------
// Estrutura
// ---------------------------------------------------------------------------

final class OdfCell {
  OdfCell(this.value,
      {this.style, this.colSpan = 1, this.rowSpan = 1, this.note})
      : assert(colSpan >= 1 && rowSpan >= 1);

  factory OdfCell.from(Object? value, {OdfCellStyle? style}) =>
      OdfCell(OdfCellValue.from(value), style: style);

  OdfCellValue value;
  OdfCellStyle? style;
  int colSpan;
  int rowSpan;

  /// Comentário exibido na célula.
  String? note;

  bool get isEmpty =>
      value is OdfEmptyValue && note == null && colSpan == 1 && rowSpan == 1;

  @override
  String toString() => 'OdfCell($value)';
}

final class OdfRow {
  OdfRow([List<OdfCell>? cells, this.height])
      : cells = List.of(cells ?? const []);

  factory OdfRow.values(List<Object?> values, {OdfCellStyle? style}) =>
      OdfRow([for (final v in values) OdfCell.from(v, style: style)]);

  final List<OdfCell> cells;

  /// Altura em centímetros.
  double? height;
}

/// Posição de célula convertida a partir da notação `A1`.
final class OdfCellRef {
  const OdfCellRef(this.row, this.column);

  factory OdfCellRef.parse(String ref) {
    final match =
        RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$').firstMatch(ref.trim());
    if (match == null) {
      throw ArgumentError.value(ref, 'ref', 'Referência de célula inválida');
    }
    var column = 0;
    for (final c in match.group(1)!.toUpperCase().codeUnits) {
      column = column * 26 + (c - 64);
    }
    return OdfCellRef(int.parse(match.group(2)!) - 1, column - 1);
  }

  /// Índices a partir de zero.
  final int row;
  final int column;

  static String columnName(int column) {
    var n = column + 1;
    var name = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      name = String.fromCharCode(65 + r) + name;
      n = (n - 1) ~/ 26;
    }
    return name;
  }

  @override
  String toString() => '${columnName(column)}${row + 1}';

  @override
  bool operator ==(Object other) =>
      other is OdfCellRef && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

final class OdfWorksheet {
  OdfWorksheet(this.name, {List<OdfRow>? rows, Map<int, double>? columnWidths})
      : rows = List.of(rows ?? const []),
        columnWidths = Map.of(columnWidths ?? const {});

  /// Cria uma aba a partir de valores Dart; a primeira linha recebe [headerStyle].
  factory OdfWorksheet.fromValues(String name, List<List<Object?>> values,
          {OdfCellStyle? headerStyle}) =>
      OdfWorksheet(name, rows: [
        for (var i = 0; i < values.length; i++)
          OdfRow.values(values[i], style: i == 0 ? headerStyle : null),
      ]);

  String name;
  final List<OdfRow> rows;

  /// Larguras de coluna em centímetros, por índice (0 = coluna A).
  final Map<int, double> columnWidths;

  /// Colunas ocupadas, incluindo as cobertas por mesclagens.
  int get columnCount => rows.fold(0, (max, row) {
        var width = row.cells.length;
        for (var c = 0; c < row.cells.length; c++) {
          final end = c + row.cells[c].colSpan;
          if (end > width) width = end;
        }
        return width > max ? width : max;
      });

  /// Célula na posição real (índices a partir de zero): `cells[i]` é sempre a
  /// coluna i. Posições cobertas por uma mesclagem existem na lista, mas são
  /// gravadas como ocultas; o conteúdo visível fica na célula de origem.
  OdfCell? cell(int row, int column) {
    if (row < 0 || row >= rows.length) return null;
    final cells = rows[row].cells;
    return column >= 0 && column < cells.length ? cells[column] : null;
  }

  /// Célula de origem da mesclagem que cobre [ref], ou a própria célula.
  OdfCell? visibleAt(String ref) {
    final target = OdfCellRef.parse(ref);
    final firstRow = target.row - 1024 < 0 ? 0 : target.row - 1024;
    for (var r = target.row < rows.length ? target.row : rows.length - 1;
        r >= firstRow;
        r--) {
      final cells = rows[r].cells;
      for (var c =
              target.column < cells.length ? target.column : cells.length - 1;
          c >= 0;
          c--) {
        if (r == target.row && c == target.column) continue;
        final cell = cells[c];
        if (r + cell.rowSpan > target.row && c + cell.colSpan > target.column) {
          return cell;
        }
      }
    }
    return cell(target.row, target.column);
  }

  OdfCell? at(String ref) {
    final r = OdfCellRef.parse(ref);
    return cell(r.row, r.column);
  }

  /// Define o valor de uma célula, criando linhas e células vazias se preciso.
  OdfCell set(String ref, Object? value, {OdfCellStyle? style}) {
    final r = OdfCellRef.parse(ref);
    while (rows.length <= r.row) {
      rows.add(OdfRow());
    }
    final cells = rows[r.row].cells;
    while (cells.length <= r.column) {
      cells.add(OdfCell(const OdfEmptyValue()));
    }
    final cell = cells[r.column]
      ..value = OdfCellValue.from(value)
      ..style = style ?? cells[r.column].style;
    return cell;
  }

  /// Valores Dart linha a linha.
  List<List<Object?>> get values => [
        for (final row in rows) [for (final c in row.cells) c.value.dartValue],
      ];
}

/// Pasta de trabalho com várias abas (ODS).
final class OdfWorkbook {
  OdfWorkbook({List<OdfWorksheet>? sheets, this.metadata = const OdfMetadata()})
      : sheets = List.of(sheets ?? const []);

  final List<OdfWorksheet> sheets;
  OdfMetadata metadata;

  OdfWorksheet addSheet(String name) {
    final sheet = OdfWorksheet(name);
    sheets.add(sheet);
    return sheet;
  }

  OdfWorksheet? sheet(String name) {
    for (final s in sheets) {
      if (s.name == name) return s;
    }
    return null;
  }
}
