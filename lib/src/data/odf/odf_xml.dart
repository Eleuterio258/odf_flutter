import 'package:xml/xml.dart';

abstract final class OdfNs {
  static const office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
  static const style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
  static const text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
  static const table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
  static const draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
  static const fo =
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
  static const xlink = 'http://www.w3.org/1999/xlink';
  static const dc = 'http://purl.org/dc/elements/1.1/';
  static const meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
  static const number = 'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0';
  static const svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
  static const presentation =
      'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0';
  static const manifest = 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0';
  static const of = 'urn:oasis:names:tc:opendocument:xmlns:of:1.2';

  static const declarations = {
    'xmlns:office': office,
    'xmlns:style': style,
    'xmlns:text': text,
    'xmlns:table': table,
    'xmlns:draw': draw,
    'xmlns:fo': fo,
    'xmlns:xlink': xlink,
    'xmlns:dc': dc,
    'xmlns:meta': meta,
    'xmlns:number': number,
    'xmlns:svg': svg,
    'xmlns:presentation': presentation,
    'xmlns:of': of,
  };
}

const odfVersion = '1.2';
const odfGenerator = 'odf_flutter/0.3.0';
const xmlHeader = '<?xml version="1.0" encoding="UTF-8"?>';

/// Envoltório enxuto sobre [XmlBuilder]: atributos nulos são omitidos e o
/// texto é escapado automaticamente.
class OdfXmlWriter {
  final _builder = XmlBuilder();

  void el(String name,
      [Map<String, String?> attributes = const {}, void Function()? body]) {
    _builder.element(name, nest: () {
      attributes.forEach((key, value) {
        if (value != null) _builder.attribute(key, value);
      });
      body?.call();
    });
  }

  void text(String value) {
    if (value.isNotEmpty) _builder.text(value);
  }

  String fragment() => _builder
      .buildFragment()
      .children
      .map((node) => node.toXmlString())
      .join();
}

/// Monta um documento ODF completo com as declarações de namespace no elemento raiz.
String odfDocument(String root, String inner) {
  final attrs =
      OdfNs.declarations.entries.map((e) => ' ${e.key}="${e.value}"').join();
  return '$xmlHeader<$root$attrs office:version="$odfVersion">$inner</$root>';
}

// ---------------------------------------------------------------------------
// Unidades
// ---------------------------------------------------------------------------

String fmtNum(num value) {
  if (value is int || value == value.roundToDouble()) {
    return value.round().toString();
  }
  var s = value.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

String cm(double value) => '${fmtNum(value)}cm';

String pt(double value) => '${fmtNum(value)}pt';

/// Converte comprimentos ODF (`cm`, `mm`, `in`, `pt`, `pc`, `px`) para centímetros.
double? parseLength(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^\s*(-?[\d.]+)\s*([a-z%]*)\s*$').firstMatch(value);
  if (match == null) return null;
  final n = double.tryParse(match.group(1)!);
  if (n == null) return null;
  final factor = switch (match.group(2)) {
    'cm' => 1.0,
    'mm' => 0.1,
    'in' || 'inch' => 2.54,
    'pt' => 2.54 / 72,
    'pc' => 2.54 / 6,
    'px' => 2.54 / 96,
    _ => null,
  };
  return factor == null ? null : _round(n * factor);
}

double? parsePoints(String? value) {
  if (value == null || !value.trim().endsWith('pt')) return null;
  return double.tryParse(value.trim().replaceFirst('pt', ''));
}

double? parsePercent(String? value) {
  if (value == null || !value.trim().endsWith('%')) return null;
  final n = double.tryParse(value.trim().replaceFirst('%', ''));
  return n == null ? null : _round(n / 100);
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;

// ---------------------------------------------------------------------------
// Leitura
// ---------------------------------------------------------------------------

extension OdfElement on XmlElement {
  bool isA(String namespace, String local) =>
      name.local == local && name.namespaceUri == namespace;

  String? attr(String namespace, String local) =>
      getAttribute(local, namespace: namespace);

  Iterable<XmlElement> elementsOf(String namespace, String local) =>
      childElements.where((e) => e.isA(namespace, local));

  XmlElement? child(String namespace, String local) {
    for (final e in childElements) {
      if (e.isA(namespace, local)) return e;
    }
    return null;
  }
}
