import 'dart:convert';

import '../../domain/entities/odf_color.dart';
import '../../domain/entities/odf_metadata.dart';
import '../../domain/entities/odf_presentation.dart';
import '../../domain/entities/odf_rich_text.dart';
import '../../domain/entities/odf_types.dart';
import '../../domain/entities/odf_workbook.dart';
import '../datasources/odf_zip_data_source.dart';
import 'odf_formula.dart';
import 'odf_style_writer.dart';
import 'odf_text_writer.dart';
import 'odf_xml.dart';

/// Conjunto de arquivos de um pacote ODF pronto para ser compactado.
class OdfPackageFiles {
  OdfPackageFiles(this.type);

  final OdfDocumentType type;
  final entries = <OdfZipEntry>[];

  void xml(String path, String content) =>
      entries.add(OdfZipEntry(path, utf8.encode(content), 'text/xml'));

  void images(OdfImageStore store) {
    store.entries.forEach((path, image) =>
        entries.add(OdfZipEntry(path, image.bytes, image.mimeType)));
  }
}

String metaXml(OdfMetadata m) {
  final now = DateTime.now();
  final created = m.created ?? now;
  final modified = m.modified ?? created;
  String date(DateTime d) => d.toUtc().toIso8601String();
  final w = OdfXmlWriter();
  w.el('office:meta', {}, () {
    void element(String name, String? value) {
      if (value != null && value.isNotEmpty) {
        w.el(name, {}, () => w.text(value));
      }
    }

    element('meta:generator', odfGenerator);
    element('dc:title', m.title);
    element('dc:subject', m.subject);
    element('dc:description', m.description);
    for (final keyword in m.keywords) {
      element('meta:keyword', keyword);
    }
    element('meta:initial-creator', m.author);
    element('dc:creator', m.author);
    element('meta:creation-date', date(created));
    element('dc:date', date(modified));
    element('dc:language', m.language);
  });
  return odfDocument('office:document-meta', w.fragment());
}

Map<String, String?> _languageAttributes(String? language) {
  if (language == null) return const {};
  final parts = language.split(RegExp('[-_]'));
  return {
    'fo:language': parts.first,
    'fo:country': parts.length > 1 ? parts[1].toUpperCase() : null
  };
}

// ===========================================================================
// ODT
// ===========================================================================

class OdtWriter {
  OdfPackageFiles write(OdfRichTextDocument doc) {
    final images = OdfImageStore();
    final layout = doc.pageLayout;

    final contentStyles = OdfStyleRegistry();
    final body = OdfXmlWriter();
    OdfTextWriter(body, contentStyles, images, maxWidth: layout.contentWidth)
        .blocks(doc.blocks);

    final masterStyles = OdfStyleRegistry(prefix: 'M');
    final master = OdfXmlWriter();
    master.el('style:master-page',
        {'style:name': 'Standard', 'style:page-layout-name': 'pm1'}, () {
      for (final (name, blocks) in [
        ('style:header', doc.header),
        ('style:footer', doc.footer)
      ]) {
        if (blocks.isEmpty) continue;
        master.el(name, {}, () {
          OdfTextWriter(master, masterStyles, images,
                  maxWidth: layout.contentWidth)
              .blocks(blocks);
        });
      }
    });

    final content =
        '<office:automatic-styles>${contentStyles.fragment()}</office:automatic-styles>'
        '<office:body><office:text>${body.fragment()}</office:text></office:body>';

    return OdfPackageFiles(OdfDocumentType.text)
      ..xml('content.xml', odfDocument('office:document-content', content))
      ..xml('styles.xml', _styles(doc, masterStyles, master.fragment()))
      ..xml('meta.xml', metaXml(doc.metadata))
      ..images(images);
  }

  String _styles(OdfRichTextDocument doc, OdfStyleRegistry masterStyles,
      String masterPage) {
    final layout = doc.pageLayout;
    final w = OdfXmlWriter();
    w.el('office:styles', {}, () {
      w.el('style:default-style', {'style:family': 'paragraph'}, () {
        w.el('style:paragraph-properties', {'style:writing-mode': 'page'});
        w.el('style:text-properties', {
          'fo:font-size': '12pt',
          'fo:font-family': "'Liberation Serif'",
          ..._languageAttributes(doc.metadata.language),
        });
      });
      w.el('style:style', {
        'style:name': 'Standard',
        'style:family': 'paragraph',
        'style:class': 'text'
      });
      w.el('style:style', {
        'style:name': 'Heading',
        'style:family': 'paragraph',
        'style:parent-style-name': 'Standard',
        'style:class': 'text',
      }, () {
        w.el('style:paragraph-properties', {
          'fo:margin-top': '0.423cm',
          'fo:margin-bottom': '0.212cm',
          'fo:keep-with-next': 'always'
        });
        w.el('style:text-properties',
            {'fo:font-family': "'Liberation Sans'", 'fo:font-size': '14pt'});
      });
      const sizes = [24, 20, 16, 14, 12, 12];
      for (var level = 1; level <= 6; level++) {
        w.el('style:style', {
          'style:name': 'Heading_20_$level',
          'style:display-name': 'Heading $level',
          'style:family': 'paragraph',
          'style:parent-style-name': 'Heading',
          'style:default-outline-level': '$level',
          'style:class': 'text',
        }, () {
          w.el('style:text-properties', {
            'fo:font-size': '${sizes[level - 1]}pt',
            'fo:font-weight': 'bold',
            'fo:font-style': level >= 5 ? 'italic' : null,
          });
        });
      }
      w.el('style:style', {
        'style:name': 'Table_20_Contents',
        'style:display-name': 'Table Contents',
        'style:family': 'paragraph',
        'style:parent-style-name': 'Standard',
        'style:class': 'extra',
      });
      w.el('style:style', {
        'style:name': 'Table_20_Heading',
        'style:display-name': 'Table Heading',
        'style:family': 'paragraph',
        'style:parent-style-name': 'Table_20_Contents',
        'style:class': 'extra',
      }, () {
        w.el('style:paragraph-properties', {'fo:text-align': 'center'});
        w.el('style:text-properties', {'fo:font-weight': 'bold'});
      });
      for (final (name, display) in [
        ('Footnote', 'Footnote'),
        ('Endnote', 'Endnote')
      ]) {
        w.el('style:style', {
          'style:name': name,
          'style:display-name': display,
          'style:family': 'paragraph',
          'style:parent-style-name': 'Standard',
          'style:class': 'extra',
        }, () {
          w.el('style:paragraph-properties',
              {'fo:margin-left': '0.6cm', 'fo:text-indent': '-0.6cm'});
          w.el('style:text-properties', {'fo:font-size': '10pt'});
        });
      }
      w.el('text:outline-style', {'style:name': 'Outline'}, () {
        for (var level = 1; level <= 10; level++) {
          w.el('text:outline-level-style',
              {'text:level': '$level', 'style:num-format': ''});
        }
      });
    });
    w.el('office:automatic-styles', {}, () {
      w.el('style:page-layout', {'style:name': 'pm1'}, () {
        w.el('style:page-layout-properties', {
          'fo:page-width': cm(layout.width),
          'fo:page-height': cm(layout.height),
          'style:print-orientation':
              layout.isLandscape ? 'landscape' : 'portrait',
          'fo:margin-top': cm(layout.marginTop),
          'fo:margin-bottom': cm(layout.marginBottom),
          'fo:margin-left': cm(layout.marginLeft),
          'fo:margin-right': cm(layout.marginRight),
        });
        if (doc.header.isNotEmpty) {
          w.el(
              'style:header-style',
              {},
              () => w.el('style:header-footer-properties',
                  {'fo:min-height': '0cm', 'fo:margin-bottom': '0.5cm'}));
        }
        if (doc.footer.isNotEmpty) {
          w.el(
              'style:footer-style',
              {},
              () => w.el('style:header-footer-properties',
                  {'fo:min-height': '0cm', 'fo:margin-top': '0.5cm'}));
        }
      });
    });
    final inner = w.fragment().replaceFirst(
          '</office:automatic-styles>',
          '${masterStyles.fragment()}</office:automatic-styles>',
        );
    return odfDocument('office:document-styles',
        '$inner<office:master-styles>$masterPage</office:master-styles>');
  }
}

// ===========================================================================
// ODS
// ===========================================================================

class OdsWriter {
  OdfPackageFiles write(OdfWorkbook workbook) {
    final styles = OdfStyleRegistry();
    final body = OdfXmlWriter();
    final sheets =
        workbook.sheets.isEmpty ? [OdfWorksheet('Planilha1')] : workbook.sheets;

    final names = <String>{};
    for (final sheet in sheets) {
      if (!names.add(sheet.name)) {
        throw ArgumentError('Nome de aba duplicado: ${sheet.name}');
      }
      _sheet(body, styles, sheet);
    }

    final content =
        '<office:automatic-styles>${styles.fragment()}</office:automatic-styles>'
        '<office:body><office:spreadsheet>${body.fragment()}</office:spreadsheet></office:body>';

    final defaults = OdfXmlWriter();
    defaults.el('office:styles', {}, () {
      defaults.el('style:default-style', {'style:family': 'table-cell'}, () {
        defaults.el('style:text-properties', {
          'fo:font-family': "'Liberation Sans'",
          'fo:font-size': '10pt',
          ..._languageAttributes(workbook.metadata.language),
        });
      });
      defaults.el('style:style',
          {'style:name': 'Default', 'style:family': 'table-cell'});
    });

    return OdfPackageFiles(OdfDocumentType.spreadsheet)
      ..xml('content.xml', odfDocument('office:document-content', content))
      ..xml('styles.xml',
          odfDocument('office:document-styles', defaults.fragment()))
      ..xml('meta.xml', metaXml(workbook.metadata));
  }

  void _sheet(OdfXmlWriter w, OdfStyleRegistry styles, OdfWorksheet sheet) {
    // cells[i] é a coluna i. Posições cobertas por uma mesclagem são gravadas
    // como covered-table-cell, e o span da origem é limitado ao fim da aba.
    final covered = <(int, int)>{};
    final rowSpans = <(int, int), int>{};
    var usedColumns = 0;
    for (var r = 0; r < sheet.rows.length; r++) {
      final cells = sheet.rows[r].cells;
      for (var c = 0; c < cells.length; c++) {
        if (covered.contains((r, c))) continue;
        final cell = cells[c];
        final rowSpan = cell.rowSpan.clamp(1, sheet.rows.length - r);
        if (rowSpan > 1) rowSpans[(r, c)] = rowSpan;
        for (var dr = 0; dr < rowSpan; dr++) {
          for (var dc = 0; dc < cell.colSpan; dc++) {
            if (dr != 0 || dc != 0) covered.add((r + dr, c + dc));
          }
        }
        if (c + cell.colSpan > usedColumns) usedColumns = c + cell.colSpan;
      }
      if (cells.length > usedColumns) usedColumns = cells.length;
    }
    final widestColumn =
        sheet.columnWidths.keys.fold(-1, (m, k) => k > m ? k : m);
    final columns =
        [usedColumns, widestColumn + 1, 1].reduce((a, b) => a > b ? a : b);

    final tableStyle = styles.register('ta', 'default', (w, name) {
      w.el(
          'style:style',
          {
            'style:name': name,
            'style:family': 'table',
            'style:master-page-name': 'Default'
          },
          () => w.el('style:table-properties',
              {'table:display': 'true', 'style:writing-mode': 'lr-tb'}));
    });

    w.el('table:table',
        {'table:name': sheet.name, 'table:style-name': tableStyle}, () {
      // Colunas consecutivas com a mesma largura são agrupadas.
      var c = 0;
      while (c < columns) {
        final width = sheet.columnWidths[c];
        var repeat = 1;
        while (
            c + repeat < columns && sheet.columnWidths[c + repeat] == width) {
          repeat++;
        }
        w.el('table:table-column', {
          'table:style-name':
              width == null ? null : _columnStyle(styles, width),
          'table:number-columns-repeated': repeat > 1 ? '$repeat' : null,
          'table:default-cell-style-name': 'Default',
        });
        c += repeat;
      }

      if (sheet.rows.isEmpty) {
        w.el('table:table-row', {}, () => w.el('table:table-cell'));
      }
      bool emptyRow(int r) =>
          sheet.rows[r].height == null &&
          sheet.rows[r].cells.every((c) => c.isEmpty && c.style == null) &&
          !covered.any((p) => p.$1 == r);
      for (var r = 0; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final height = row.height;
        // Linhas vazias seguidas viram uma só, repetida (toda linha precisa de uma célula).
        if (emptyRow(r)) {
          var repeat = 1;
          while (r + repeat < sheet.rows.length && emptyRow(r + repeat)) {
            repeat++;
          }
          w.el(
              'table:table-row',
              {'table:number-rows-repeated': repeat > 1 ? '$repeat' : null},
              () => w.el('table:table-cell', {
                    'table:number-columns-repeated':
                        columns > 1 ? '$columns' : null
                  }));
          r += repeat - 1;
          continue;
        }
        w.el('table:table-row', {
          'table:style-name': height == null
              ? null
              : styles.register('ro', height, (w, name) {
                  w.el('style:style',
                      {'style:name': name, 'style:family': 'table-row'}, () {
                    w.el('style:table-row-properties', {
                      'style:row-height': cm(height),
                      'style:use-optimal-row-height': 'false'
                    });
                  });
                }),
        }, () {
          final last = [
            row.cells.length,
            ...covered.where((p) => p.$1 == r).map((p) => p.$2 + 1)
          ].fold(0, (m, v) => v > m ? v : m);
          var c = 0;
          while (c < last) {
            final cell = c < row.cells.length ? row.cells[c] : null;
            final isCovered = covered.contains((r, c));
            bool blank(int col) =>
                !covered.contains((r, col)) &&
                (col >= row.cells.length ||
                    (row.cells[col].isEmpty && row.cells[col].style == null));
            if (!isCovered && blank(c)) {
              var repeat = 1;
              while (c + repeat < last && blank(c + repeat)) {
                repeat++;
              }
              w.el('table:table-cell', {
                'table:number-columns-repeated': repeat > 1 ? '$repeat' : null
              });
              c += repeat;
              continue;
            }
            if (isCovered &&
                (cell == null || cell.isEmpty && cell.style == null)) {
              w.el('table:covered-table-cell');
            } else {
              _cell(w, styles, cell!, isCovered ? 1 : rowSpans[(r, c)] ?? 1,
                  covered: isCovered);
            }
            c++;
          }
        });
      }
    });
  }

  String _columnStyle(OdfStyleRegistry styles, double width) =>
      styles.register('co', width, (w, name) {
        w.el(
            'style:style', {'style:name': name, 'style:family': 'table-column'},
            () {
          w.el('style:table-column-properties',
              {'fo:break-before': 'auto', 'style:column-width': cm(width)});
        });
      });

  /// Com [covered], grava o conteúdo oculto de uma posição coberta por mesclagem.
  void _cell(OdfXmlWriter w, OdfStyleRegistry styles, OdfCell cell, int rowSpan,
      {bool covered = false}) {
    final value = cell.value;
    final format = cell.style?.numberFormat ?? defaultFormatFor(value);
    final style = (cell.style ?? const OdfCellStyle()).withNumberFormat(format);

    final attributes = <String, String?>{
      'table:style-name': style.isDefault ? null : _cellStyle(styles, style),
      'table:number-columns-spanned':
          !covered && cell.colSpan > 1 ? '${cell.colSpan}' : null,
      'table:number-rows-spanned': !covered && rowSpan > 1 ? '$rowSpan' : null,
      if (value is OdfFormula)
        'table:formula': OdfFormulaConverter.toOpenFormula(value.expression),
      ..._valueAttributes(
          value is OdfFormula ? value.result ?? const OdfEmptyValue() : value),
    };

    w.el(covered ? 'table:covered-table-cell' : 'table:table-cell', attributes,
        () {
      if (cell.note != null) {
        w.el('office:annotation', {}, () {
          for (final line in cell.note!.split('\n')) {
            w.el('text:p', {}, () => w.text(line));
          }
        });
      }
      final text = displayText(value, format);
      if (text.isNotEmpty) {
        for (final line in text.split('\n')) {
          w.el('text:p', {}, () => w.text(line));
        }
      }
    });
  }

  Map<String, String?> _valueAttributes(OdfCellValue value) => switch (value) {
        OdfEmptyValue() || OdfFormula() => const {},
        OdfStringValue() => const {'office:value-type': 'string'},
        OdfNumberValue(:final value) => {
            'office:value-type': 'float',
            'office:value': fmtNum(value)
          },
        OdfPercentageValue(:final value) => {
            'office:value-type': 'percentage',
            'office:value': fmtNum(value)
          },
        OdfCurrencyValue(:final value, :final currency) => {
            'office:value-type': 'currency',
            'office:currency': currency,
            'office:value': fmtNum(value),
          },
        OdfBooleanValue(:final value) => {
            'office:value-type': 'boolean',
            'office:boolean-value': '$value'
          },
        OdfDateValue(:final value, :final includeTime) => {
            'office:value-type': 'date',
            'office:date-value': includeTime
                ? DateTime(value.year, value.month, value.day, value.hour,
                        value.minute, value.second)
                    .toIso8601String()
                    .replaceFirst(RegExp(r'\.\d+$'), '')
                : value.toIso8601String().substring(0, 10),
          },
        OdfTimeValue(:final value) => {
            'office:value-type': 'time',
            'office:time-value':
                'PT${value.inHours}H${value.inMinutes % 60}M${value.inSeconds % 60}S',
          },
      };

  String _cellStyle(OdfStyleRegistry styles, OdfCellStyle style) {
    final dataStyle = style.numberFormat == null
        ? null
        : styles.dataStyle(style.numberFormat!);
    return styles.register('ce', style, (w, name) {
      w.el('style:style', {
        'style:name': name,
        'style:family': 'table-cell',
        'style:parent-style-name': 'Default',
        'style:data-style-name': dataStyle,
      }, () {
        w.el('style:table-cell-properties', {
          'fo:background-color': style.backgroundColor?.toHex(),
          'fo:border': style.border ? '0.06pt solid #000000' : null,
          'style:vertical-align': style.verticalAlign?.name,
          'fo:wrap-option': style.wrap ? 'wrap' : null,
          'style:text-align-source': style.align == null ? null : 'fix',
        });
        if (style.align != null) {
          w.el('style:paragraph-properties',
              {'fo:text-align': alignValue(style.align!)});
        }
        writeTextProperties(
          w,
          OdfTextStyle(
            bold: style.bold,
            italic: style.italic,
            underline: style.underline,
            fontSize: style.fontSize,
            color: style.color,
          ),
        );
      });
    });
  }
}

// ===========================================================================
// ODP
// ===========================================================================

class OdpWriter {
  static const _margin = 1.2;

  OdfPackageFiles write(OdfPresentation presentation) {
    final styles = OdfStyleRegistry();
    final images = OdfImageStore();
    final body = OdfXmlWriter();
    final size = presentation.size;

    for (var i = 0; i < presentation.slides.length; i++) {
      _slide(body, styles, images, presentation.slides[i], i + 1, size);
    }

    final content =
        '<office:automatic-styles>${styles.fragment()}</office:automatic-styles>'
        '<office:body><office:presentation>${body.fragment()}</office:presentation></office:body>';

    final w = OdfXmlWriter();
    w.el('office:styles', {}, () {
      w.el('style:default-style', {'style:family': 'graphic'}, () {
        w.el('style:graphic-properties',
            {'svg:stroke-color': '#3465a4', 'draw:fill-color': '#729fcf'});
        w.el('style:text-properties', {
          'fo:font-family': "'Liberation Sans'",
          'fo:font-size': '20pt',
          ..._languageAttributes(presentation.metadata.language),
        });
      });
    });
    w.el('office:automatic-styles', {}, () {
      w.el('style:page-layout', {'style:name': 'PM1'}, () {
        w.el('style:page-layout-properties', {
          'fo:margin-top': '0cm',
          'fo:margin-bottom': '0cm',
          'fo:margin-left': '0cm',
          'fo:margin-right': '0cm',
          'fo:page-width': cm(size.width),
          'fo:page-height': cm(size.height),
          'style:print-orientation':
              size.width >= size.height ? 'landscape' : 'portrait',
        });
      });
      w.el(
          'style:style', {'style:name': 'Mdp1', 'style:family': 'drawing-page'},
          () {
        w.el('style:drawing-page-properties', {
          'draw:background-size': 'border',
          'draw:fill': 'solid',
          'draw:fill-color': '#ffffff'
        });
      });
    });
    w.el('office:master-styles', {}, () {
      w.el('style:master-page', {
        'style:name': 'Default',
        'style:page-layout-name': 'PM1',
        'draw:style-name': 'Mdp1'
      });
    });

    return OdfPackageFiles(OdfDocumentType.presentation)
      ..xml('content.xml', odfDocument('office:document-content', content))
      ..xml('styles.xml', odfDocument('office:document-styles', w.fragment()))
      ..xml('meta.xml', metaXml(presentation.metadata))
      ..images(images);
  }

  void _slide(OdfXmlWriter w, OdfStyleRegistry styles, OdfImageStore images,
      OdfSlide slide, int number, OdfSlideSize size) {
    final background = slide.background;
    final pageStyle = background == null
        ? null
        : styles.register('dp', background, (w, name) {
            w.el('style:style',
                {'style:name': name, 'style:family': 'drawing-page'}, () {
              w.el('style:drawing-page-properties', {
                'draw:fill': 'solid',
                'draw:fill-color': background.toHex(),
                'draw:background-size': 'border',
                'presentation:background-visible': 'true',
                'presentation:background-objects-visible': 'true',
              });
            });
          });

    final contentWidth = size.width - 2 * _margin;
    final top = slide.title == null ? _margin : 3.6;
    final area = OdfFrame(_margin, top, contentWidth, size.height - top - 1.0);
    final frames = _autoLayout(slide.elements, area);

    w.el('draw:page', {
      'draw:name': 'page$number',
      'draw:master-page-name': 'Default',
      'draw:style-name': pageStyle,
    }, () {
      if (slide.title != null) {
        final titleStyle = styles.register('pr', 'title', (w, name) {
          w.el('style:style',
              {'style:name': name, 'style:family': 'presentation'}, () {
            w.el('style:graphic-properties', {
              'draw:fill': 'none',
              'draw:stroke': 'none',
              'draw:textarea-vertical-align': 'middle',
              'draw:auto-grow-height': 'false',
            });
            w.el('style:paragraph-properties', {'fo:text-align': 'center'});
            w.el('style:text-properties',
                {'fo:font-size': '36pt', 'fo:font-weight': 'bold'});
          });
        });
        _frame(w, OdfFrame(_margin, 0.6, contentWidth, 2.6), {
          'presentation:style-name': titleStyle,
          'presentation:class': 'title',
        }, () {
          w.el('draw:text-box', {}, () {
            for (final line in slide.title!.split('\n')) {
              w.el('text:p', {}, () {
                if (slide.titleStyle.isPlain) {
                  w.text(line);
                } else {
                  w.el(
                      'text:span',
                      {'text:style-name': styles.textStyle(slide.titleStyle)},
                      () => w.text(line));
                }
              });
            }
          });
        });
      }

      for (var i = 0; i < slide.elements.length; i++) {
        final element = slide.elements[i];
        final frame = frames[i];
        switch (element) {
          case OdfTextBox(:final blocks):
            _frame(w, frame, {
              'draw:style-name':
                  _graphicStyle(styles, null, null, textBox: true)
            }, () {
              w.el('draw:text-box', {}, () {
                OdfTextWriter(w, styles, images,
                        maxWidth: frame.width,
                        defaultParagraphStyle: null,
                        headingStyles: false)
                    .blocks(blocks);
              });
            });
          case OdfSlideImage(:final image):
            _frame(w, frame,
                {'draw:style-name': _graphicStyle(styles, null, null)}, () {
              w.el('draw:image', {
                'xlink:href': images.add(image),
                'xlink:type': 'simple',
                'xlink:show': 'embed',
                'xlink:actuate': 'onLoad',
              });
            });
          case OdfShape(
              :final kind,
              :final fill,
              :final stroke,
              :final text,
              :final textStyle
            ):
            w.el(kind == OdfShapeKind.ellipse ? 'draw:ellipse' : 'draw:rect', {
              'draw:style-name': _graphicStyle(styles, fill, stroke),
              'draw:layer': 'layout',
              ..._geometry(frame),
            }, () {
              if (text == null) return;
              for (final line in text.split('\n')) {
                w.el('text:p', {'text:style-name': _centered(styles)}, () {
                  if (textStyle.isPlain) {
                    w.text(line);
                  } else {
                    w.el(
                        'text:span',
                        {'text:style-name': styles.textStyle(textStyle)},
                        () => w.text(line));
                  }
                });
              }
            });
        }
      }

      if (slide.notes != null) {
        w.el('presentation:notes', {}, () {
          w.el('draw:page-thumbnail', {
            'draw:layer': 'layout',
            'svg:width': '14cm',
            'svg:height': cm(14 * size.height / size.width),
            'svg:x': '3.5cm',
            'svg:y': '2cm',
            'draw:page-number': '$number',
            'presentation:class': 'page',
          });
          w.el('draw:frame', {
            'draw:layer': 'layout',
            'svg:width': '17cm',
            'svg:height': '12cm',
            'svg:x': '2cm',
            'svg:y': '13cm',
            'presentation:class': 'notes',
          }, () {
            w.el('draw:text-box', {}, () {
              for (final line in slide.notes!.split('\n')) {
                w.el('text:p', {}, () => w.text(line));
              }
            });
          });
        });
      }
    });
  }

  /// Posiciona elementos sem moldura: um ocupa a área toda; dois ficam lado a
  /// lado; três ou mais são empilhados. Imagens mantêm a proporção.
  List<OdfFrame> _autoLayout(List<OdfSlideElement> elements, OdfFrame area) {
    final automatic = elements.where((e) => e.frame == null).length;
    const gap = 0.6;
    var index = 0;
    return [
      for (final element in elements)
        if (element.frame != null)
          element.frame!
        else
          () {
            final i = index++;
            final OdfFrame cell;
            if (automatic == 2) {
              final width = (area.width - gap) / 2;
              cell = OdfFrame(
                  area.x + i * (width + gap), area.y, width, area.height);
            } else {
              final height = (area.height - gap * (automatic - 1)) / automatic;
              cell = OdfFrame(
                  area.x, area.y + i * (height + gap), area.width, height);
            }
            return element is OdfSlideImage ? _fit(element, cell) : cell;
          }(),
    ];
  }

  OdfFrame _fit(OdfSlideImage element, OdfFrame cell) {
    final pixels = element.image.pixelSize;
    if (pixels == null || pixels.$1 == 0 || pixels.$2 == 0) return cell;
    final ratio = pixels.$2 / pixels.$1;
    var width = cell.width;
    var height = width * ratio;
    if (height > cell.height) {
      height = cell.height;
      width = height / ratio;
    }
    return OdfFrame(cell.x + (cell.width - width) / 2,
        cell.y + (cell.height - height) / 2, width, height);
  }

  Map<String, String> _geometry(OdfFrame f) => {
        'svg:x': cm(f.x),
        'svg:y': cm(f.y),
        'svg:width': cm(f.width),
        'svg:height': cm(f.height)
      };

  void _frame(OdfXmlWriter w, OdfFrame frame, Map<String, String?> attributes,
          void Function() body) =>
      w.el('draw:frame',
          {...attributes, 'draw:layer': 'layout', ..._geometry(frame)}, body);

  String _graphicStyle(
      OdfStyleRegistry styles, OdfColor? fill, OdfColor? stroke,
      {bool textBox = false}) {
    return styles.register('gr', (fill, stroke, textBox), (w, name) {
      w.el('style:style', {'style:name': name, 'style:family': 'graphic'}, () {
        w.el('style:graphic-properties', {
          'draw:fill': fill == null ? 'none' : 'solid',
          'draw:fill-color': fill?.toHex(),
          'draw:stroke': stroke == null ? 'none' : 'solid',
          'svg:stroke-color': stroke?.toHex(),
          'draw:auto-grow-height': textBox ? 'false' : null,
          'draw:textarea-vertical-align': textBox ? 'top' : 'middle',
          'fo:min-height': textBox ? '0cm' : null,
        });
      });
    });
  }

  String _centered(OdfStyleRegistry styles) => styles
      .paragraphStyle(const OdfParagraphStyle(align: OdfTextAlign.center));
}
