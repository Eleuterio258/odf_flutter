import 'dart:convert';

import 'package:xml/xml.dart';

import '../../domain/entities/odf_package_entity.dart';
import '../../domain/entities/odf_template_options.dart';
import '../../domain/entities/odf_types.dart';
import '../../domain/exceptions/odf_exception.dart';
import '../datasources/odf_zip_data_source.dart';
import 'odf_style_writer.dart' show formatDate;
import 'odf_xml.dart';

final _placeholder = RegExp(r'\{\{\s*([^{}]*?)\s*\}\}');
final _blockMarker = RegExp(r'^\s*\{\{\s*([#^/])\s*([^{}]*?)\s*\}\}\s*$');

// Caracteres de uso privado que marcam quebras, tabulações e espaços extras
// vindos dos valores, convertidos depois em elementos ODF.
const _newline = '';
const _tab = '';
const _space = '';

class _Missing {
  const _Missing();
}

const _missing = _Missing();

/// Preenche `{{campos}}` diretamente no XML, preservando o resto do pacote.
class OdfTemplateEngine {
  OdfTemplateEngine(this.options);

  final OdfTemplateOptions options;
  final _missingFields = <String>{};

  /// Lista os campos usados no documento (sem repetir, na ordem em que aparecem).
  static List<String> fields(OdfPackageEntity package) {
    final found = <String>{};
    for (final path in const ['content.xml', 'styles.xml']) {
      if (!package.contains(path)) continue;
      final document = _parse(package, path);
      for (final p in _paragraphs(document.rootElement)) {
        for (final match in _placeholder.allMatches(_paragraphText(p))) {
          final name = match.group(1)!;
          found.add(name.startsWith('#') ||
                  name.startsWith('^') ||
                  name.startsWith('/')
              ? name.substring(1).trim()
              : name);
        }
      }
    }
    return found.toList();
  }

  Map<String, List<int>> fill(
      OdfPackageEntity package, Map<String, Object?> data) {
    final files = <String, List<int>>{
      for (final path in package.paths) path: package.file(path),
    };

    final content = _parse(package, 'content.xml');
    final body = content.rootElement.child(OdfNs.office, 'body');
    if (body != null) _process(body, [data]);
    files['content.xml'] = utf8.encode(content.toXmlString());

    if (package.contains('styles.xml')) {
      final styles = _parse(package, 'styles.xml');
      final master = styles.rootElement.child(OdfNs.office, 'master-styles');
      if (master != null) _process(master, [data]);
      files['styles.xml'] = utf8.encode(styles.toXmlString());
    }

    if (options.missing == OdfMissingField.error && _missingFields.isNotEmpty) {
      throw OdfException('Campos sem valor: ${_missingFields.join(', ')}');
    }

    // O preenchimento de um modelo (.ott) gera um documento (.odt).
    if (package.isTemplate) {
      final template = utf8.decode(files['mimetype']!).trim();
      final mime = OdfDocumentType.fromMimeType(template).mimeType;
      files['mimetype'] = utf8.encode(mime);
      final manifest = files['META-INF/manifest.xml'];
      if (manifest != null) {
        files['META-INF/manifest.xml'] =
            utf8.encode(utf8.decode(manifest).replaceAll(template, mime));
      }
    }
    return files;
  }

  static XmlDocument _parse(OdfPackageEntity package, String path) {
    try {
      final document = XmlDocument.parse(
          OdfZipDataSource.decodeUtf8(package.file(path), path));
      // O arquivo é regravado em UTF-8; uma declaração antiga como "us-ascii"
      // tornaria inválidos os caracteres que eram referências (&#x2022;).
      final declaration = document.declaration;
      if (declaration != null && declaration.encoding != null) {
        declaration.encoding = 'UTF-8';
      }
      return document;
    } on XmlException catch (e) {
      throw OdfException('XML inválido em $path: ${e.message}');
    }
  }

  // ------------------------------------------------------------ estrutura

  void _process(XmlElement container, List<Object?> context) =>
      _processRange(container, 0, container.children.length, context);

  /// Processa os filhos em `[start, end)` e devolve o novo fim do intervalo.
  /// Cópias são inseridas no documento antes de processadas: fora da árvore,
  /// os prefixos `text:`/`table:` não resolvem seus namespaces.
  int _processRange(
      XmlElement container, int start, int end, List<Object?> context) {
    final children = container.children;
    var i = start;
    while (i < end) {
      final node = children[i];
      if (node is! XmlElement) {
        i++;
        continue;
      }

      // Blocos {{#chave}} ... {{/chave}} entre parágrafos irmãos.
      final marker = _isParagraph(node)
          ? _blockMarker.firstMatch(_paragraphText(node))
          : null;
      if (marker != null && marker.group(1) != '/') {
        final key = marker.group(2)!;
        final close = _findBlockEnd(children, i, key, end);
        final inner = [
          for (final n in children.sublist(i + 1, close)) n.copy()
        ];
        final value = _lookup(key, context);
        final contexts = <List<Object?>>[
          if (marker.group(1) == '^')
            if (!_truthy(value)) context else ...[]
          else if (value is Iterable && value is! String)
            for (final (index, item) in value.indexed)
              [
                ...context,
                item,
                {'@index': index + 1}
              ]
          else if (_truthy(value))
            value is Map ? [...context, value] : context,
        ];
        final removed = close - i + 1;
        for (var k = close; k >= i; k--) {
          children.removeAt(k);
        }
        var position = i;
        for (final itemContext in contexts) {
          final copies = [for (final n in inner) n.copy()];
          children.insertAll(position, copies);
          position = _processRange(
              container, position, position + copies.length, itemContext);
        }
        end += (position - i) - removed;
        i = position;
        continue;
      }
      if (marker != null) {
        throw OdfException(
            '{{/${marker.group(2)}}} sem {{#${marker.group(2)}}} correspondente.');
      }

      // Linhas de tabela e itens de lista que usam {{lista.campo}} são repetidos.
      if (node.isA(OdfNs.table, 'table-row') ||
          node.isA(OdfNs.text, 'list-item')) {
        final list = _repeatingList(node, context);
        if (list != null) {
          children.removeAt(i);
          var position = i;
          for (final (index, item) in list.$2.indexed) {
            final copy = node.copy();
            children.insert(position, copy);
            _process(copy, [
              ...context,
              {list.$1: item, '@index': index + 1}
            ]);
            position++;
          }
          end += (position - i) - 1;
          i = position;
          continue;
        }
      }

      if (node.isA(OdfNs.table, 'table-cell') && _typedCell(node, context)) {
        i++;
        continue;
      }
      if (_isParagraph(node)) {
        _replaceInParagraph(node, context);
        // Notas e caixas de texto dentro do parágrafo têm parágrafos próprios.
        for (final nested
            in node.descendantElements.where(_isContainer).toList()) {
          _process(nested, context);
        }
      } else {
        _process(node, context);
      }
      i++;
    }
    return end;
  }

  int _findBlockEnd(List<XmlNode> children, int start, String key, int end) {
    var depth = 0;
    for (var j = start + 1; j < end; j++) {
      final node = children[j];
      if (node is! XmlElement || !_isParagraph(node)) continue;
      final m = _blockMarker.firstMatch(_paragraphText(node));
      if (m == null || m.group(2) != key) continue;
      if (m.group(1) == '/') {
        if (depth == 0) return j;
        depth--;
      } else {
        depth++;
      }
    }
    throw OdfException(
        '{{#$key}} sem {{/$key}}: o fechamento deve estar no mesmo nível (mesma célula ou seção).');
  }

  (String, Iterable<Object?>)? _repeatingList(
      XmlElement row, List<Object?> context) {
    for (final p in _paragraphs(row)) {
      for (final match in _placeholder.allMatches(_paragraphText(p))) {
        final path = match.group(1)!;
        if (!path.contains('.') ||
            path.startsWith('#') ||
            path.startsWith('^') ||
            path.startsWith('/')) {
          continue;
        }
        final head = path.substring(0, path.indexOf('.'));
        final value = _lookup(head, context);
        if (value is Iterable && value is! String) return (head, value);
      }
    }
    return null;
  }

  // -------------------------------------------------------------- valores

  Object? _lookup(String path, List<Object?> context) {
    if (path == '.' || path == 'this') return context.last;
    final parts = path.split('.');
    for (var c = context.length - 1; c >= 0; c--) {
      Object? value = context[c];
      if (value is! Map || !value.containsKey(parts.first)) continue;
      value = value[parts.first];
      for (final part in parts.skip(1)) {
        if (value is Map && value.containsKey(part)) {
          value = value[part];
        } else if (value is List &&
            (int.tryParse(part) ?? -1) >= 0 &&
            int.parse(part) < value.length) {
          value = value[int.parse(part)];
        } else {
          return _missing;
        }
      }
      return value;
    }
    return _missing;
  }

  bool _truthy(Object? value) => switch (value) {
        null || false || _Missing() => false,
        final String s => s.isNotEmpty,
        final Iterable<Object?> it => it.isNotEmpty,
        final Map<Object?, Object?> m => m.isNotEmpty,
        _ => true,
      };

  String? _text(String path, List<Object?> context) {
    final value = _lookup(path, context);
    if (value is _Missing) {
      _missingFields.add(path);
      return options.missing == OdfMissingField.keep ? '{{$path}}' : '';
    }
    final custom = options.format;
    if (custom != null) return custom(value);
    return switch (value) {
      null => '',
      final DateTime d => formatDate(
          d,
          d.hour == 0 && d.minute == 0 && d.second == 0
              ? 'dd/MM/yyyy'
              : 'dd/MM/yyyy HH:mm'),
      final double d when d == d.truncateToDouble() && d.abs() < 1e15 =>
        d.toInt().toString(),
      true => 'Sim',
      false => 'Não',
      _ => value.toString(),
    };
  }

  // ------------------------------------------------------------- parágrafos

  static bool _isParagraph(XmlElement e) =>
      e.isA(OdfNs.text, 'p') || e.isA(OdfNs.text, 'h');

  /// Elementos dentro de um parágrafo que contêm outros parágrafos.
  static bool _isContainer(XmlElement e) =>
      e.isA(OdfNs.text, 'note-body') ||
      e.isA(OdfNs.draw, 'text-box') ||
      e.isA(OdfNs.office, 'annotation');

  static Iterable<XmlElement> _paragraphs(XmlElement root) =>
      root.descendantElements.where(_isParagraph);

  /// Nós de texto que pertencem diretamente a este parágrafo (não a notas internas).
  static List<XmlText> _ownTexts(XmlElement paragraph) => [
        for (final t in paragraph.descendants.whereType<XmlText>())
          if (_owner(t) == paragraph) t,
      ];

  static XmlElement? _owner(XmlNode node) {
    var parent = node.parentElement;
    while (parent != null && !_isParagraph(parent)) {
      parent = parent.parentElement;
    }
    return parent;
  }

  static String _paragraphText(XmlElement paragraph) =>
      _ownTexts(paragraph).map((t) => t.value).join();

  /// Substitui os campos mesmo quando o editor dividiu `{{campo}}` em vários
  /// trechos de formatação: o valor herda a formatação do início do campo.
  void _replaceInParagraph(XmlElement paragraph, List<Object?> context) {
    final texts = _ownTexts(paragraph);
    if (texts.isEmpty) return;
    final full = texts.map((t) => t.value).join();
    final matches = _placeholder.allMatches(full).toList();
    if (matches.isEmpty) return;

    final starts = <int>[];
    var offset = 0;
    for (final t in texts) {
      starts.add(offset);
      offset += t.value.length;
    }
    (int, int) locate(int position) {
      var n = texts.length - 1;
      while (n > 0 && starts[n] > position) {
        n--;
      }
      return (n, position - starts[n]);
    }

    for (final match in matches.reversed) {
      final value = _encode(_text(match.group(1)!, context) ?? '');
      final (startNode, startOffset) = locate(match.start);
      final (endNode, endOffset) = locate(match.end - 1);
      final first = texts[startNode];
      if (startNode == endNode) {
        first.value =
            first.value.replaceRange(startOffset, endOffset + 1, value);
      } else {
        final last = texts[endNode];
        last.value = last.value.substring(endOffset + 1);
        for (var n = startNode + 1; n < endNode; n++) {
          texts[n].value = '';
        }
        first.value = first.value.substring(0, startOffset) + value;
      }
    }
    for (final t in texts) {
      if (t.value.contains(RegExp('[$_newline$_tab$_space]'))) {
        _expandMarkers(t);
      }
    }
  }

  static String _encode(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll('\n', _newline)
      .replaceAll('\t', _tab)
      .replaceAllMapped(
          RegExp(' {2,}'), (m) => ' ${_space * (m.group(0)!.length - 1)}');

  static void _expandMarkers(XmlText text) {
    final parent = text.parent!;
    final nodes = <XmlNode>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) nodes.add(XmlText(buffer.toString()));
      buffer.clear();
    }

    final value = text.value;
    var i = 0;
    while (i < value.length) {
      final c = value[i];
      if (c == _newline) {
        flush();
        nodes.add(XmlElement(XmlName.fromString('text:line-break')));
      } else if (c == _tab) {
        flush();
        nodes.add(XmlElement(XmlName.fromString('text:tab')));
      } else if (c == _space) {
        flush();
        var count = 1;
        while (i + 1 < value.length && value[i + 1] == _space) {
          count++;
          i++;
        }
        nodes.add(XmlElement(XmlName.fromString('text:s'), [
          if (count > 1) XmlAttribute(XmlName.fromString('text:c'), '$count')
        ]));
      } else {
        buffer.write(c);
      }
      i++;
    }
    flush();
    final index = parent.children.indexOf(text);
    parent.children
      ..removeAt(index)
      ..insertAll(index, nodes);
  }

  // ------------------------------------------------------- células tipadas

  /// Célula de planilha contendo apenas `{{campo}}` com valor número, data ou
  /// booleano: grava o valor tipado. Retorna falso para seguir o fluxo normal.
  bool _typedCell(XmlElement cell, List<Object?> context) {
    final paragraphs = cell.elementsOf(OdfNs.text, 'p').toList();
    if (paragraphs.length != 1) return false;
    final match = RegExp(r'^\s*\{\{\s*([^{}#^/][^{}]*?)\s*\}\}\s*$')
        .firstMatch(_paragraphText(paragraphs.single));
    if (match == null) return false;
    final value = _lookup(match.group(1)!, context);
    final (String type, Map<String, String> attributes)? typed =
        switch (value) {
      final num n => ('float', {'office:value': '$n'}),
      final bool b => ('boolean', {'office:boolean-value': '$b'}),
      final DateTime d => (
          'date',
          {
            'office:date-value': d.hour == 0 && d.minute == 0 && d.second == 0
                ? d.toIso8601String().substring(0, 10)
                : d.toIso8601String().replaceFirst(RegExp(r'\.\d+$'), ''),
          }
        ),
      _ => null,
    };
    if (typed == null) return false;
    for (final name in const [
      'office:value',
      'office:string-value',
      'office:boolean-value',
      'office:date-value',
      'office:time-value',
      'office:currency'
    ]) {
      cell.removeAttribute(name);
    }
    final calcext = cell.attributes.where(
        (a) => a.name.local == 'value-type' && a.name.prefix == 'calcext');
    for (final a in calcext.toList()) {
      a.value = typed.$1;
    }
    cell.setAttribute('office:value-type', typed.$1);
    typed.$2.forEach(cell.setAttribute);
    _replaceInParagraph(paragraphs.single, context);
    return true;
  }
}
