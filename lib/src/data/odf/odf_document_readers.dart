import 'package:xml/xml.dart';

import '../../domain/entities/odf_color.dart';
import '../../domain/entities/odf_metadata.dart';
import '../../domain/entities/odf_package_entity.dart';
import '../../domain/entities/odf_presentation.dart';
import '../../domain/entities/odf_rich_text.dart';
import '../../domain/entities/odf_types.dart';
import '../../domain/entities/odf_workbook.dart';
import '../../domain/exceptions/odf_exception.dart';
import '../datasources/odf_zip_data_source.dart';
import 'odf_formula.dart';
import 'odf_style_reader.dart';
import 'odf_style_writer.dart' show defaultFormatFor;
import 'odf_text_reader.dart';
import 'odf_xml.dart';

/// Acesso aos XMLs e ao manifesto de um pacote aberto.
class OdfPackageXml {
  OdfPackageXml(this.package) {
    final manifest = xml('META-INF/manifest.xml');
    if (manifest != null) {
      for (final entry
          in manifest.rootElement.elementsOf(OdfNs.manifest, 'file-entry')) {
        final path = entry.attr(OdfNs.manifest, 'full-path');
        final type = entry.attr(OdfNs.manifest, 'media-type');
        if (path != null && type != null) _mediaTypes[path] = type;
      }
    }
  }

  final OdfPackageEntity package;
  final _mediaTypes = <String, String>{};
  final _cache = <String, XmlDocument?>{};

  XmlDocument? xml(String path) => _cache.putIfAbsent(path, () {
        if (!package.contains(path)) return null;
        try {
          return XmlDocument.parse(
              OdfZipDataSource.decodeUtf8(package.file(path), path));
        } on XmlException catch (e) {
          throw OdfException('XML inválido em $path: ${e.message}');
        }
      });

  XmlDocument content() =>
      xml('content.xml') ??
      (throw const OdfException('O pacote não contém content.xml.'));

  OdfStyleSheet styleSheet() => OdfStyleSheet([xml('styles.xml'), content()]);

  OdfFileLookup get lookup => (
        file: (path) => package.contains(path) ? package.file(path) : null,
        mediaType: (path) => _mediaTypes[path],
      );

  XmlElement body(String kind) {
    final body = content()
        .rootElement
        .child(OdfNs.office, 'body')
        ?.child(OdfNs.office, kind);
    if (body == null) {
      throw OdfException('content.xml não contém office:$kind.');
    }
    return body;
  }

  void expectType(OdfDocumentType type) {
    if (package.type != type) {
      throw OdfException('Esperado documento ${type.extension.toUpperCase()}, '
          'mas o pacote é ${package.type.extension.toUpperCase()}.');
    }
  }
}

OdfMetadata readMetadata(OdfPackageXml xml) {
  final meta = xml.xml('meta.xml')?.rootElement.child(OdfNs.office, 'meta');
  if (meta == null) return const OdfMetadata();
  String? text(String ns, String local) {
    final value = meta.child(ns, local)?.innerText.trim();
    return value == null || value.isEmpty ? null : value;
  }

  DateTime? date(String ns, String local) {
    final value = text(ns, local);
    return value == null ? null : DateTime.tryParse(value);
  }

  return OdfMetadata(
    title: text(OdfNs.dc, 'title'),
    subject: text(OdfNs.dc, 'subject'),
    description: text(OdfNs.dc, 'description'),
    author: text(OdfNs.meta, 'initial-creator') ?? text(OdfNs.dc, 'creator'),
    keywords: [
      for (final k in meta.elementsOf(OdfNs.meta, 'keyword')) k.innerText.trim()
    ],
    language: text(OdfNs.dc, 'language'),
    created: date(OdfNs.meta, 'creation-date'),
    modified: date(OdfNs.dc, 'date'),
    generator: text(OdfNs.meta, 'generator'),
  );
}

// ===========================================================================
// ODT
// ===========================================================================

class OdtReader {
  OdfRichTextDocument read(OdfPackageEntity package) {
    final xml = OdfPackageXml(package)..expectType(OdfDocumentType.text);
    final reader = OdfTextReader(xml.styleSheet(), xml.lookup);
    final blocks = reader.blocks(xml.body('text'));

    // Cabeçalho e rodapé usam apenas os estilos de styles.xml.
    final masterSheet = OdfStyleSheet([xml.xml('styles.xml')]);
    final master = masterSheet.masterPages
            .where((p) => p.attr(OdfNs.style, 'name') == 'Standard')
            .firstOrNull ??
        masterSheet.masterPages.firstOrNull;
    final masterReader = OdfTextReader(masterSheet, xml.lookup);
    List<OdfBlock> section(String local) {
      final e = master?.child(OdfNs.style, local);
      return e == null ? const [] : masterReader.blocks(e);
    }

    final props = masterSheet
        .pageLayoutProps(master?.attr(OdfNs.style, 'page-layout-name'));
    final defaults = OdfPageLayout.a4;
    double length(String local, double fallback) =>
        parseLength(props?.attr(OdfNs.fo, local)) ?? fallback;

    return OdfRichTextDocument(
      blocks: blocks,
      metadata: readMetadata(xml),
      header: section('header'),
      footer: section('footer'),
      pageLayout: OdfPageLayout(
        width: length('page-width', defaults.width),
        height: length('page-height', defaults.height),
        marginTop: length('margin-top', defaults.marginTop),
        marginBottom: length('margin-bottom', defaults.marginBottom),
        marginLeft: length('margin-left', defaults.marginLeft),
        marginRight: length('margin-right', defaults.marginRight),
      ),
    );
  }
}

// ===========================================================================
// ODS
// ===========================================================================

class OdsReader {
  /// O modelo guarda as linhas em lista; planilhas com dados além destes
  /// limites (ex.: na linha 16 milhões) são recusadas com [OdfException]
  /// em vez de esgotar a memória.
  OdsReader({this.maxRows = 1048576, this.maxColumns = 16384});

  final int maxRows;
  final int maxColumns;

  OdfWorkbook read(OdfPackageEntity package) {
    final xml = OdfPackageXml(package)..expectType(OdfDocumentType.spreadsheet);
    final styles = xml.styleSheet();
    final text = OdfTextReader(styles, xml.lookup);
    return OdfWorkbook(
      metadata: readMetadata(xml),
      sheets: [
        for (final table
            in xml.body('spreadsheet').elementsOf(OdfNs.table, 'table'))
          _sheet(table, styles, text),
      ],
    );
  }

  OdfWorksheet _sheet(
      XmlElement table, OdfStyleSheet styles, OdfTextReader text) {
    final columnStyles = <String?>[];
    final columnWidths = <int, double>{};

    void columns(XmlElement parent) {
      for (final c in parent.childElements) {
        if (c.isA(OdfNs.table, 'table-column')) {
          final repeat = _repeat(c, 'number-columns-repeated')
              .clamp(0, maxColumns - columnStyles.length);
          final width = styles.columnWidth(c.attr(OdfNs.table, 'style-name'));
          for (var i = 0; i < repeat; i++) {
            if (width != null) columnWidths[columnStyles.length] = width;
            columnStyles.add(c.attr(OdfNs.table, 'default-cell-style-name'));
          }
        } else if (c.isA(OdfNs.table, 'table-columns') ||
            c.isA(OdfNs.table, 'table-header-columns') ||
            c.isA(OdfNs.table, 'table-column-group')) {
          columns(c);
        }
      }
    }

    final rows = <OdfRow>[];
    var pendingEmptyRows = 0;

    void addRow(XmlElement r) {
      final cells = _cells(r, styles, text, columnStyles);
      final repeat = _repeat(r, 'number-rows-repeated');
      if (cells.isEmpty) {
        pendingEmptyRows += repeat;
        return;
      }
      if (rows.length + pendingEmptyRows + repeat > maxRows) {
        throw OdfException(
            'A aba "${table.attr(OdfNs.table, 'name')}" tem dados além da linha $maxRows; '
            'aumente OdsReader.maxRows para lê-la.');
      }
      for (var i = 0; i < pendingEmptyRows; i++) {
        rows.add(OdfRow());
      }
      pendingEmptyRows = 0;
      final height = styles.rowHeight(r.attr(OdfNs.table, 'style-name'));
      for (var i = 0; i < repeat; i++) {
        rows.add(
            OdfRow(i == 0 ? cells : [for (final c in cells) _copy(c)], height));
      }
    }

    void collectRows(XmlElement parent) {
      for (final r in parent.childElements) {
        if (r.isA(OdfNs.table, 'table-row')) {
          addRow(r);
        } else if (r.isA(OdfNs.table, 'table-header-rows') ||
            r.isA(OdfNs.table, 'table-rows') ||
            r.isA(OdfNs.table, 'table-row-group')) {
          collectRows(r);
        }
      }
    }

    columns(table);
    collectRows(table);

    final used =
        rows.fold(0, (m, r) => r.cells.length > m ? r.cells.length : m);
    columnWidths.removeWhere((index, _) => index >= used);
    return OdfWorksheet(table.attr(OdfNs.table, 'name') ?? 'Planilha',
        rows: rows, columnWidths: columnWidths);
  }

  List<OdfCell> _cells(XmlElement row, OdfStyleSheet styles, OdfTextReader text,
      List<String?> columnStyles) {
    final cells = <OdfCell>[];
    final pending = <(OdfCell, int)>[];
    var column = 0;
    for (final c in row.childElements) {
      // Posições cobertas por mesclagem também ocupam sua coluna no modelo,
      // para que cells[i] seja sempre a coluna i.
      if (!c.isA(OdfNs.table, 'covered-table-cell') &&
          !c.isA(OdfNs.table, 'table-cell')) {
        continue;
      }
      final repeat = _repeat(c, 'number-columns-repeated');
      final styleName = c.attr(OdfNs.table, 'style-name') ??
          (column < columnStyles.length ? columnStyles[column] : null);
      final cell = _cell(c, styles.cellStyle(styleName), text);
      column += repeat;
      if (cell.isEmpty) {
        pending.add((cell, repeat));
        continue;
      }
      if (column > maxColumns) {
        throw OdfException(
            'A linha tem dados além da coluna $maxColumns; aumente OdsReader.maxColumns para lê-la.');
      }
      for (final (empty, count) in pending) {
        for (var i = 0; i < count; i++) {
          cells.add(_copy(empty));
        }
      }
      pending.clear();
      for (var i = 0; i < repeat; i++) {
        cells.add(i == 0 ? cell : _copy(cell));
      }
    }
    return cells;
  }

  OdfCell _cell(XmlElement c, OdfCellStyle? style, OdfTextReader text) {
    final formula = c.attr(OdfNs.table, 'formula');
    final paragraphs =
        c.elementsOf(OdfNs.text, 'p').map(text.plainText).toList();
    var value = _value(c, paragraphs.join('\n'));
    if (formula != null) {
      value = OdfFormula(OdfFormulaConverter.fromOpenFormula(formula),
          result: value is OdfEmptyValue ? null : value);
    }
    final format = style?.numberFormat;
    if (format != null && format == defaultFormatFor(value)) {
      style = style!.withNumberFormat(null);
    }
    final annotation = c.child(OdfNs.office, 'annotation');
    return OdfCell(
      value,
      style: style == null || style.isDefault ? null : style,
      colSpan:
          int.tryParse(c.attr(OdfNs.table, 'number-columns-spanned') ?? '') ??
              1,
      rowSpan:
          int.tryParse(c.attr(OdfNs.table, 'number-rows-spanned') ?? '') ?? 1,
      note: annotation
          ?.elementsOf(OdfNs.text, 'p')
          .map(text.plainText)
          .join('\n'),
    );
  }

  OdfCellValue _value(XmlElement c, String displayed) {
    num? number() {
      final v = c.attr(OdfNs.office, 'value');
      if (v == null) return null;
      final parsed = num.tryParse(v);
      return parsed is double &&
              parsed == parsed.truncateToDouble() &&
              !v.contains('.')
          ? parsed.toInt()
          : parsed;
    }

    switch (c.attr(OdfNs.office, 'value-type')) {
      case 'float':
        final n = number();
        return n == null ? const OdfEmptyValue() : OdfNumberValue(n);
      case 'percentage':
        final n = number();
        return n == null ? const OdfEmptyValue() : OdfPercentageValue(n);
      case 'currency':
        final n = number();
        return n == null
            ? const OdfEmptyValue()
            : OdfCurrencyValue(n,
                currency: c.attr(OdfNs.office, 'currency') ?? 'BRL');
      case 'date':
        final raw = c.attr(OdfNs.office, 'date-value');
        final date = raw == null ? null : DateTime.tryParse(raw);
        return date == null
            ? OdfStringValue(displayed)
            : OdfDateValue(date, includeTime: raw!.contains('T'));
      case 'time':
        final duration = _duration(c.attr(OdfNs.office, 'time-value'));
        return duration == null
            ? OdfStringValue(displayed)
            : OdfTimeValue(duration);
      case 'boolean':
        return OdfBooleanValue(c.attr(OdfNs.office, 'boolean-value') == 'true');
      case 'string':
        return OdfStringValue(
            c.attr(OdfNs.office, 'string-value') ?? displayed);
      default:
        return displayed.isEmpty
            ? const OdfEmptyValue()
            : OdfStringValue(displayed);
    }
  }

  Duration? _duration(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^-?P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?$')
        .firstMatch(value);
    if (m == null) return null;
    final seconds = double.tryParse(m.group(4) ?? '0') ?? 0;
    return Duration(
      days: int.tryParse(m.group(1) ?? '') ?? 0,
      hours: int.tryParse(m.group(2) ?? '') ?? 0,
      minutes: int.tryParse(m.group(3) ?? '') ?? 0,
      milliseconds: (seconds * 1000).round(),
    );
  }

  int _repeat(XmlElement e, String attribute) =>
      int.tryParse(e.attr(OdfNs.table, attribute) ?? '') ?? 1;

  OdfCell _copy(OdfCell c) => OdfCell(c.value,
      style: c.style, colSpan: c.colSpan, rowSpan: c.rowSpan, note: c.note);
}

// ===========================================================================
// ODP
// ===========================================================================

class OdpReader {
  OdfPresentation read(OdfPackageEntity package) {
    final xml = OdfPackageXml(package)
      ..expectType(OdfDocumentType.presentation);
    final styles = xml.styleSheet();
    final text = OdfTextReader(styles, xml.lookup);

    final masterSheet = OdfStyleSheet([xml.xml('styles.xml')]);
    final master = masterSheet.masterPages.firstOrNull;
    final layout = masterSheet
        .pageLayoutProps(master?.attr(OdfNs.style, 'page-layout-name'));
    final size = OdfSlideSize(
      parseLength(layout?.attr(OdfNs.fo, 'page-width')) ??
          OdfSlideSize.widescreen.width,
      parseLength(layout?.attr(OdfNs.fo, 'page-height')) ??
          OdfSlideSize.widescreen.height,
    );

    return OdfPresentation(
      metadata: readMetadata(xml),
      size: size,
      slides: [
        for (final page
            in xml.body('presentation').elementsOf(OdfNs.draw, 'page'))
          _slide(page, styles, text),
      ],
    );
  }

  OdfSlide _slide(XmlElement page, OdfStyleSheet styles, OdfTextReader text) {
    final slide = OdfSlide();
    final background =
        styles.drawingPageProps(page.attr(OdfNs.draw, 'style-name'));
    if (background?.attr(OdfNs.draw, 'fill') == 'solid') {
      slide.background =
          OdfColor.tryParse(background?.attr(OdfNs.draw, 'fill-color'));
    }

    void shapes(XmlElement parent) {
      for (final e in parent.childElements) {
        if (e.isA(OdfNs.draw, 'g')) {
          shapes(e);
        } else if (e.isA(OdfNs.draw, 'frame')) {
          _frame(e, slide, styles, text);
        } else if (e.isA(OdfNs.draw, 'rect') ||
            e.isA(OdfNs.draw, 'ellipse') ||
            e.isA(OdfNs.draw, 'custom-shape')) {
          slide.elements.add(_shape(e, styles, text));
        } else if (e.isA(OdfNs.presentation, 'notes')) {
          final notes = e
              .elementsOf(OdfNs.draw, 'frame')
              .where((f) => f.attr(OdfNs.presentation, 'class') == 'notes')
              .map((f) => f.child(OdfNs.draw, 'text-box'))
              .whereType<XmlElement>()
              .map((box) => box
                  .elementsOf(OdfNs.text, 'p')
                  .map(text.plainText)
                  .join('\n'))
              .join('\n');
          if (notes.isNotEmpty) slide.notes = notes;
        }
      }
    }

    shapes(page);
    return slide;
  }

  void _frame(
      XmlElement e, OdfSlide slide, OdfStyleSheet styles, OdfTextReader text) {
    final kind = e.attr(OdfNs.presentation, 'class');
    final box = e.child(OdfNs.draw, 'text-box');
    if (kind == 'title' && box != null) {
      final title =
          box.elementsOf(OdfNs.text, 'p').map(text.plainText).join('\n');
      if (title.isNotEmpty) {
        slide
          ..title = title
          ..titleStyle = text.firstStyle(box.elementsOf(OdfNs.text, 'p'));
      }
      return;
    }
    if (box != null) {
      final base = styles
          .textProps('graphic', e.attr(OdfNs.draw, 'style-name'),
              directOnly: true)
          .merge(styles.textProps(
              'presentation', e.attr(OdfNs.presentation, 'style-name'),
              directOnly: true));
      final blocks = text.blocksWithBase(box, base);
      if (blocks.isNotEmpty) {
        slide.elements.add(OdfTextBox(blocks, frame: _geometry(e)));
      }
      return;
    }
    final image = text.imageData(e);
    if (image != null) {
      slide.elements.add(OdfSlideImage(image, frame: _geometry(e)));
    }
  }

  OdfShape _shape(XmlElement e, OdfStyleSheet styles, OdfTextReader text) {
    final graphic =
        styles.graphicProps('graphic', e.attr(OdfNs.draw, 'style-name'));
    final geometryType =
        e.child(OdfNs.draw, 'enhanced-geometry')?.attr(OdfNs.draw, 'type');
    final ellipse = e.isA(OdfNs.draw, 'ellipse') || geometryType == 'ellipse';
    final content =
        e.elementsOf(OdfNs.text, 'p').map(text.plainText).join('\n');
    return OdfShape(
      ellipse ? OdfShapeKind.ellipse : OdfShapeKind.rectangle,
      frame: _geometry(e) ?? const OdfFrame(0, 0, 0, 0),
      fill: graphic?.attr(OdfNs.draw, 'fill') == 'solid'
          ? OdfColor.tryParse(graphic?.attr(OdfNs.draw, 'fill-color'))
          : null,
      stroke: graphic?.attr(OdfNs.draw, 'stroke') == 'none'
          ? null
          : OdfColor.tryParse(graphic?.attr(OdfNs.svg, 'stroke-color')),
      text: content.isEmpty ? null : content,
      textStyle: text.firstStyle(e.elementsOf(OdfNs.text, 'p')),
    );
  }

  OdfFrame? _geometry(XmlElement e) {
    final width = parseLength(e.attr(OdfNs.svg, 'width'));
    final height = parseLength(e.attr(OdfNs.svg, 'height'));
    if (width == null || height == null) return null;
    return OdfFrame(parseLength(e.attr(OdfNs.svg, 'x')) ?? 0,
        parseLength(e.attr(OdfNs.svg, 'y')) ?? 0, width, height);
  }
}
