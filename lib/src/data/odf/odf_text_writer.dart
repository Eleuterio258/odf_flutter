import '../../domain/entities/odf_color.dart';
import '../../domain/entities/odf_rich_text.dart';
import '../../domain/exceptions/odf_exception.dart';
import 'odf_style_writer.dart';
import 'odf_xml.dart';

/// Serializa blocos de texto ODF (`text:p`, `text:h`, `text:list`, `table:table`...).
class OdfTextWriter {
  OdfTextWriter(
    this.w,
    this.styles,
    this.images, {
    required this.maxWidth,
    this.defaultParagraphStyle = 'Standard',
    this.headingStyles = true,
  });

  final OdfXmlWriter w;
  final OdfStyleRegistry styles;
  final OdfImageStore images;

  /// Largura útil (cm) para tabelas e imagens.
  final double maxWidth;

  /// Estilo comum dos parágrafos (`Standard` no ODT; nulo no ODP).
  final String? defaultParagraphStyle;

  /// Usa os estilos comuns `Heading_20_N` (ODT).
  final bool headingStyles;

  bool _pendingBreak = false;
  int _tables = 0;
  int _frames = 0;
  int _footnotes = 0;
  int _endnotes = 0;

  void blocks(List<OdfBlock> blocks, {String? paragraphStyle}) {
    for (final block in blocks) {
      this.block(block, paragraphStyle: paragraphStyle);
    }
    if (_pendingBreak) {
      w.el('text:p', {
        'text:style-name':
            _paragraphStyle(OdfParagraphStyle.normal, defaultParagraphStyle)
      });
    }
  }

  void block(OdfBlock block, {String? paragraphStyle}) {
    switch (block) {
      case OdfParagraph(:final inlines, :final style):
        w.el(
            'text:p',
            {
              'text:style-name': _paragraphStyle(
                  style, paragraphStyle ?? defaultParagraphStyle)
            },
            () => inline(inlines));
      case OdfHeading(:final inlines, :final style, :final level):
        final parent =
            headingStyles ? 'Heading_20_$level' : defaultParagraphStyle;
        w.el(
            'text:h',
            {
              'text:style-name': _paragraphStyle(style, parent),
              'text:outline-level': '$level',
            },
            () => inline(inlines));
      case OdfList():
        _list(block);
      case OdfTable():
        _table(block);
      case OdfImage():
        _image(block);
      case OdfPageBreak():
        // Quebras seguidas geram páginas em branco.
        if (_pendingBreak) {
          w.el('text:p', {
            'text:style-name':
                _paragraphStyle(OdfParagraphStyle.normal, defaultParagraphStyle)
          });
        }
        _pendingBreak = true;
    }
  }

  String? _paragraphStyle(OdfParagraphStyle style, String? parent) {
    final breakBefore = _pendingBreak;
    _pendingBreak = false;
    if (style.isNormal && !breakBefore) return parent;
    return styles.paragraphStyle(style,
        parent: parent, breakBefore: breakBefore);
  }

  // ------------------------------------------------------------- em linha

  void inline(List<OdfInline> inlines) {
    for (final item in inlines) {
      switch (item) {
        case OdfSpan(:final text, :final style):
          _styled(style, () => _text(text));
        case OdfLink(:final text, :final url, :final style):
          w.el('text:a', {'xlink:type': 'simple', 'xlink:href': url},
              () => _styled(style, () => _text(text)));
        case OdfLineBreak():
          w.el('text:line-break');
        case OdfTab():
          w.el('text:tab');
        case OdfPageNumber(:final style):
          _styled(
              style,
              () => w.el('text:page-number', {'text:select-page': 'current'},
                  () => w.text('1')));
        case OdfPageCount(:final style):
          _styled(style, () => w.el('text:page-count', {}, () => w.text('1')));
        case OdfNote():
          _note(item);
      }
    }
  }

  void _note(OdfNote note) {
    final number = note.endnote ? ++_endnotes : ++_footnotes;
    final kind = note.endnote ? 'endnote' : 'footnote';
    w.el('text:note', {'text:id': '${kind}_$number', 'text:note-class': kind},
        () {
      w.el('text:note-citation', {'text:label': note.citation},
          () => w.text(note.citation ?? '$number'));
      w.el('text:note-body', {}, () {
        if (note.body.any((b) => b is OdfTable || b is OdfPageBreak)) {
          throw const OdfException(
              'Notas aceitam apenas parágrafos, títulos, listas e imagens.');
        }
        blocks(note.body,
            paragraphStyle:
                headingStyles ? (note.endnote ? 'Endnote' : 'Footnote') : null);
      });
    });
  }

  void _styled(OdfTextStyle style, void Function() body) {
    if (style.isPlain) {
      body();
    } else {
      w.el('text:span', {'text:style-name': styles.textStyle(style)}, body);
    }
  }

  /// Converte `\n`, `\t` e sequências de espaços para os elementos ODF,
  /// pois o ODF colapsa espaços em branco do XML.
  void _text(String text) {
    final buffer = StringBuffer();
    void flush() {
      w.text(buffer.toString());
      buffer.clear();
    }

    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c == '\n') {
        flush();
        w.el('text:line-break');
        i++;
      } else if (c == '\t') {
        flush();
        w.el('text:tab');
        i++;
      } else if (c == '\r') {
        i++;
      } else if (c == ' ') {
        var j = i;
        while (j < text.length && text[j] == ' ') {
          j++;
        }
        final atStart = i == 0 || text[i - 1] == '\n' || text[i - 1] == '\t';
        var count = j - i;
        if (!atStart) {
          buffer.write(' ');
          count--;
        }
        if (count > 0) {
          flush();
          w.el('text:s', {'text:c': count > 1 ? '$count' : null});
        }
        i = j;
      } else {
        buffer.write(c);
        i++;
      }
    }
    flush();
  }

  // ---------------------------------------------------------------- listas

  void _list(OdfList list) {
    w.el('text:list',
        {'text:style-name': styles.listStyle(ordered: list.ordered)}, () {
      for (final item in list.items) {
        w.el('text:list-item', {}, () {
          for (final block in item.blocks) {
            if (block is OdfTable) {
              throw const OdfException(
                  'Tabelas não podem ficar dentro de itens de lista.');
            }
            this.block(block);
          }
        });
      }
    });
  }

  // --------------------------------------------------------------- tabelas

  void _table(OdfTable table) {
    _tables++;
    final grid = OdfTableGrid.layout([
      for (final row in table.rows)
        [for (final c in row.cells) (c.colSpan, c.rowSpan)],
    ]);
    final columns = grid.columnCount == 0 ? 1 : grid.columnCount;
    final widths = List<double>.generate(columns, (i) {
      final given = table.columnWidths;
      return given != null && i < given.length ? given[i] : maxWidth / columns;
    });
    final total = widths.fold(0.0, (a, b) => a + b);
    final breakBefore = _pendingBreak;
    _pendingBreak = false;

    final tableStyle = styles.register('Tab', (total, breakBefore), (w, name) {
      w.el('style:style', {'style:name': name, 'style:family': 'table'}, () {
        w.el('style:table-properties', {
          'style:width': cm(total),
          'table:align': 'left',
          'fo:break-before': breakBefore ? 'page' : null,
        });
      });
    });

    w.el('table:table', {
      'table:name': table.name ?? 'Tabela$_tables',
      'table:style-name': tableStyle
    }, () {
      for (final width in widths) {
        final columnStyle = styles.register('co', width, (w, name) {
          w.el(
              'style:style',
              {'style:name': name, 'style:family': 'table-column'},
              () => w.el('style:table-column-properties',
                  {'style:column-width': cm(width)}));
        });
        w.el('table:table-column', {'table:style-name': columnStyle});
      }

      void row(int r) {
        final isHeader = r < table.headerRows;
        w.el('table:table-row', {}, () {
          for (final slot in grid.slots[r]) {
            if (slot == OdfTableGrid.covered) {
              w.el('table:covered-table-cell');
              continue;
            }
            final cell = slot == null ? null : table.rows[r].cells[slot];
            final rowSpan = slot == null ? 1 : grid.rowSpans[r][slot];
            w.el('table:table-cell', {
              'table:style-name': _cellStyle(cell?.backgroundColor),
              'office:value-type': 'string',
              'table:number-columns-spanned':
                  cell != null && cell.colSpan > 1 ? '${cell.colSpan}' : null,
              'table:number-rows-spanned': rowSpan > 1 ? '$rowSpan' : null,
            }, () {
              final style = headingStyles
                  ? (isHeader ? 'Table_20_Heading' : 'Table_20_Contents')
                  : null;
              if (cell == null || cell.blocks.isEmpty) {
                w.el('text:p', {'text:style-name': style});
              } else {
                blocks(cell.blocks, paragraphStyle: style);
              }
            });
          }
        });
      }

      if (table.headerRows > 0) {
        w.el('table:table-header-rows', {}, () {
          for (var r = 0; r < table.headerRows && r < table.rows.length; r++) {
            row(r);
          }
        });
      }
      for (var r = table.headerRows; r < table.rows.length; r++) {
        row(r);
      }
    });
  }

  String _cellStyle(OdfColor? background) =>
      styles.register('ce', background ?? 'none', (w, name) {
        w.el('style:style', {'style:name': name, 'style:family': 'table-cell'},
            () {
          w.el('style:table-cell-properties', {
            'fo:padding': '0.1cm',
            'fo:border': '0.5pt solid #000000',
            'fo:background-color': background?.toHex(),
          });
        });
      });

  // --------------------------------------------------------------- imagens

  void _image(OdfImage image) {
    final (width, height) =
        imageSize(image.data, image.width, image.height, maxWidth);
    final style = OdfParagraphStyle(align: image.align ?? OdfTextAlign.center);
    w.el('text:p',
        {'text:style-name': _paragraphStyle(style, defaultParagraphStyle)}, () {
      writeImageFrame(image, width, height);
    });
  }

  void writeImageFrame(OdfImage image, double width, double height) {
    _frames++;
    final frameStyle = styles.register('fr', 'as-char', (w, name) {
      w.el('style:style', {'style:name': name, 'style:family': 'graphic'}, () {
        w.el('style:graphic-properties', {
          'style:vertical-pos': 'top',
          'style:vertical-rel': 'baseline',
          'fo:border': 'none',
        });
      });
    });
    w.el('draw:frame', {
      'draw:style-name': frameStyle,
      'draw:name': 'Imagem$_frames',
      'text:anchor-type': 'as-char',
      'svg:width': cm(width),
      'svg:height': cm(height),
      'draw:z-index': '0',
    }, () {
      w.el('draw:image', {
        'xlink:href': images.add(image.data),
        'xlink:type': 'simple',
        'xlink:show': 'embed',
        'xlink:actuate': 'onLoad',
      });
      if (image.description != null) {
        w.el('svg:desc', {}, () => w.text(image.description!));
      }
    });
  }
}
