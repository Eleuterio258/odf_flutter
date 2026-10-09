import 'dart:convert';

import 'package:xml/xml.dart';

import '../entities/odf_package_entity.dart';
import '../exceptions/odf_exception.dart';

/// Extrai o texto de parágrafos e títulos, um por linha, na ordem do documento.
///
/// `text:s`, `text:tab` e `text:line-break` viram espaços, `\t` e `\n`.
/// Notas de rodapé e comentários não entram no texto principal.
class ExtractOdfText {
  const ExtractOdfText();

  static const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
  static const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';

  String call(OdfPackageEntity package) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(package.contentXml));
    } on XmlException catch (e) {
      throw OdfException('XML inválido em content.xml: ${e.message}');
    } on FormatException {
      throw const OdfException('content.xml não está em UTF-8 válido.');
    }
    final body =
        document.rootElement.getElement('office:body') ?? document.rootElement;
    final lines = <String>[];
    _collect(body, lines);
    return lines.join('\n');
  }

  void _collect(XmlElement element, List<String> lines) {
    for (final child in element.childElements) {
      final ns = child.name.namespaceUri;
      final local = child.name.local;
      if (ns == _office && local == 'annotation') continue;
      if (ns == _text && (local == 'p' || local == 'h')) {
        final buffer = StringBuffer();
        _inline(child, buffer);
        lines.add(buffer.toString());
      } else if (!(ns == _text &&
          (local == 'tracked-changes' || local == 'note'))) {
        _collect(child, lines);
      }
    }
  }

  void _inline(XmlElement element, StringBuffer out) {
    for (final node in element.children) {
      if (node is XmlText || node is XmlCDATA) {
        out.write(node.value!.replaceAll(RegExp(r'\s+'), ' '));
      } else if (node is XmlElement) {
        final ns = node.name.namespaceUri;
        final local = node.name.local;
        if (ns == _office && local == 'annotation') continue;
        if (ns == _text) {
          switch (local) {
            case 's':
              out.write(' ' *
                  (int.tryParse(
                          node.getAttribute('c', namespace: _text) ?? '') ??
                      1));
              continue;
            case 'tab':
              out.write('\t');
              continue;
            case 'line-break':
              out.write('\n');
              continue;
            case 'note' ||
                  'bookmark-start' ||
                  'bookmark-end' ||
                  'soft-page-break':
              continue;
          }
        }
        _inline(node, out);
      }
    }
  }
}
