import 'dart:convert';

import '../data/odf/odf_style_writer.dart' show OdfTableGrid;
import '../domain/entities/odf_image.dart';
import '../domain/entities/odf_metadata.dart';
import '../domain/entities/odf_rich_text.dart';

const _mono = 'Liberation Mono';

// ===========================================================================
// ODT -> Markdown
// ===========================================================================

/// Converte para Markdown no estilo GitHub (tabelas, `~~tachado~~`, notas `[^1]`).
///
/// Quebras de página viram `---`. Imagens são embutidas como `data:` URIs,
/// a menos que [imageUrl] devolva outro endereço.
class OdfMarkdownWriter {
  OdfMarkdownWriter({this.imageUrl});

  final String Function(OdfImageData image, int index)? imageUrl;

  final _notes = <OdfNote>[];
  var _images = 0;

  String write(OdfRichTextDocument doc) {
    final out = StringBuffer(_blocks(doc.blocks, ''));
    for (var i = 0; i < _notes.length; i++) {
      final body = _blocks(_notes[i].body, '    ').trim();
      out.write('\n[^${i + 1}]: $body\n');
    }
    return '${out.toString().trimRight()}\n';
  }

  String _blocks(List<OdfBlock> blocks, String indent) {
    final parts = <String>[];
    for (final block in blocks) {
      parts.add(_block(block, indent));
    }
    return parts.where((p) => p.isNotEmpty).join('\n$indent');
  }

  String _block(OdfBlock block, String indent) {
    switch (block) {
      case OdfParagraph(:final inlines):
        final text = _inlines(inlines, indent);
        return text.isEmpty ? '' : '${_escapeLineStart(text)}\n';
      case OdfHeading(:final inlines, :final level):
        return '${'#' * level} ${_inlines(inlines, indent).replaceAll('\\\n$indent', ' ')}\n';
      case OdfList(:final items, :final ordered):
        final out = StringBuffer();
        for (var i = 0; i < items.length; i++) {
          final marker = ordered ? '${i + 1}. ' : '- ';
          final inner = '$indent${' ' * marker.length}';
          final content = _blocks(items[i].blocks, inner).trimRight();
          out.write('${i == 0 ? '' : indent}$marker$content\n');
        }
        return out.toString();
      case OdfTable():
        return _table(block, indent);
      case OdfImage(:final data, :final description):
        return '${_image(data, description)}\n';
      case OdfPageBreak():
        return '---\n';
    }
  }

  String _image(OdfImageData data, String? description) {
    _images++;
    final url = imageUrl?.call(data, _images) ??
        'data:${data.mimeType};base64,${base64.encode(data.bytes)}';
    return '![${_escape(description ?? '')}]($url)';
  }

  String _table(OdfTable table, String indent) {
    if (table.rows.isEmpty) return '';
    final grid = OdfTableGrid.layout([
      for (final row in table.rows)
        [for (final c in row.cells) (c.colSpan, c.rowSpan)],
    ]);
    String cell(int r, int? slot) {
      if (slot == null || slot == OdfTableGrid.covered) return '';
      final c = table.rows[r].cells[slot];
      return c.blocks
          .map((b) => b is OdfParagraph || b is OdfHeading
              ? _inlines(_inlinesOf(b), indent)
              : b.plainText)
          .join('<br>')
          .replaceAll(RegExp(r'\\\n *'), '<br>')
          .replaceAll('|', r'\|')
          .replaceAll('\n', ' ');
    }

    final lines = <String>[];
    // Markdown exige uma linha de cabeçalho; sem cabeçalho no ODT, ela fica vazia.
    final headerRow = table.headerRows > 0 ? 0 : -1;
    final columns = grid.columnCount;
    String row(List<String> cells) => '| ${cells.join(' | ')} |';
    lines.add(row([
      for (var c = 0; c < columns; c++)
        headerRow < 0 ? ' ' : cell(0, grid.slots[0][c])
    ]));
    lines.add(row(List.filled(columns, '---')));
    for (var r = headerRow + 1; r < table.rows.length; r++) {
      lines.add(
          row([for (var c = 0; c < columns; c++) cell(r, grid.slots[r][c])]));
    }
    return '${lines.join('\n$indent')}\n';
  }

  static List<OdfInline> _inlinesOf(OdfBlock b) => switch (b) {
        OdfParagraph(:final inlines) => inlines,
        OdfHeading(:final inlines) => inlines,
        _ => const [],
      };

  String _inlines(List<OdfInline> inlines, String indent) {
    final out = StringBuffer();
    for (final inline in inlines) {
      switch (inline) {
        case OdfSpan(:final text, :final style):
          out.write(_styled(text, style, indent));
        case OdfLink(:final text, :final url, :final style):
          out.write(
              '[${_styled(text, style, indent)}](${url.replaceAll(' ', '%20').replaceAll(')', '%29')})');
        case OdfLineBreak():
          out.write('\\\n$indent');
        case OdfTab():
          out.write('\t');
        case OdfPageNumber() || OdfPageCount():
          out.write('#');
        case OdfNote():
          _notes.add(inline);
          out.write('[^${_notes.length}]');
      }
    }
    return out.toString();
  }

  /// Aplica marcadores sem incluir os espaços das pontas, que o Markdown não aceita.
  String _styled(String text, OdfTextStyle style, String indent) {
    final lines = text.split('\n');
    final rendered = <String>[];
    for (final line in lines) {
      final match = RegExp(r'^(\s*)(.*?)(\s*)$').firstMatch(line)!;
      var core = style.fontFamily == _mono
          ? _code(match.group(2)!)
          : _escape(match.group(2)!);
      if (core.isNotEmpty) {
        if (style.strikethrough) core = '~~$core~~';
        if (style.italic) core = '*$core*';
        if (style.bold) core = '**$core**';
        if (style.superscript) core = '<sup>$core</sup>';
        if (style.subscript) core = '<sub>$core</sub>';
        if (style.underline) core = '<u>$core</u>';
      }
      rendered.add('${match.group(1)}$core${match.group(3)}');
    }
    return rendered.join('\\\n$indent');
  }

  static String _code(String s) => s.contains('`') ? '`` $s ``' : '`$s`';

  static String _escape(String s) =>
      s.replaceAllMapped(RegExp(r'[\\`*_\[\]<>~]'), (m) => '\\${m.group(0)}');

  /// Evita que um parágrafo comece com algo que o Markdown leia como título ou lista.
  static String _escapeLineStart(String s) => s.replaceFirstMapped(
      RegExp(r'^(#{1,6} |[-+] |\d+[.)] |> |---$)'), (m) => '\\${m.group(0)}');
}

// ===========================================================================
// Markdown -> ODT
// ===========================================================================

/// Lê Markdown (CommonMark com tabelas, `~~tachado~~` e notas do GitHub).
///
/// Imagens com `data:` URI são embutidas; outros endereços são passados a
/// [imageLoader] e, se ele não devolver bytes, viram o texto alternativo.
class OdfMarkdownReader {
  OdfMarkdownReader({this.imageLoader});

  final List<int>? Function(String url)? imageLoader;

  final _footnotes = <String, String>{};

  OdfRichTextDocument read(String markdown,
      {OdfMetadata metadata = const OdfMetadata()}) {
    final lines =
        const LineSplitter().convert(markdown.replaceAll('\t', '    '));
    final kept = <String>[];
    String? note;
    for (final line in lines) {
      final m = RegExp(r'^\[\^([^\]]+)\]:\s?(.*)$').firstMatch(line);
      if (m != null) {
        note = m.group(1)!;
        _footnotes[note] = m.group(2)!;
      } else if (note != null && line.startsWith('    ')) {
        _footnotes[note] = '${_footnotes[note]}\n${line.substring(4)}';
      } else {
        note = null;
        kept.add(line);
      }
    }
    return OdfRichTextDocument(blocks: _blocks(kept), metadata: metadata);
  }

  List<OdfBlock> _blocks(List<String> lines) {
    final blocks = <OdfBlock>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      final heading =
          RegExp(r'^ {0,3}(#{1,6})(?:\s+(.*?))?\s*#*\s*$').firstMatch(line);
      if (heading != null) {
        blocks.add(OdfHeading(_inline(heading.group(2) ?? ''),
            level: heading.group(1)!.length));
        i++;
        continue;
      }

      if (RegExp(r'^ {0,3}([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
        blocks.add(const OdfPageBreak());
        i++;
        continue;
      }

      final fence = RegExp(r'^ {0,3}(```+|~~~+)').firstMatch(line);
      if (fence != null) {
        final code = <String>[];
        i++;
        while (i < lines.length &&
            !lines[i].trimLeft().startsWith(fence.group(1)!)) {
          code.add(lines[i]);
          i++;
        }
        i++;
        blocks.add(OdfParagraph.text(code.join('\n'),
            style: const OdfTextStyle(fontFamily: _mono)));
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quoted = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoted.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        for (final b in _blocks(quoted)) {
          blocks.add(b is OdfParagraph
              ? OdfParagraph(b.inlines,
                  style: const OdfParagraphStyle(indentLeft: 1))
              : b);
        }
        continue;
      }

      if (_listMarker(line) != null) {
        final (list, next) = _list(lines, i);
        blocks.add(list);
        i = next;
        continue;
      }

      if (i + 1 < lines.length &&
          trimmed.contains('|') &&
          _isDelimiterRow(lines[i + 1])) {
        final (table, next) = _table(lines, i);
        blocks.add(table);
        i = next;
        continue;
      }

      // Parágrafo: linhas até uma linha vazia ou outro tipo de bloco. Um
      // sublinhado com === ou --- transforma o parágrafo em título (setext).
      final paragraph = <String>[line];
      i++;
      int? setext;
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        final underline = RegExp(r'^ {0,3}(=+|-+)\s*$').firstMatch(lines[i]);
        if (underline != null) {
          setext = underline.group(1)!.startsWith('=') ? 1 : 2;
          i++;
          break;
        }
        if (_startsBlock(lines, i)) break;
        paragraph.add(lines[i]);
        i++;
      }
      if (setext != null) {
        blocks.add(OdfHeading(_inline(paragraph.map((l) => l.trim()).join(' ')),
            level: setext));
      } else {
        blocks.addAll(_paragraph(paragraph));
      }
    }
    return blocks;
  }

  bool _startsBlock(List<String> lines, int i) {
    final line = lines[i];
    return RegExp(r'^ {0,3}(#{1,6}(\s|$)|```|~~~|>)').hasMatch(line) ||
        RegExp(r'^ {0,3}([-*_])(\s*\1){2,}\s*$').hasMatch(line) ||
        _listMarker(line) != null ||
        (i + 1 < lines.length &&
            line.contains('|') &&
            _isDelimiterRow(lines[i + 1]));
  }

  List<OdfBlock> _paragraph(List<String> lines) {
    final text = StringBuffer();
    for (var k = 0; k < lines.length; k++) {
      var line = lines[k].trimLeft();
      final last = k == lines.length - 1;
      if (!last && (line.endsWith('  ') || line.endsWith('\\'))) {
        line = line.endsWith('\\')
            ? line.substring(0, line.length - 1)
            : line.trimRight();
        text.write('$line\u0000');
      } else {
        text.write(last ? line.trimRight() : '${line.trimRight()} ');
      }
    }
    final content = text.toString();
    final image =
        RegExp(r'^!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)$')
            .firstMatch(content);
    if (image != null) {
      final bytes = _loadImage(image.group(2)!);
      if (bytes != null) {
        return [
          OdfImage(OdfImageData(bytes), description: _unescape(image.group(1)!))
        ];
      }
    }
    return [OdfParagraph(_inline(content))];
  }

  List<int>? _loadImage(String url) {
    final data = RegExp(r'^data:([^;,]+)?;base64,(.*)$').firstMatch(url);
    if (data != null) {
      try {
        final bytes = base64.decode(data.group(2)!);
        return OdfImageData.detectMimeType(bytes) == null ? null : bytes;
      } on FormatException {
        return null;
      }
    }
    final bytes = imageLoader?.call(url);
    return bytes != null && OdfImageData.detectMimeType(bytes) != null
        ? bytes
        : null;
  }

  // ---------------------------------------------------------------- listas

  (String marker, int indent, bool ordered)? _listMarker(String line) {
    final m = RegExp(r'^( *)([-*+]|\d{1,9}[.)])( +|$)').firstMatch(line);
    if (m == null) return null;
    final ordered = !RegExp('^[-*+]').hasMatch(m.group(2)!);
    return (m.group(0)!, m.group(1)!.length, ordered);
  }

  (OdfList, int) _list(List<String> lines, int start) {
    final first = _listMarker(lines[start])!;
    final baseIndent = first.$2;
    final items = <List<String>>[];
    var i = start;
    while (i < lines.length) {
      final line = lines[i];
      final marker = _listMarker(line);
      if (marker != null && marker.$2 == baseIndent && marker.$3 == first.$3) {
        final contentIndent = marker.$1.length;
        items.add([line.substring(contentIndent)]);
        i++;
        // Linhas de continuação (indentadas) e listas aninhadas pertencem ao item.
        while (i < lines.length) {
          final next = lines[i];
          if (next.trim().isEmpty) {
            if (i + 1 < lines.length && _indentOf(lines[i + 1]) > baseIndent) {
              items.last.add('');
              i++;
              continue;
            }
            break;
          }
          final nextMarker = _listMarker(next);
          if (nextMarker != null && nextMarker.$2 <= baseIndent) break;
          if (nextMarker == null &&
              _indentOf(next) <= baseIndent &&
              _startsBlock(lines, i)) {
            break;
          }
          items.last.add(next.length >= contentIndent &&
                  next.substring(0, contentIndent).trim().isEmpty
              ? next.substring(contentIndent)
              : next.trimLeft());
          i++;
        }
        continue;
      }
      break;
    }
    return (
      OdfList([for (final item in items) OdfListItem(_blocks(item))],
          ordered: first.$3),
      i
    );
  }

  static int _indentOf(String line) => line.length - line.trimLeft().length;

  // --------------------------------------------------------------- tabelas

  static bool _isDelimiterRow(String line) =>
      RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$').hasMatch(line) &&
      line.contains('-');

  static List<String> _cells(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
    final cells = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length && s[i + 1] == '|') {
        buffer.write('|');
        i++;
      } else if (s[i] == '|') {
        cells.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(s[i]);
      }
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  (OdfTable, int) _table(List<String> lines, int start) {
    final header = _cells(lines[start]);
    final aligns = [
      for (final d in _cells(lines[start + 1]))
        d.startsWith(':') && d.endsWith(':')
            ? OdfTextAlign.center
            : d.endsWith(':')
                ? OdfTextAlign.end
                : d.startsWith(':')
                    ? OdfTextAlign.start
                    : null,
    ];
    OdfTableRow row(List<String> cells, {bool bold = false}) => OdfTableRow([
          for (var c = 0; c < header.length; c++)
            OdfTableCell([
              for (final part in (c < cells.length ? cells[c] : '')
                  .split(RegExp(r'<br\s*/?>')))
                OdfParagraph(_inline(part, bold: bold),
                    style: OdfParagraphStyle(
                        align: c < aligns.length ? aligns[c] : null)),
            ]),
        ]);

    final emptyHeader = header.every((h) => h.isEmpty);
    final rows = [if (!emptyHeader) row(header, bold: true)];
    var i = start + 2;
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        lines[i].contains('|')) {
      rows.add(row(_cells(lines[i])));
      i++;
    }
    return (OdfTable(rows, headerRows: emptyHeader ? 0 : 1), i);
  }

  // -------------------------------------------------------------- em linha

  List<OdfInline> _inline(String text, {bool bold = false}) {
    final out = <OdfInline>[];
    _parseInline(text, OdfTextStyle(bold: bold), out);
    return _merge(out);
  }

  void _parseInline(String s, OdfTextStyle style, List<OdfInline> out) {
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) out.add(OdfSpan(buffer.toString(), style: style));
      buffer.clear();
    }

    var i = 0;
    while (i < s.length) {
      final c = s[i];
      final rest = s.substring(i);

      if (c == '\u0000') {
        flush();
        out.add(const OdfLineBreak());
        i++;
        continue;
      }
      if (c == '\\' &&
          i + 1 < s.length &&
          RegExp(r'[!-/:-@\[-`{-~]').hasMatch(s[i + 1])) {
        buffer.write(s[i + 1]);
        i += 2;
        continue;
      }
      if (c == '`') {
        final ticks = RegExp('^`+').firstMatch(rest)!.group(0)!;
        final end = s.indexOf(ticks, i + ticks.length);
        if (end > 0) {
          flush();
          var code = s.substring(i + ticks.length, end);
          if (code.startsWith(' ') &&
              code.endsWith(' ') &&
              code.trim().isNotEmpty) {
            code = code.substring(1, code.length - 1);
          }
          out.add(OdfSpan(code, style: style.copyWith(fontFamily: _mono)));
          i = end + ticks.length;
          continue;
        }
      }
      final footnote = RegExp(r'^\[\^([^\]]+)\]').firstMatch(rest);
      if (footnote != null && _footnotes.containsKey(footnote.group(1))) {
        flush();
        final body = _footnotes[footnote.group(1)]!;
        out.add(OdfNote(OdfMarkdownReader(imageLoader: imageLoader)
            ._blocks(const LineSplitter().convert(body))));
        i += footnote.group(0)!.length;
        continue;
      }
      final link = RegExp(
              r'^(!?)\[((?:\\.|[^\]\\])*)\]\(\s*<?([^)\s>]*)>?(?:\s+"[^"]*")?\s*\)')
          .firstMatch(rest);
      if (link != null) {
        flush();
        final label = link.group(2)!;
        final url = link.group(3)!;
        if (link.group(1) == '!') {
          // Imagem dentro do texto: o modelo só tem imagens em bloco.
          if (label.isNotEmpty) {
            out.add(OdfSpan(_unescape(label), style: style));
          }
        } else {
          final inner = <OdfInline>[];
          _parseInline(label, style, inner);
          for (final part in _merge(inner)) {
            if (part is OdfSpan) {
              out.add(OdfLink(part.text, url, style: part.style));
            }
          }
        }
        i += link.group(0)!.length;
        continue;
      }
      final autolink =
          RegExp(r'^<((?:https?|mailto):[^>\s]+)>').firstMatch(rest);
      if (autolink != null) {
        flush();
        out.add(OdfLink(autolink.group(1)!, autolink.group(1)!, style: style));
        i += autolink.group(0)!.length;
        continue;
      }
      final html = RegExp(r'^<(u|sup|sub|ins|del|s|strong|b|em|i)>(.*?)</\1>')
          .firstMatch(rest);
      if (html != null) {
        flush();
        final tag = html.group(1)!;
        _parseInline(
          html.group(2)!,
          switch (tag) {
            'u' || 'ins' => style.copyWith(underline: true),
            'sup' => style.copyWith(superscript: true),
            'sub' => style.copyWith(subscript: true),
            'del' || 's' => style.copyWith(strikethrough: true),
            'strong' || 'b' => style.copyWith(bold: true),
            _ => style.copyWith(italic: true),
          },
          out,
        );
        i += html.group(0)!.length;
        continue;
      }
      final emphasis = _emphasis(s, i);
      if (emphasis != null) {
        flush();
        final (marker, end) = emphasis;
        final inner = s.substring(i + marker.length, end);
        final next = switch (marker) {
          '**' || '__' => style.copyWith(bold: true),
          '~~' => style.copyWith(strikethrough: true),
          '***' || '___' => style.copyWith(bold: true, italic: true),
          _ => style.copyWith(italic: true),
        };
        _parseInline(inner, next, out);
        i = end + marker.length;
        continue;
      }
      buffer.write(c);
      i++;
    }
    flush();
  }

  /// Procura o fechamento de `*`, `_`, `**`, `__`, `***` ou `~~` a partir de [i].
  (String, int)? _emphasis(String s, int i) {
    final m = RegExp(r'^(\*{1,3}|_{1,3}|~~)').firstMatch(s.substring(i));
    if (m == null) return null;
    final marker = m.group(1)!;
    final open = i + marker.length;
    if (open >= s.length || s[open] == ' ') return null;
    // "_" no meio de palavras (nome_de_variavel) não é ênfase.
    if (marker.startsWith('_') && i > 0 && RegExp(r'\w').hasMatch(s[i - 1])) {
      return null;
    }
    var j = open;
    while (true) {
      j = s.indexOf(marker, j);
      if (j < 0) return null;
      final escaped = j > 0 && s[j - 1] == '\\';
      final afterSpace = s[j - 1] == ' ';
      final longer = j + marker.length < s.length &&
          s[j + marker.length] == marker[0] &&
          marker != '~~';
      final wordAfter = marker.startsWith('_') &&
          j + marker.length < s.length &&
          RegExp(r'\w').hasMatch(s[j + marker.length]);
      if (j > open && !escaped && !afterSpace && !longer && !wordAfter) {
        return (marker, j);
      }
      j += 1;
    }
  }

  static List<OdfInline> _merge(List<OdfInline> inlines) {
    final out = <OdfInline>[];
    for (final inline in inlines) {
      final last = out.isEmpty ? null : out.last;
      if (inline is OdfSpan && last is OdfSpan && last.style == inline.style) {
        out[out.length - 1] =
            OdfSpan(last.text + inline.text, style: last.style);
      } else if (inline is OdfLink &&
          last is OdfLink &&
          last.url == inline.url &&
          last.style == inline.style) {
        out[out.length - 1] =
            OdfLink(last.text + inline.text, last.url, style: last.style);
      } else if (!(inline is OdfSpan && inline.text.isEmpty)) {
        out.add(inline);
      }
    }
    return out;
  }

  static String _unescape(String s) =>
      s.replaceAllMapped(RegExp(r'\\([!-/:-@\[-`{-~])'), (m) => m.group(1)!);
}
