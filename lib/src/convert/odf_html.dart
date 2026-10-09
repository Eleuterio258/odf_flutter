import 'dart:convert';

import '../data/odf/odf_style_writer.dart' show OdfTableGrid, imageSize;
import '../data/odf/odf_xml.dart' show fmtNum;
import '../domain/entities/odf_rich_text.dart';

/// Converte um [OdfRichTextDocument] em HTML com estilos em linha.
/// Imagens são embutidas como `data:` URIs e notas viram uma lista no fim.
class OdfHtmlWriter {
  OdfHtmlWriter({this.fragment = false});

  /// Quando verdadeiro, devolve só o conteúdo, sem `<html>`, `<head>` e `<body>`.
  final bool fragment;

  final _notes = <OdfNote>[];

  String write(OdfRichTextDocument doc) {
    final width = doc.pageLayout.contentWidth;
    final body = StringBuffer();
    if (doc.header.isNotEmpty) {
      body.write('<header>${_blocks(doc.header, width)}</header>\n');
    }
    body.write(_blocks(doc.blocks, width));
    if (_notes.isNotEmpty) {
      body.write('<section class="notes"><hr>\n<ol>\n');
      for (var i = 0; i < _notes.length; i++) {
        final only = _notes[i].body.length == 1 ? _notes[i].body.single : null;
        final content = only is OdfParagraph && only.style.isNormal
            ? _inlines(only.inlines)
            : _blocks(_notes[i].body, width).trim();
        body.write('<li id="nota-${i + 1}">$content</li>\n');
      }
      body.write('</ol></section>\n');
    }
    if (doc.footer.isNotEmpty) {
      body.write('<footer>${_blocks(doc.footer, width)}</footer>\n');
    }
    if (fragment) return body.toString();

    final meta = doc.metadata;
    final lang =
        meta.language == null ? '' : ' lang="${_attr(meta.language!)}"';
    return '<!DOCTYPE html>\n<html$lang>\n<head>\n<meta charset="utf-8">\n'
        '${meta.title == null ? '' : '<title>${_escape(meta.title!)}</title>\n'}'
        '${meta.author == null ? '' : '<meta name="author" content="${_attr(meta.author!)}">\n'}'
        '<style>body{max-width:${fmtNum(width)}cm;margin:2em auto;font-family:serif}'
        'table{border-collapse:collapse}td,th{border:1px solid #000;padding:.1cm;vertical-align:top}'
        '.page-break{page-break-after:always;border:0}</style>\n'
        '</head>\n<body>\n$body</body>\n</html>\n';
  }

  String _blocks(List<OdfBlock> blocks, double width) =>
      blocks.map((b) => _block(b, width)).join();

  String _block(OdfBlock block, double width) {
    switch (block) {
      case OdfParagraph(:final inlines, :final style):
        return '<p${_paragraphStyle(style)}>${_inlines(inlines)}</p>\n';
      case OdfHeading(:final inlines, :final style, :final level):
        return '<h$level${_paragraphStyle(style)}>${_inlines(inlines)}</h$level>\n';
      case OdfList(:final items, :final ordered):
        final tag = ordered ? 'ol' : 'ul';
        final out = StringBuffer('<$tag>\n');
        for (final item in items) {
          // Um único parágrafo simples fica sem <p>, como num HTML escrito à mão.
          final only = item.blocks.length == 1 ? item.blocks.single : null;
          final content = only is OdfParagraph && only.style.isNormal
              ? _inlines(only.inlines)
              : _blocks(item.blocks, width).trim();
          out.write('<li>$content</li>\n');
        }
        return '$out</$tag>\n';
      case OdfTable():
        return _table(block, width);
      case OdfImage(:final data, :final align, :final description):
        final (w, h) = imageSize(data, block.width, block.height, width);
        final img =
            '<img src="data:${data.mimeType};base64,${base64.encode(data.bytes)}"'
            ' alt="${_attr(description ?? '')}" style="width:${fmtNum(w)}cm;height:${fmtNum(h)}cm">';
        return '<p style="text-align:${_align(align ?? OdfTextAlign.center)}">$img</p>\n';
      case OdfPageBreak():
        return '<hr class="page-break">\n';
    }
  }

  String _table(OdfTable table, double width) {
    final grid = OdfTableGrid.layout([
      for (final row in table.rows)
        [for (final c in row.cells) (c.colSpan, c.rowSpan)],
    ]);
    final out = StringBuffer('<table>\n');
    final widths = table.columnWidths;
    if (widths != null) {
      out.write(
          '<colgroup>${widths.map((w) => '<col style="width:${fmtNum(w)}cm">').join()}</colgroup>\n');
    }
    for (var r = 0; r < table.rows.length; r++) {
      if (r == 0 && table.headerRows > 0) out.write('<thead>\n');
      if (r == table.headerRows && table.headerRows > 0) out.write('<tbody>\n');
      final header = r < table.headerRows;
      final tag = header ? 'th' : 'td';
      out.write('<tr>');
      for (final slot in grid.slots[r]) {
        if (slot == OdfTableGrid.covered) continue;
        if (slot == null) {
          out.write('<$tag></$tag>');
          continue;
        }
        final cell = table.rows[r].cells[slot];
        final rowSpan = grid.rowSpans[r][slot];
        final attrs = StringBuffer();
        if (cell.colSpan > 1) attrs.write(' colspan="${cell.colSpan}"');
        if (rowSpan > 1) attrs.write(' rowspan="$rowSpan"');
        if (cell.backgroundColor != null) {
          attrs.write(
              ' style="background-color:${cell.backgroundColor!.toHex()}"');
        }
        final only = cell.blocks.length == 1 ? cell.blocks.single : null;
        final content = only is OdfParagraph && only.style.isNormal
            ? _inlines(only.inlines)
            : _blocks(cell.blocks, width).trim();
        out.write('<$tag$attrs>$content</$tag>');
      }
      out.write('</tr>\n');
      if (r == table.headerRows - 1) out.write('</thead>\n');
    }
    if (table.headerRows > 0 && table.rows.length > table.headerRows) {
      out.write('</tbody>\n');
    }
    return '$out</table>\n';
  }

  String _inlines(List<OdfInline> inlines) {
    final out = StringBuffer();
    for (final inline in inlines) {
      switch (inline) {
        case OdfSpan(:final text, :final style):
          out.write(_styled(_text(text), style));
        case OdfLink(:final text, :final url, :final style):
          out.write(
              '<a href="${_attr(url)}">${_styled(_text(text), style)}</a>');
        case OdfLineBreak():
          out.write('<br>');
        case OdfTab():
          out.write('&emsp;');
        case OdfPageNumber() || OdfPageCount():
          out.write('#');
        case OdfNote():
          _notes.add(inline);
          final n = _notes.length;
          out.write(
              '<sup><a href="#nota-$n">${_escape(inline.citation ?? '$n')}</a></sup>');
      }
    }
    return out.toString();
  }

  String _styled(String html, OdfTextStyle s) {
    var out = html;
    if (s.bold) out = '<strong>$out</strong>';
    if (s.italic) out = '<em>$out</em>';
    if (s.underline) out = '<u>$out</u>';
    if (s.strikethrough) out = '<s>$out</s>';
    if (s.superscript) out = '<sup>$out</sup>';
    if (s.subscript) out = '<sub>$out</sub>';
    final css = [
      if (s.color != null) 'color:${s.color!.toHex()}',
      if (s.backgroundColor != null)
        'background-color:${s.backgroundColor!.toHex()}',
      if (s.fontSize != null) 'font-size:${fmtNum(s.fontSize!)}pt',
      if (s.fontFamily != null)
        "font-family:'${s.fontFamily!.replaceAll("'", '')}'",
    ];
    return css.isEmpty
        ? out
        : '<span style="${_attr(css.join(';'))}">$out</span>';
  }

  /// Escapa o texto e preserva quebras, tabulações e espaços múltiplos.
  String _text(String text) => _escape(text)
      .replaceAll('\r', '')
      .replaceAll('\n', '<br>')
      .replaceAll('\t', '&emsp;')
      .replaceAllMapped(
          RegExp(' {2,}'), (m) => ' ${'&nbsp;' * (m.group(0)!.length - 1)}');

  String _paragraphStyle(OdfParagraphStyle s) {
    if (s.isNormal) return '';
    final css = [
      if (s.align != null) 'text-align:${_align(s.align!)}',
      if (s.spaceBefore != null) 'margin-top:${fmtNum(s.spaceBefore!)}cm',
      if (s.spaceAfter != null) 'margin-bottom:${fmtNum(s.spaceAfter!)}cm',
      if (s.indentLeft != null) 'margin-left:${fmtNum(s.indentLeft!)}cm',
      if (s.firstLineIndent != null)
        'text-indent:${fmtNum(s.firstLineIndent!)}cm',
      if (s.lineSpacing != null) 'line-height:${fmtNum(s.lineSpacing!)}',
      if (s.backgroundColor != null)
        'background-color:${s.backgroundColor!.toHex()}',
    ];
    return ' style="${_attr(css.join(';'))}"';
  }

  static String _align(OdfTextAlign a) => switch (a) {
        OdfTextAlign.start => 'left',
        OdfTextAlign.center => 'center',
        OdfTextAlign.end => 'right',
        OdfTextAlign.justify => 'justify',
      };

  static String _escape(String s) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(s);

  static String _attr(String s) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(s);
}
