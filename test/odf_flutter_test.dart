import 'dart:convert';

import 'package:odf_flutter/odf_flutter.dart';
import 'package:test/test.dart';

void main() {
  test('cria e reabre um ODT com parágrafos', () {
    final bytes = OdfDocument.createText(
      OdfTextDocument(
          title: 'Teste', paragraphs: ['Olá ODF', 'Segundo parágrafo']),
    );
    final package = OdfDocument.open(bytes);

    expect(package.type, OdfDocumentType.text);
    expect(package.version, '1.2');
    expect(
        OdfDocument.extractText(package), 'Teste\nOlá ODF\nSegundo parágrafo');
    expect(package.contains('styles.xml'), isTrue);
    expect(package.contains('meta.xml'), isTrue);
  });

  test('cria planilha ODS com células', () {
    final bytes = OdfDocument.createSpreadsheet(
      OdfSpreadsheet(sheets: [
        OdfSheet('Dados', rows: [
          ['Nome', 'Valor'],
          ['A', '10']
        ])
      ]),
    );
    final package = OdfDocument.open(bytes);

    expect(package.type, OdfDocumentType.spreadsheet);
    expect(utf8.decode(package.contentXml), contains('table:name="Dados"'));
  });

  test('reconhece todos os tipos MIME ODF', () {
    expect(
        OdfDocumentType.fromMimeType(
            'application/vnd.oasis.opendocument.presentation'),
        OdfDocumentType.presentation);
    expect(
        OdfDocumentType.fromMimeType(
            'application/vnd.oasis.opendocument.database'),
        OdfDocumentType.database);
    expect(
        OdfDocumentType.fromMimeType(
            'application/vnd.oasis.opendocument.graphics'),
        OdfDocumentType.graphics);
    expect(
        OdfDocumentType.fromMimeType(
            'application/vnd.oasis.opendocument.formula'),
        OdfDocumentType.formula);
  });
}
