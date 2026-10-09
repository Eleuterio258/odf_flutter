import 'dart:convert';

import 'package:xml/xml.dart';

import '../../domain/entities/odf_color.dart';
import '../../domain/entities/odf_image.dart';
import '../../domain/entities/odf_rich_text.dart';
import 'odf_style_reader.dart';
import 'odf_xml.dart';

/// Busca arquivos internos do pacote (imagens) e seus tipos no manifesto.
typedef OdfFileLookup = ({
  List<int>? Function(String path) file,
  String? Function(String path) mediaType
});

/// Converte elementos de texto ODF de volta para o modelo [OdfBlock].
class OdfTextReader {
  OdfTextReader(this.styles, this.files);

  final OdfStyleSheet styles;
  final OdfFileLookup files;

  /// Formatação herdada do contêiner (ex.: estilo automático de uma caixa de texto).
  TextProps _base = TextProps.empty;

  List<OdfBlock> blocksWithBase(XmlElement parent, TextProps base) {
    final previous = _base;
    _base = base;
    try {
      return blocks(parent);
    } finally {
      _base = previous;
    }
  }

  /// Estilo do primeiro trecho de texto (títulos de slide e texto de formas).
  OdfTextStyle firstStyle(Iterable<XmlElement> paragraphs) {
    for (final p in paragraphs) {
      final collector = _InlineCollector();
      _inlines(
          p,
          styles.textProps('paragraph', p.attr(OdfNs.text, 'style-name'),
              directOnly: true),
          collector,
          [],
          null);
      for (final inline in collector.finish()) {
        if (inline is OdfSpan) return inline.style;
      }
    }
    return OdfTextStyle.plain;
  }

  List<OdfBlock> blocks(XmlElement parent,
      {String? listStyle, int listLevel = 0}) {
    final out = <OdfBlock>[];
    for (final e in parent.childElements) {
      _block(e, out, listStyle: listStyle, listLevel: listLevel);
    }
    return out;
  }

  void _block(XmlElement e, List<OdfBlock> out,
      {String? listStyle, int listLevel = 0}) {
    final ns = e.name.namespaceUri;
    final local = e.name.local;
    if (ns == OdfNs.text) {
      switch (local) {
        case 'p' || 'h':
          _paragraph(e, out, heading: local == 'h');
        case 'list':
          out.add(_list(e, inheritedStyle: listStyle, level: listLevel + 1));
        case 'section' || 'index-body':
          out.addAll(blocks(e, listStyle: listStyle, listLevel: listLevel));
        case 'table-of-content' ||
              'alphabetical-index' ||
              'illustration-index' ||
              'table-index' ||
              'object-index' ||
              'user-index' ||
              'bibliography':
          final body = e.child(OdfNs.text, 'index-body');
          if (body != null) out.addAll(blocks(body));
      }
    } else if (e.isA(OdfNs.table, 'table')) {
      out.add(_table(e));
    } else if (e.isA(OdfNs.draw, 'frame')) {
      final image = this.image(e);
      if (image != null) out.add(image);
    }
  }

  // ------------------------------------------------------------ parágrafos

  void _paragraph(XmlElement e, List<OdfBlock> out, {required bool heading}) {
    final styleName = e.attr(OdfNs.text, 'style-name');
    final base =
        _base.merge(styles.textProps('paragraph', styleName, directOnly: true));
    final collector = _InlineCollector();
    final images = <OdfImage>[];
    _inlines(e, base, collector, images, null);
    final inlines = collector.finish();
    final style = styles.paragraphStyle(styleName);

    final breakBefore = styles.breakBefore(styleName);
    if (breakBefore) out.add(const OdfPageBreak());

    final isEmpty = inlines.isEmpty;
    if (!(isEmpty && (images.isNotEmpty || breakBefore))) {
      if (heading) {
        final level =
            int.tryParse(e.attr(OdfNs.text, 'outline-level') ?? '') ?? 1;
        out.add(OdfHeading(inlines, level: level.clamp(1, 6), style: style));
      } else {
        out.add(OdfParagraph(inlines, style: style));
      }
    }
    for (final image in images) {
      out.add(OdfImage(image.data,
          width: image.width,
          height: image.height,
          align: style.align,
          description: image.description));
    }
    if (styles.breakAfter(styleName)) out.add(const OdfPageBreak());
  }

  /// Texto puro de um elemento (títulos de slide, notas, células).
  String plainText(XmlElement e) {
    final collector = _InlineCollector();
    _inlines(e, TextProps.empty, collector, [], null);
    return collector.finish().map((i) => i.plainText).join();
  }

  void _inlines(XmlElement parent, TextProps props, _InlineCollector out,
      List<OdfImage> images, String? link) {
    for (final node in parent.children) {
      if (node is XmlText || node is XmlCDATA) {
        out.add(
            node.value!
                .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
                .replaceAll(RegExp(' {2,}'), ' '),
            props,
            link);
        continue;
      }
      if (node is! XmlElement) continue;
      final ns = node.name.namespaceUri;
      final local = node.name.local;
      if (ns == OdfNs.text) {
        switch (local) {
          case 's':
            out.add(' ' * (int.tryParse(node.attr(OdfNs.text, 'c') ?? '') ?? 1),
                props, link);
          case 'tab':
            out.add('\t', props, link);
          case 'line-break':
            out.add('\n', props, link);
          case 'span':
            final style = props.merge(
                styles.textProps('text', node.attr(OdfNs.text, 'style-name')));
            _inlines(node, style, out, images, link);
          case 'a':
            _inlines(node, props, out, images, node.attr(OdfNs.xlink, 'href'));
          case 'page-number':
            out.field(OdfPageNumber(style: props.toStyle()));
          case 'page-count':
            out.field(OdfPageCount(style: props.toStyle()));
          case 'note':
            final body = node.child(OdfNs.text, 'note-body');
            out.field(OdfNote(
              body == null ? const [] : blocks(body),
              endnote: node.attr(OdfNs.text, 'note-class') == 'endnote',
              citation: node
                  .child(OdfNs.text, 'note-citation')
                  ?.attr(OdfNs.text, 'label'),
            ));
          case 'bookmark' ||
                'bookmark-start' ||
                'bookmark-end' ||
                'soft-page-break':
          case 'reference-mark' ||
                'reference-mark-start' ||
                'reference-mark-end' ||
                'tracked-changes':
            break;
          default:
            _inlines(node, props, out, images, link);
        }
      } else if (node.isA(OdfNs.draw, 'frame')) {
        final image = this.image(node);
        if (image != null) images.add(image);
      } else if (node.isA(OdfNs.draw, 'a')) {
        _inlines(node, props, out, images, link);
      }
    }
  }

  // ---------------------------------------------------------------- listas

  OdfList _list(XmlElement e, {String? inheritedStyle, required int level}) {
    final styleName = e.attr(OdfNs.text, 'style-name') ?? inheritedStyle;
    final ordered = styles.listOrdered(styleName, level) ??
        styles.listOrdered(styleName, 1) ??
        false;
    final items = <OdfListItem>[];
    for (final item in e.childElements) {
      if (item.isA(OdfNs.text, 'list-item') ||
          item.isA(OdfNs.text, 'list-header')) {
        items.add(
            OdfListItem(blocks(item, listStyle: styleName, listLevel: level)));
      }
    }
    return OdfList(items, ordered: ordered);
  }

  // --------------------------------------------------------------- tabelas

  OdfTable _table(XmlElement e) {
    final widths = <double?>[];
    var headerRows = 0;
    final rows = <OdfTableRow>[];

    void columns(XmlElement parent) {
      for (final c in parent.childElements) {
        if (c.isA(OdfNs.table, 'table-column')) {
          final repeat = (int.tryParse(
                      c.attr(OdfNs.table, 'number-columns-repeated') ?? '') ??
                  1)
              .clamp(1, 1024);
          final width = styles.columnWidth(c.attr(OdfNs.table, 'style-name'));
          for (var i = 0; i < repeat; i++) {
            widths.add(width);
          }
        } else if (c.isA(OdfNs.table, 'table-columns') ||
            c.isA(OdfNs.table, 'table-header-columns') ||
            c.isA(OdfNs.table, 'table-column-group')) {
          columns(c);
        }
      }
    }

    void collectRows(XmlElement parent, {bool header = false}) {
      for (final r in parent.childElements) {
        if (r.isA(OdfNs.table, 'table-row')) {
          final cells = <OdfTableCell>[];
          for (final c in r.childElements
              .where((c) => c.isA(OdfNs.table, 'table-cell'))) {
            final repeat = (int.tryParse(
                        c.attr(OdfNs.table, 'number-columns-repeated') ?? '') ??
                    1)
                .clamp(1, 1024);
            final cellStyle = c.attr(OdfNs.table, 'style-name');
            final background = styles
                .cellProps(cellStyle, 'table-cell-properties')
                ?.attr(OdfNs.fo, 'background-color');
            for (var i = 0; i < repeat; i++) {
              cells.add(OdfTableCell(
                blocks(c),
                colSpan: int.tryParse(
                        c.attr(OdfNs.table, 'number-columns-spanned') ?? '') ??
                    1,
                rowSpan: int.tryParse(
                        c.attr(OdfNs.table, 'number-rows-spanned') ?? '') ??
                    1,
                backgroundColor: background == 'transparent'
                    ? null
                    : OdfColor.tryParse(background),
              ));
            }
          }
          final repeat = (int.tryParse(
                      r.attr(OdfNs.table, 'number-rows-repeated') ?? '') ??
                  1)
              .clamp(1, 1024);
          for (var i = 0; i < repeat; i++) {
            rows.add(OdfTableRow(cells));
            if (header) headerRows++;
          }
        } else if (r.isA(OdfNs.table, 'table-header-rows')) {
          collectRows(r, header: true);
        } else if (r.isA(OdfNs.table, 'table-rows') ||
            r.isA(OdfNs.table, 'table-row-group')) {
          collectRows(r, header: header);
        }
      }
    }

    columns(e);
    collectRows(e);
    final known = widths.every((w) => w != null) && widths.isNotEmpty;
    return OdfTable(rows,
        headerRows: headerRows,
        columnWidths: known ? widths.cast<double>() : null,
        name: e.attr(OdfNs.table, 'name'));
  }

  // --------------------------------------------------------------- imagens

  OdfImage? image(XmlElement frame) {
    final data = imageData(frame);
    if (data == null) return null;
    return OdfImage(
      data,
      width: parseLength(frame.attr(OdfNs.svg, 'width')),
      height: parseLength(frame.attr(OdfNs.svg, 'height')),
      description: frame.child(OdfNs.svg, 'desc')?.innerText ??
          frame.child(OdfNs.svg, 'title')?.innerText,
    );
  }

  OdfImageData? imageData(XmlElement frame) {
    final img = frame.child(OdfNs.draw, 'image');
    if (img == null) return null;
    List<int>? bytes;
    String? mediaType;
    final href = img.attr(OdfNs.xlink, 'href');
    if (href != null) {
      final path = href.startsWith('./') ? href.substring(2) : href;
      bytes = files.file(path);
      mediaType = files.mediaType(path);
    } else {
      final binary = img.child(OdfNs.office, 'binary-data')?.innerText;
      if (binary != null) {
        bytes = base64.decode(binary.replaceAll(RegExp(r'\s'), ''));
      }
    }
    if (bytes == null) return null;
    final mime = OdfImageData.detectMimeType(bytes) ??
        (mediaType != null && mediaType.isNotEmpty
            ? mediaType
            : 'application/octet-stream');
    return OdfImageData(bytes, mimeType: mime);
  }
}

/// Junta trechos de texto vizinhos com o mesmo estilo e link.
class _InlineCollector {
  final _items = <OdfInline>[];
  final _buffer = StringBuffer();
  OdfTextStyle? _style;
  String? _link;

  void add(String text, TextProps props, String? link) {
    if (text.isEmpty) return;
    final style = props.toStyle();
    if (_buffer.isNotEmpty && (style != _style || link != _link)) _flush();
    _style = style;
    _link = link;
    _buffer.write(text);
  }

  void field(OdfInline inline) {
    _flush();
    _items.add(inline);
  }

  void _flush() {
    if (_buffer.isEmpty) return;
    final text = _buffer.toString();
    _items.add(_link == null
        ? OdfSpan(text, style: _style!)
        : OdfLink(text, _link!, style: _style!));
    _buffer.clear();
  }

  List<OdfInline> finish() {
    _flush();
    return _items;
  }
}
