import '../../domain/entities/odf_image.dart';
import '../../domain/entities/odf_rich_text.dart';
import '../../domain/entities/odf_workbook.dart';
import 'odf_xml.dart';

/// Estilos automáticos deduplicados: o mesmo conteúdo sempre recebe o mesmo nome.
class OdfStyleRegistry {
  OdfStyleRegistry({this.prefix = ''});

  final String prefix;
  final _entries = <Object, _StyleEntry>{};
  final _counters = <String, int>{};

  String register(String family, Object key,
      void Function(OdfXmlWriter w, String name) write) {
    final k = (family, key);
    final existing = _entries[k];
    if (existing != null) return existing.name;
    final n = (_counters[family] ?? 0) + 1;
    _counters[family] = n;
    final name = '$prefix$family$n';
    _entries[k] = _StyleEntry(name, write);
    return name;
  }

  String fragment() {
    final w = OdfXmlWriter();
    for (final entry in _entries.values) {
      entry.write(w, entry.name);
    }
    return w.fragment();
  }

  // ------------------------------------------------------------------ texto

  String textStyle(OdfTextStyle style) => register('T', style, (w, name) {
        w.el('style:style', {'style:name': name, 'style:family': 'text'},
            () => writeTextProperties(w, style));
      });

  String paragraphStyle(OdfParagraphStyle style,
          {String? parent, bool breakBefore = false}) =>
      register('P', (style, parent, breakBefore), (w, name) {
        w.el('style:style', {
          'style:name': name,
          'style:family': 'paragraph',
          'style:parent-style-name': parent
        }, () {
          writeParagraphProperties(w, style, breakBefore: breakBefore);
        });
      });

  String listStyle({required bool ordered}) =>
      register('L', ordered, (w, name) {
        const bullets = ['•', '◦', '▪'];
        const formats = ['1', 'a', 'i'];
        w.el('text:list-style', {'style:name': name}, () {
          for (var level = 1; level <= 10; level++) {
            final indent = 0.635 * level;
            void props() => w.el('style:list-level-properties', {
                  'text:list-level-position-and-space-mode': 'label-alignment'
                }, () {
                  w.el('style:list-level-label-alignment', {
                    'text:label-followed-by': 'listtab',
                    'text:list-tab-stop-position': cm(indent + 0.635),
                    'fo:text-indent': cm(-0.635),
                    'fo:margin-left': cm(indent + 0.635),
                  });
                });
            if (ordered) {
              w.el(
                  'text:list-level-style-number',
                  {
                    'text:level': '$level',
                    'style:num-suffix': '.',
                    'style:num-format': formats[(level - 1) % formats.length],
                  },
                  props);
            } else {
              w.el(
                  'text:list-level-style-bullet',
                  {
                    'text:level': '$level',
                    'text:bullet-char': bullets[(level - 1) % bullets.length],
                  },
                  props);
            }
          }
        });
      });

  // --------------------------------------------------------------- números

  String dataStyle(OdfNumberFormat format) =>
      register('N', format, (w, name) => writeDataStyle(w, name, format));
}

class _StyleEntry {
  _StyleEntry(this.name, this.write);
  final String name;
  final void Function(OdfXmlWriter w, String name) write;
}

void writeTextProperties(OdfXmlWriter w, OdfTextStyle s) {
  final size = s.fontSize == null ? null : pt(s.fontSize!);
  final family = s.fontFamily == null
      ? null
      : (s.fontFamily!.contains(' ') ? "'${s.fontFamily}'" : s.fontFamily);
  w.el('style:text-properties', {
    if (s.bold) ...{
      'fo:font-weight': 'bold',
      'style:font-weight-asian': 'bold',
      'style:font-weight-complex': 'bold'
    },
    if (s.italic) ...{
      'fo:font-style': 'italic',
      'style:font-style-asian': 'italic',
      'style:font-style-complex': 'italic'
    },
    if (s.underline) ...{
      'style:text-underline-style': 'solid',
      'style:text-underline-width': 'auto',
      'style:text-underline-color': 'font-color',
    },
    if (s.strikethrough) ...{
      'style:text-line-through-style': 'solid',
      'style:text-line-through-type': 'single'
    },
    if (s.superscript) 'style:text-position': 'super 58%',
    if (s.subscript) 'style:text-position': 'sub 58%',
    'fo:font-size': size,
    'style:font-size-asian': size,
    'style:font-size-complex': size,
    'fo:font-family': family,
    'fo:color': s.color?.toHex(),
    'fo:background-color': s.backgroundColor?.toHex(),
  });
}

String alignValue(OdfTextAlign align) => switch (align) {
      OdfTextAlign.start => 'start',
      OdfTextAlign.center => 'center',
      OdfTextAlign.end => 'end',
      OdfTextAlign.justify => 'justify',
    };

void writeParagraphProperties(OdfXmlWriter w, OdfParagraphStyle s,
    {bool breakBefore = false}) {
  w.el('style:paragraph-properties', {
    'fo:text-align': s.align == null ? null : alignValue(s.align!),
    'fo:margin-top': s.spaceBefore == null ? null : cm(s.spaceBefore!),
    'fo:margin-bottom': s.spaceAfter == null ? null : cm(s.spaceAfter!),
    'fo:margin-left': s.indentLeft == null ? null : cm(s.indentLeft!),
    'fo:text-indent': s.firstLineIndent == null ? null : cm(s.firstLineIndent!),
    'fo:line-height':
        s.lineSpacing == null ? null : '${fmtNum(s.lineSpacing! * 100)}%',
    'fo:background-color': s.backgroundColor?.toHex(),
    'fo:break-before': breakBefore ? 'page' : null,
  });
}

// ---------------------------------------------------------------------------
// Formatos numéricos
// ---------------------------------------------------------------------------

const currencySymbols = {
  'BRL': 'R\$',
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
  'JPY': '¥',
  'AOA': 'Kz',
  'MZN': 'MT'
};

const _currencyLocales = {
  'BRL': ('pt', 'BR'),
  'USD': ('en', 'US'),
  'EUR': ('de', 'DE'),
  'GBP': ('en', 'GB'),
  'JPY': ('ja', 'JP'),
  'AOA': ('pt', 'AO'),
  'MZN': ('pt', 'MZ'),
};

/// Formato padrão para o tipo do valor, quando a célula não define um.
OdfNumberFormat? defaultFormatFor(OdfCellValue value) => switch (value) {
      OdfCurrencyValue(:final currency) => OdfNumberFormat.currency(currency),
      OdfPercentageValue() => const OdfNumberFormat.percentage(),
      OdfDateValue(includeTime: true) =>
        const OdfNumberFormat.date('dd/MM/yyyy HH:mm'),
      OdfDateValue() => const OdfNumberFormat.date(),
      OdfTimeValue() => const OdfNumberFormat.time(),
      OdfFormula(:final result?) => defaultFormatFor(result),
      _ => null,
    };

/// Divide um padrão de data/hora em blocos de letras iguais e literais.
List<String> tokenizeDatePattern(String pattern) {
  final tokens = <String>[];
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    var j = i + 1;
    if (RegExp('[dMyHhms]').hasMatch(c)) {
      while (j < pattern.length && pattern[j] == c) {
        j++;
      }
    } else {
      while (j < pattern.length && !RegExp('[dMyHhms]').hasMatch(pattern[j])) {
        j++;
      }
    }
    tokens.add(pattern.substring(i, j));
    i = j;
  }
  return tokens;
}

void writeDataStyle(OdfXmlWriter w, String name, OdfNumberFormat f) {
  void number({bool grouping = false}) => w.el('number:number', {
        'number:decimal-places': '${f.decimals}',
        'number:min-integer-digits': '1',
        'number:grouping': grouping ? 'true' : null,
      });

  switch (f.kind) {
    case OdfNumberFormatKind.number:
      w.el('number:number-style', {'style:name': name},
          () => number(grouping: f.grouping));
    case OdfNumberFormatKind.percentage:
      w.el('number:percentage-style', {'style:name': name}, () {
        number();
        w.el('number:text', {}, () => w.text('%'));
      });
    case OdfNumberFormatKind.currency:
      final code = f.currency!;
      final locale = _currencyLocales[code];
      w.el('number:currency-style', {'style:name': name}, () {
        w.el(
            'number:currency-symbol',
            {'number:language': locale?.$1, 'number:country': locale?.$2},
            () => w.text(currencySymbols[code] ?? code));
        w.el('number:text', {}, () => w.text(' '));
        number(grouping: true);
      });
    case OdfNumberFormatKind.date:
    case OdfNumberFormatKind.time:
      final isTime = f.kind == OdfNumberFormatKind.time;
      w.el(isTime ? 'number:time-style' : 'number:date-style', {
        'style:name': name,
        if (isTime) 'number:truncate-on-overflow': 'false',
      }, () {
        // Um padrão sem nenhum campo de data/hora geraria um estilo inválido.
        var tokens = tokenizeDatePattern(f.pattern!);
        if (!tokens.any((t) => RegExp('^[dMyHhms]').hasMatch(t))) {
          tokens = tokenizeDatePattern(isTime ? 'HH:mm:ss' : 'dd/MM/yyyy');
        }
        for (final token in tokens) {
          final long = token.length >= 2 ? 'long' : null;
          switch (token[0]) {
            case 'd':
              w.el('number:day', {'number:style': long});
            case 'M':
              w.el('number:month', {
                'number:style':
                    token.length == 2 || token.length >= 4 ? 'long' : null,
                'number:textual': token.length >= 3 ? 'true' : null,
              });
            case 'y':
              w.el('number:year',
                  {'number:style': token.length >= 4 ? 'long' : null});
            case 'H' || 'h':
              w.el('number:hours', {'number:style': long});
            case 'm':
              w.el('number:minutes', {'number:style': long});
            case 's':
              w.el('number:seconds', {'number:style': long});
            default:
              w.el('number:text', {}, () => w.text(token));
          }
        }
      });
  }
}

/// Texto exibido na célula (cache usado por leitores que não recalculam).
String displayText(OdfCellValue value, OdfNumberFormat? format) {
  String fixed(num v, int decimals) =>
      decimals == 0 ? v.round().toString() : v.toStringAsFixed(decimals);
  switch (value) {
    case OdfEmptyValue():
      return '';
    case OdfStringValue(:final value):
      return value;
    case OdfNumberValue(:final value):
      return format?.kind == OdfNumberFormatKind.number
          ? fixed(value, format!.decimals)
          : fmtNum(value);
    case OdfPercentageValue(:final value):
      return '${fixed(value * 100, format?.decimals ?? 0)}%';
    case OdfCurrencyValue(:final value, :final currency):
      return '${currencySymbols[currency] ?? currency} ${fixed(value, format?.decimals ?? 2)}';
    case OdfBooleanValue(:final value):
      return value ? 'TRUE' : 'FALSE';
    case OdfDateValue(:final value):
      return formatDate(value, format?.pattern ?? 'dd/MM/yyyy');
    case OdfTimeValue(:final value):
      final total = value.inSeconds;
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(total ~/ 3600)}:${two(total % 3600 ~/ 60)}:${two(total % 60)}';
    case OdfFormula(:final result):
      return result == null ? '' : displayText(result, format);
  }
}

String formatDate(DateTime d, String pattern) {
  const months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez'
  ];
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  return tokenizeDatePattern(pattern).map((t) {
    final long = t.length >= 2;
    return switch (t[0]) {
      'd' => long ? pad(d.day, 2) : '${d.day}',
      'M' => t.length >= 3
          ? months[d.month - 1]
          : (long ? pad(d.month, 2) : '${d.month}'),
      'y' => t.length >= 4 ? pad(d.year, 4) : pad(d.year % 100, 2),
      'H' || 'h' => long ? pad(d.hour, 2) : '${d.hour}',
      'm' => long ? pad(d.minute, 2) : '${d.minute}',
      's' => long ? pad(d.second, 2) : '${d.second}',
      _ => t,
    };
  }).join();
}

// ---------------------------------------------------------------------------
// Imagens e grade de tabelas
// ---------------------------------------------------------------------------

/// Guarda as imagens do pacote e atribui caminhos em `Pictures/`.
/// Imagens com bytes idênticos são gravadas uma única vez.
class OdfImageStore {
  final _byHash = <int, List<(OdfImageData, String)>>{};
  final _entries = <String, OdfImageData>{};

  Map<String, OdfImageData> get entries => Map.unmodifiable(_entries);

  String add(OdfImageData image) {
    final bytes = image.bytes;
    final hash = Object.hash(
        bytes.length,
        image.mimeType,
        Object.hashAll(bytes.take(4096)),
        Object.hashAll(bytes.length > 4096
            ? bytes.skip(bytes.length - 4096)
            : const <int>[]));
    final candidates = _byHash.putIfAbsent(hash, () => []);
    for (final (existing, path) in candidates) {
      if (identical(existing, image) || _sameBytes(existing.bytes, bytes)) {
        return path;
      }
    }
    final path = 'Pictures/image${_entries.length + 1}.${image.extension}';
    candidates.add((image, path));
    _entries[path] = image;
    return path;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Tamanho final da imagem em cm, preservando a proporção e respeitando [maxWidth].
(double, double) imageSize(
    OdfImageData image, double? width, double? height, double maxWidth) {
  final pixels = image.pixelSize;
  final ratio = pixels == null || pixels.$1 == 0 ? 0.75 : pixels.$2 / pixels.$1;
  var w = width ??
      (height != null
          ? height / ratio
          : (pixels == null ? 10.0 : pixels.$1 * 2.54 / 96));
  var h = height ?? w * ratio;
  if (width == null && height == null && w > maxWidth) {
    w = maxWidth;
    h = w * ratio;
  }
  return (w, h);
}

/// Disposição de células com mesclagem: cada posição da grade aponta para o
/// índice da célula na linha, [covered] (ocupada por mesclagem) ou `null` (vazia).
class OdfTableGrid {
  OdfTableGrid._(this.slots, this.rowSpans, this.columnCount);

  static const covered = -1;

  /// [rows]: para cada linha, os pares (colSpan, rowSpan) das células.
  factory OdfTableGrid.layout(List<List<(int, int)>> rows) {
    final occupied = <(int, int)>{};
    final slots = <List<int?>>[];
    final rowSpans = <List<int>>[];
    for (var r = 0; r < rows.length; r++) {
      final row = <int?>[];
      final spans = <int>[];
      var col = 0;
      void skipCovered() {
        while (occupied.remove((r, col))) {
          row.add(covered);
          col++;
        }
      }

      for (var i = 0; i < rows[r].length; i++) {
        skipCovered();
        final (colSpan, rowSpan) = rows[r][i];
        final effectiveRows = rowSpan.clamp(1, rows.length - r);
        spans.add(effectiveRows);
        row.add(i);
        for (var dr = 0; dr < effectiveRows; dr++) {
          for (var dc = 0; dc < colSpan; dc++) {
            if (dr != 0 || dc != 0) occupied.add((r + dr, col + dc));
          }
        }
        col++;
      }
      skipCovered();
      final lastOccupied = occupied
          .where((p) => p.$1 == r)
          .fold(-1, (m, p) => p.$2 > m ? p.$2 : m);
      while (col <= lastOccupied) {
        row.add(occupied.remove((r, col)) ? covered : null);
        col++;
      }
      slots.add(row);
      rowSpans.add(spans);
    }
    final columns = slots.fold(0, (m, r) => r.length > m ? r.length : m);
    for (final row in slots) {
      while (row.length < columns) {
        row.add(null);
      }
    }
    return OdfTableGrid._(slots, rowSpans, columns);
  }

  final List<List<int?>> slots;

  /// rowSpan efetivo (limitado ao fim da tabela) de cada célula, por linha.
  final List<List<int>> rowSpans;
  final int columnCount;
}
