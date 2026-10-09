import 'package:xml/xml.dart';

import '../../domain/entities/odf_color.dart';
import '../../domain/entities/odf_rich_text.dart';
import '../../domain/entities/odf_workbook.dart';
import 'odf_style_writer.dart' show currencySymbols;
import 'odf_xml.dart';

/// Propriedades de texto parciais: `null` significa "não definido" (herda).
class TextProps {
  const TextProps({
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
    this.position,
    this.fontSize,
    this.fontFamily,
    this.color,
    this.backgroundColor,
  });

  static const empty = TextProps();

  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strikethrough;

  /// 1 = sobrescrito, -1 = subscrito, 0 = normal.
  final int? position;
  final double? fontSize;
  final String? fontFamily;
  final OdfColor? color;
  final OdfColor? backgroundColor;

  factory TextProps.parse(XmlElement? e) {
    if (e == null) return empty;
    bool? flag(String? value, bool Function(String v) isOn) =>
        value == null ? null : isOn(value);
    final weight = e.attr(OdfNs.fo, 'font-weight');
    final position = e.attr(OdfNs.style, 'text-position');
    final family =
        e.attr(OdfNs.fo, 'font-family') ?? e.attr(OdfNs.style, 'font-name');
    final background = e.attr(OdfNs.fo, 'background-color');
    return TextProps(
      bold: flag(weight, (v) => v == 'bold' || (int.tryParse(v) ?? 400) >= 600),
      italic: flag(e.attr(OdfNs.fo, 'font-style'),
          (v) => v == 'italic' || v == 'oblique'),
      underline:
          flag(e.attr(OdfNs.style, 'text-underline-style'), (v) => v != 'none'),
      strikethrough: flag(
          e.attr(OdfNs.style, 'text-line-through-style'), (v) => v != 'none'),
      position: position == null
          ? null
          : position.startsWith('super')
              ? 1
              : position.startsWith('sub')
                  ? -1
                  : (double.tryParse(
                              position.split(' ').first.replaceAll('%', '')) ??
                          0)
                      .sign
                      .toInt(),
      fontSize: parsePoints(e.attr(OdfNs.fo, 'font-size')),
      fontFamily: family?.replaceAll(RegExp("^['\"]|['\"]\$"), ''),
      color: OdfColor.tryParse(e.attr(OdfNs.fo, 'color')),
      backgroundColor:
          background == 'transparent' ? null : OdfColor.tryParse(background),
    );
  }

  /// [other] tem precedência sobre este.
  TextProps merge(TextProps other) => TextProps(
        bold: other.bold ?? bold,
        italic: other.italic ?? italic,
        underline: other.underline ?? underline,
        strikethrough: other.strikethrough ?? strikethrough,
        position: other.position ?? position,
        fontSize: other.fontSize ?? fontSize,
        fontFamily: other.fontFamily ?? fontFamily,
        color: other.color ?? color,
        backgroundColor: other.backgroundColor ?? backgroundColor,
      );

  OdfTextStyle toStyle() => OdfTextStyle(
        bold: bold ?? false,
        italic: italic ?? false,
        underline: underline ?? false,
        strikethrough: strikethrough ?? false,
        superscript: position == 1,
        subscript: position == -1,
        fontSize: fontSize,
        fontFamily: fontFamily,
        color: color,
        backgroundColor: backgroundColor,
      );
}

class _Style {
  _Style(this.element, {required this.automatic});

  final XmlElement element;
  final bool automatic;

  String? get parent => element.attr(OdfNs.style, 'parent-style-name');

  XmlElement? props(String local) => element.child(OdfNs.style, local);
}

/// Índice dos estilos de um documento (comuns + automáticos).
class OdfStyleSheet {
  OdfStyleSheet(Iterable<XmlDocument?> documents) {
    for (final doc in documents.whereType<XmlDocument>()) {
      final root = doc.rootElement;
      for (final (container, automatic) in [
        ('styles', false),
        ('automatic-styles', true)
      ]) {
        final section = root.child(OdfNs.office, container);
        if (section != null) _index(section, automatic: automatic);
      }
      final master = root.child(OdfNs.office, 'master-styles');
      if (master != null) {
        for (final page in master.elementsOf(OdfNs.style, 'master-page')) {
          masterPages.add(page);
        }
      }
    }
  }

  final _styles = <String, _Style>{};
  final _listStyles = <String, XmlElement>{};
  final _dataStyles = <String, XmlElement>{};
  final _pageLayouts = <String, XmlElement>{};
  final masterPages = <XmlElement>[];

  void _index(XmlElement section, {required bool automatic}) {
    for (final e in section.childElements) {
      final name = e.attr(OdfNs.style, 'name');
      if (name == null) continue;
      if (e.isA(OdfNs.style, 'style')) {
        final family = e.attr(OdfNs.style, 'family');
        _styles['$family:$name'] = _Style(e, automatic: automatic);
      } else if (e.isA(OdfNs.text, 'list-style')) {
        _listStyles[name] = e;
      } else if (e.isA(OdfNs.style, 'page-layout')) {
        _pageLayouts[name] = e;
      } else if (e.name.namespaceUri == OdfNs.number) {
        _dataStyles[name] = e;
      }
    }
  }

  _Style? _find(String family, String? name) =>
      name == null ? null : _styles['$family:$name'];

  /// Propriedades de texto seguindo a herança; com [directOnly], para no
  /// primeiro estilo comum (só interessa a formatação direta).
  TextProps textProps(String family, String? name, {bool directOnly = false}) {
    final chain = <_Style>[];
    var style = _find(family, name);
    while (style != null && chain.length < 20) {
      if (directOnly && !style.automatic) break;
      chain.add(style);
      style = _find(family, style.parent);
    }
    return chain.reversed.fold(TextProps.empty,
        (acc, s) => acc.merge(TextProps.parse(s.props('text-properties'))));
  }

  XmlElement? paragraphProps(String? name) {
    final style = _find('paragraph', name);
    return style != null && style.automatic
        ? style.props('paragraph-properties')
        : null;
  }

  OdfParagraphStyle paragraphStyle(String? name) {
    final p = paragraphProps(name);
    if (p == null) return OdfParagraphStyle.normal;
    return OdfParagraphStyle(
      align: parseAlign(p.attr(OdfNs.fo, 'text-align')),
      spaceBefore: parseLength(p.attr(OdfNs.fo, 'margin-top')),
      spaceAfter: parseLength(p.attr(OdfNs.fo, 'margin-bottom')),
      indentLeft: parseLength(p.attr(OdfNs.fo, 'margin-left')),
      firstLineIndent: parseLength(p.attr(OdfNs.fo, 'text-indent')),
      lineSpacing: parsePercent(p.attr(OdfNs.fo, 'line-height')),
      backgroundColor: OdfColor.tryParse(p.attr(OdfNs.fo, 'background-color')),
    );
  }

  bool breakBefore(String? paragraphStyle) =>
      paragraphProps(paragraphStyle)?.attr(OdfNs.fo, 'break-before') == 'page';

  bool breakAfter(String? paragraphStyle) =>
      paragraphProps(paragraphStyle)?.attr(OdfNs.fo, 'break-after') == 'page';

  /// Verdadeiro para listas numeradas no nível informado.
  bool? listOrdered(String? name, int level) {
    final style = name == null ? null : _listStyles[name];
    if (style == null) return null;
    for (final e in style.childElements) {
      if (e.attr(OdfNs.text, 'level') == '$level') {
        return e.name.local == 'list-level-style-number';
      }
    }
    return null;
  }

  XmlElement? cellProps(String? name, String local) =>
      _find('table-cell', name)?.props(local);

  String? dataStyleName(String? cellStyle) => _find('table-cell', cellStyle)
      ?.element
      .attr(OdfNs.style, 'data-style-name');

  double? columnWidth(String? name) => parseLength(_find('table-column', name)
      ?.props('table-column-properties')
      ?.attr(OdfNs.style, 'column-width'));

  double? rowHeight(String? name) {
    final p = _find('table-row', name)?.props('table-row-properties');
    if (p == null || p.attr(OdfNs.style, 'use-optimal-row-height') == 'true') {
      return null;
    }
    return parseLength(p.attr(OdfNs.style, 'row-height'));
  }

  XmlElement? graphicProps(String family, String? name) =>
      _find(family, name)?.props('graphic-properties');

  XmlElement? drawingPageProps(String? name) =>
      _find('drawing-page', name)?.props('drawing-page-properties');

  XmlElement? pageLayoutProps(String? name) => name == null
      ? null
      : _pageLayouts[name]?.child(OdfNs.style, 'page-layout-properties');

  OdfCellStyle? cellStyle(String? name) {
    if (name == null) return null;
    final text = textProps('table-cell', name);
    final cell = cellProps(name, 'table-cell-properties');
    final paragraph = cellProps(name, 'paragraph-properties');
    final border =
        cell?.attr(OdfNs.fo, 'border') ?? cell?.attr(OdfNs.fo, 'border-top');
    final style = OdfCellStyle(
      bold: text.bold ?? false,
      italic: text.italic ?? false,
      underline: text.underline ?? false,
      fontSize: _isAutomatic('table-cell', name) ? text.fontSize : null,
      color: text.color,
      backgroundColor: cell?.attr(OdfNs.fo, 'background-color') == 'transparent'
          ? null
          : OdfColor.tryParse(cell?.attr(OdfNs.fo, 'background-color')),
      align: parseAlign(paragraph?.attr(OdfNs.fo, 'text-align')),
      verticalAlign: switch (cell?.attr(OdfNs.style, 'vertical-align')) {
        'top' => OdfVerticalAlign.top,
        'middle' => OdfVerticalAlign.middle,
        'bottom' => OdfVerticalAlign.bottom,
        _ => null,
      },
      wrap: cell?.attr(OdfNs.fo, 'wrap-option') == 'wrap',
      border: border != null && border != 'none',
      numberFormat: numberFormat(dataStyleName(name)),
    );
    return style.isDefault ? null : style;
  }

  bool _isAutomatic(String family, String name) =>
      _find(family, name)?.automatic ?? false;

  OdfNumberFormat? numberFormat(String? name) {
    final e = name == null ? null : _dataStyles[name];
    if (e == null) return null;
    final number = e.child(OdfNs.number, 'number');
    final decimals =
        int.tryParse(number?.attr(OdfNs.number, 'decimal-places') ?? '') ?? 0;
    switch (e.name.local) {
      case 'number-style':
        if (number == null) return null;
        return OdfNumberFormat.number(
            decimals: decimals,
            grouping: number.attr(OdfNs.number, 'grouping') == 'true');
      case 'percentage-style':
        return OdfNumberFormat.percentage(decimals: decimals);
      case 'currency-style':
        final symbol =
            e.child(OdfNs.number, 'currency-symbol')?.innerText.trim() ?? '';
        final code = currencySymbols.entries
            .where((c) => c.value == symbol)
            .map((c) => c.key)
            .firstOrNull;
        return OdfNumberFormat.currency(code ?? symbol, decimals: decimals);
      case 'date-style':
        return OdfNumberFormat.date(_pattern(e));
      case 'time-style':
        return OdfNumberFormat.time(_pattern(e));
    }
    return null;
  }

  String _pattern(XmlElement style) {
    final out = StringBuffer();
    for (final e in style.childElements) {
      final long = e.attr(OdfNs.number, 'style') == 'long';
      out.write(switch (e.name.local) {
        'day' => long ? 'dd' : 'd',
        'month' when e.attr(OdfNs.number, 'textual') == 'true' =>
          long ? 'MMMM' : 'MMM',
        'month' => long ? 'MM' : 'M',
        'year' => long ? 'yyyy' : 'yy',
        'hours' => long ? 'HH' : 'H',
        'minutes' => long ? 'mm' : 'm',
        'seconds' => long ? 'ss' : 's',
        'text' => e.innerText,
        _ => '',
      });
    }
    return out.toString();
  }

  static OdfTextAlign? parseAlign(String? value) => switch (value) {
        'start' || 'left' => OdfTextAlign.start,
        'center' => OdfTextAlign.center,
        'end' || 'right' => OdfTextAlign.end,
        'justify' => OdfTextAlign.justify,
        _ => null,
      };
}
