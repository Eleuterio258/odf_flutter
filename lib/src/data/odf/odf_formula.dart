/// Converte entre fórmulas no estilo das planilhas (`=SUM(A1:B2;Dados!C3)`) e a
/// sintaxe OpenFormula que o ODF grava (`of:=SUM([.A1:.B2];[$Dados.C3])`).
///
/// Referências aceitas: `A1`, `A1:B2`, `$A$1`, colunas e linhas inteiras
/// (`A:C`, `1:3`), outra aba (`Dados!A1`, `'Minha aba'!A1`) e 3D
/// (`Plan1:Plan3!A1`). Se a fórmula separar argumentos com `;`, a vírgula
/// entre dígitos é lida como decimal (`=ROUND(1,5;0)`).
abstract final class OdfFormulaConverter {
  static const _sheet = r"('(?:[^']|'')+'|[A-Za-z_][\w.]*)";
  static const _cell = r'(\$?[A-Za-z]{1,3}\$?\d+)';
  static const _column = r'(\$?[A-Za-z]{1,3})';
  static const _row = r'(\$?\d+)';

  static final _sheetPrefix = RegExp('$_sheet(?::$_sheet)?!');
  static final _cellRange = RegExp('$_cell(?::$_cell)?');
  static final _columnRange = RegExp('$_column:$_column');
  static final _rowRange = RegExp('$_row:$_row');

  static String toOpenFormula(String formula) {
    var f = formula.trim();
    if (f.startsWith('of:')) return f;
    if (f.startsWith('=')) f = f.substring(1);
    final semicolons = _outsideStrings(f).contains(';');

    final out = StringBuffer('of:=');
    var i = 0;
    while (i < f.length) {
      final c = f[i];
      if (c == '"') {
        final end = _stringEnd(f, i);
        out.write(f.substring(i, end));
        i = end;
        continue;
      }
      if (c == ',') {
        final decimal = semicolons &&
            i > 0 &&
            i + 1 < f.length &&
            _isDigit(f[i - 1]) &&
            _isDigit(f[i + 1]);
        out.write(decimal ? '.' : ';');
        i++;
        continue;
      }
      if ((_isIdentifierStart(c) || _isDigit(c)) &&
          (i == 0 || !_isIdentifierChar(f[i - 1]))) {
        final reference = _reference(f, i);
        if (reference != null) {
          out.write(reference.$2);
          i = reference.$1;
          continue;
        }
        // Copia o identificador ou número inteiro (função, nome definido, 1.5E3...).
        var j = i + 1;
        while (j < f.length && _isIdentifierChar(f[j])) {
          j++;
        }
        out.write(f.substring(i, j));
        i = j;
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  /// Reconhece uma referência em [i]; devolve o fim e o texto OpenFormula.
  static (int, String)? _reference(String f, int i) {
    var position = i;
    String? sheet;
    String? lastSheet;
    final prefix = _sheetPrefix.matchAsPrefix(f, i);
    if (prefix != null) {
      sheet = _odfSheet(prefix.group(1)!);
      lastSheet = prefix.group(2) == null ? null : _odfSheet(prefix.group(2)!);
      position = prefix.end;
    }
    String from(String start) => sheet == null ? '.$start' : '\$$sheet.$start';
    String to(String end) => lastSheet == null ? '.$end' : '\$$lastSheet.$end';

    for (final (pattern, isRange) in [
      (_cellRange, false),
      (_columnRange, true),
      (_rowRange, true)
    ]) {
      final m = pattern.matchAsPrefix(f, position);
      if (m == null || _continuesIdentifier(f, m.end)) continue;
      final start = m.group(1)!.toUpperCase();
      final end = m.group(2)?.toUpperCase();
      // Uma linha solta ("12") é número, não referência.
      if (!isRange && !RegExp('[A-Za-z]').hasMatch(start)) continue;
      if (end == null) {
        return (
          m.end,
          lastSheet == null
              ? '[${from(start)}]'
              : '[${from(start)}:${to(start)}]'
        );
      }
      return (m.end, '[${from(start)}:${to(end)}]');
    }
    return null;
  }

  static String fromOpenFormula(String formula) {
    var f = formula.trim();
    final prefix = RegExp(r'^[a-z]+:').firstMatch(f);
    if (prefix != null) f = f.substring(prefix.end);
    if (f.startsWith('=')) f = f.substring(1);

    final out = StringBuffer('=');
    var i = 0;
    while (i < f.length) {
      final c = f[i];
      if (c == '"') {
        final end = _stringEnd(f, i);
        out.write(f.substring(i, end));
        i = end;
      } else if (c == '[') {
        final end = _bracketEnd(f, i);
        out.write(_spreadsheetReference(f.substring(i + 1, end - 1)));
        i = end;
      } else if (c == ';') {
        out.write(',');
        i++;
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  static String _odfSheet(String sheet) =>
      RegExp(r'^[A-Za-z_]\w*$').hasMatch(sheet) || sheet.startsWith("'")
          ? sheet
          : "'$sheet'";

  static String _spreadsheetReference(String odf) {
    final parts = [for (final part in _splitRange(odf)) _splitSheet(part)];
    final first = parts.first;
    if (parts.length == 2) {
      final last = parts.last;
      // 3D: a mesma célula em várias abas.
      if (first.$1 != null && last.$1 != null && first.$1 != last.$1) {
        final cells = first.$2 == last.$2 ? first.$2 : '${first.$2}:${last.$2}';
        return '${first.$1}:${last.$1}!$cells';
      }
    }
    final sheet = first.$1 == null ? '' : '${first.$1}!';
    return '$sheet${parts.map((p) => p.$2).join(':')}';
  }

  static List<String> _splitRange(String odf) {
    final parts = <String>[];
    var quoted = false;
    var start = 0;
    for (var i = 0; i < odf.length; i++) {
      if (odf[i] == "'") quoted = !quoted;
      if (odf[i] == ':' && !quoted) {
        parts.add(odf.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(odf.substring(start));
    return parts;
  }

  static (String?, String) _splitSheet(String part) {
    final p = part.trim();
    if (p.startsWith('.')) return (null, p.substring(1));
    var quoted = false;
    var dot = -1;
    for (var i = 0; i < p.length; i++) {
      if (p[i] == "'") quoted = !quoted;
      if (p[i] == '.' && !quoted) dot = i;
    }
    if (dot < 0) return (null, p);
    var sheet = p.substring(0, dot);
    if (sheet.startsWith(r'$')) sheet = sheet.substring(1);
    return (sheet, p.substring(dot + 1));
  }

  static String _outsideStrings(String f) =>
      f.replaceAll(RegExp(r'"(?:[^"]|"")*"'), '');

  static int _stringEnd(String f, int start) {
    var i = start + 1;
    while (i < f.length) {
      if (f[i] == '"') {
        if (i + 1 < f.length && f[i + 1] == '"') {
          i += 2;
          continue;
        }
        return i + 1;
      }
      i++;
    }
    return f.length;
  }

  static int _bracketEnd(String f, int start) {
    var quoted = false;
    for (var i = start + 1; i < f.length; i++) {
      if (f[i] == "'") quoted = !quoted;
      if (f[i] == ']' && !quoted) return i + 1;
    }
    return f.length;
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static bool _isIdentifierStart(String c) =>
      RegExp(r"[A-Za-z_$']").hasMatch(c);

  static bool _isIdentifierChar(String c) => RegExp(r'[\w.$]').hasMatch(c);

  /// Evita tratar `LOG10(` ou `A1B` como referência.
  static bool _continuesIdentifier(String f, int end) =>
      end < f.length && RegExp(r'[\w(.]').hasMatch(f[end]);
}
