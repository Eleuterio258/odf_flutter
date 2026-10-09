import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:odf_flutter/odf_flutter.dart';
import 'package:test/test.dart';

import 'advanced_test.dart' show png, unzip;

OdfPackage template(OdfRichTextDocument doc) =>
    OdfDocument.open(OdfDocument.createRichText(doc));

OdfRichTextDocument fillText(OdfPackage package, Map<String, Object?> data,
        [OdfTemplateOptions options = const OdfTemplateOptions()]) =>
    OdfDocument.readRichText(OdfDocument.open(
        OdfDocument.fillTemplate(package, data, options: options)));

void main() {
  encodingTests();

  final data = {
    'cliente': {'nome': 'Ana Souza', 'cidade': 'Maputo'},
    'data': DateTime(2026, 10, 9),
    'total': 1250.5,
    'vip': true,
    'itens': [
      {'descricao': 'Caneta', 'qtd': 10},
      {'descricao': 'Caderno', 'qtd': 3},
    ],
    'obs': 'Linha 1\nLinha 2\tcom  espaços',
    'vazio': <Object?>[],
  };

  test('campos simples, caminhos, datas, números e campo dividido em trechos',
      () {
    final doc = OdfRichTextDocument()
      ..heading('Recibo de {{cliente.nome}}')
      ..rich([
        const OdfSpan('Cliente: {{cli'),
        const OdfSpan('ente.nome}}', style: OdfTextStyle(bold: true)),
        const OdfSpan(' de {{cliente.cidade}}, em {{data}}, total {{total}}.'),
      ])
      ..paragraph('{{obs}}');
    final read = fillText(template(doc), data);
    expect(read.blocks[0].plainText, 'Recibo de Ana Souza');
    final p = read.blocks[1] as OdfParagraph;
    expect(p.plainText,
        'Cliente: Ana Souza de Maputo, em 09/10/2026, total 1250.5.');
    // O valor herda a formatação do início do campo.
    expect(
        p.inlines.first,
        const OdfSpan(
            'Cliente: Ana Souza de Maputo, em 09/10/2026, total 1250.5.'));
    expect(read.blocks[2].plainText, 'Linha 1\nLinha 2\tcom  espaços');
  });

  test('linhas de tabela e itens de lista são repetidos', () {
    final doc = OdfRichTextDocument()
      ..table([
        ['#', 'Item', 'Qtd'],
        ['{{@index}}', '{{itens.descricao}}', '{{itens.qtd}}'],
        ['', 'Total', '{{total}}'],
      ])
      ..bullets(['{{itens.descricao}} ({{itens.qtd}})']);
    final read = fillText(template(doc), data);
    final table = read.blocks[0] as OdfTable;
    expect(table.rows.map((r) => r.cells.map((c) => c.plainText).toList()), [
      ['#', 'Item', 'Qtd'],
      ['1', 'Caneta', '10'],
      ['2', 'Caderno', '3'],
      ['', 'Total', '1250.5'],
    ]);
    expect((read.blocks[1] as OdfList).items.map((i) => i.plainText),
        ['Caneta (10)', 'Caderno (3)']);
  });

  test('blocos condicionais, invertidos e repetidos', () {
    final doc = OdfRichTextDocument()
      ..paragraph('{{#vip}}')
      ..paragraph('Cliente VIP: {{cliente.nome}}')
      ..paragraph('{{/vip}}')
      ..paragraph('{{^vip}}')
      ..paragraph('Cliente comum')
      ..paragraph('{{/vip}}')
      ..paragraph('{{#itens}}')
      ..paragraph('{{@index}}. {{descricao}} x{{qtd}}')
      ..paragraph('{{/itens}}')
      ..paragraph('{{#vazio}}')
      ..paragraph('não aparece')
      ..paragraph('{{/vazio}}')
      ..paragraph('{{^vazio}}')
      ..paragraph('Sem pendências')
      ..paragraph('{{/vazio}}')
      ..paragraph('{{#cliente}}')
      ..paragraph('Cidade: {{cidade}}')
      ..paragraph('{{/cliente}}');
    final read = fillText(template(doc), data);
    expect(read.blocks.map((b) => b.plainText), [
      'Cliente VIP: Ana Souza',
      '1. Caneta x10',
      '2. Caderno x3',
      'Sem pendências',
      'Cidade: Maputo',
    ]);
  });

  test('cabeçalho, rodapé, notas, imagens e estilos são preservados', () {
    final doc = OdfRichTextDocument(
      header: [OdfParagraph.text('Pedido de {{cliente.nome}}')],
      footer: [
        OdfParagraph([const OdfSpan('Página '), const OdfPageNumber()])
      ],
      pageLayout: OdfPageLayout.a4.landscape,
    )
      ..rich(
          [const OdfSpan('Texto'), OdfNote.text('Nota para {{cliente.nome}}')])
      ..image(png);
    final original = OdfDocument.createRichText(doc);
    final filled = OdfDocument.fillTemplate(OdfDocument.open(original), data);
    final read = OdfDocument.readRichText(OdfDocument.open(filled));
    expect(read.header.single.plainText, 'Pedido de Ana Souza');
    expect(read.footer.single, isA<OdfParagraph>());
    expect(read.pageLayout, OdfPageLayout.a4.landscape);
    final note =
        (read.blocks.first as OdfParagraph).inlines.whereType<OdfNote>().single;
    expect(note.bodyText, 'Nota para Ana Souza');
    expect(read.blocks[1], isA<OdfImage>());
    // Os arquivos que não têm campos continuam idênticos.
    final before = unzip(original);
    final after = unzip(filled);
    expect(after.keys, before.keys);
    expect(after['meta.xml'], before['meta.xml']);
    expect(after['Pictures/image1.png'], before['Pictures/image1.png']);
    final archive = ZipDecoder().decodeBytes(filled);
    expect(archive.files.first.name, 'mimetype');
    expect(archive.files.first.compression, CompressionType.none);
  });

  test('células de planilha recebem valores tipados e linhas são repetidas',
      () {
    final workbook = OdfWorkbook(sheets: [
      OdfWorksheet.fromValues('S', [
        ['Item', 'Qtd', 'Data'],
        ['{{itens.descricao}}', '{{itens.qtd}}', '{{data}}'],
        ['Total', '{{total}}', 'VIP: {{vip}}'],
      ]),
    ]);
    final package = OdfDocument.open(OdfDocument.createWorkbook(workbook));
    final read = OdfDocument.readWorkbook(
            OdfDocument.open(OdfDocument.fillTemplate(package, data)))
        .sheets
        .single;
    expect(read.values, [
      ['Item', 'Qtd', 'Data'],
      ['Caneta', 10, DateTime(2026, 10, 9)],
      ['Caderno', 3, DateTime(2026, 10, 9)],
      ['Total', 1250.5, 'VIP: Sim'],
    ]);
  });

  test('ODP também é preenchido', () {
    final presentation = OdfPresentation(slides: [
      OdfSlide(title: 'Proposta para {{cliente.nome}}', elements: [
        OdfTextBox.bullets(['{{itens.descricao}}'])
      ]),
    ]);
    final package =
        OdfDocument.open(OdfDocument.createPresentation(presentation));
    final read = OdfDocument.readPresentation(
        OdfDocument.open(OdfDocument.fillTemplate(package, data)));
    expect(read.slides.single.title, 'Proposta para Ana Souza');
    final list = (read.slides.single.elements.single as OdfTextBox)
        .blocks
        .single as OdfList;
    expect(list.items.map((i) => i.plainText), ['Caneta', 'Caderno']);
  });

  test('campos ausentes: vazio, mantido ou erro', () {
    final package = template(
        OdfRichTextDocument()..paragraph('Olá {{nome}} {{sobrenome}}'));
    expect(fillText(package, {'nome': 'Ana'}).plainText, 'Olá Ana ');
    expect(
        fillText(package, {'nome': 'Ana'},
                const OdfTemplateOptions(missing: OdfMissingField.keep))
            .plainText,
        'Olá Ana {{sobrenome}}');
    expect(
      () => OdfDocument.fillTemplate(package, {'nome': 'Ana'},
          options: const OdfTemplateOptions(missing: OdfMissingField.error)),
      throwsA(isA<OdfException>()
          .having((e) => e.message, 'message', contains('sobrenome'))),
    );
  });

  test('formatação personalizada e lista de campos', () {
    final package = template(OdfRichTextDocument()
      ..paragraph('{{#itens}}')
      ..paragraph('{{descricao}}: {{total}}')
      ..paragraph('{{/itens}}'));
    expect(
        OdfDocument.templateFields(package), ['itens', 'descricao', 'total']);
    final read = fillText(
        package,
        data,
        OdfTemplateOptions(
            format: (v) => v is num ? v.toStringAsFixed(2) : '$v'));
    expect(read.plainText, 'Caneta: 1250.50\nCaderno: 1250.50');
  });

  test('bloco sem fechamento gera OdfException clara', () {
    final package = template(OdfRichTextDocument()..paragraph('{{#vip}}'));
    expect(() => OdfDocument.fillTemplate(package, data),
        throwsA(isA<OdfException>()));
  });

  test('modelo .ott gera documento .odt', () {
    final files = unzip(OdfDocument.createRichText(
        OdfRichTextDocument()..paragraph('Olá {{nome}}')));
    final archive = Archive();
    files['mimetype'] =
        utf8.encode('application/vnd.oasis.opendocument.text-template');
    files.forEach((name, bytes) =>
        archive.addFile(ArchiveFile(name, bytes.length, bytes)));
    final package = OdfDocument.open(ZipEncoder().encode(archive));
    expect(package.isTemplate, isTrue);
    final filled =
        OdfDocument.open(OdfDocument.fillTemplate(package, {'nome': 'Ana'}));
    expect(filled.isTemplate, isFalse);
    expect(OdfDocument.extractText(filled), 'Olá Ana');
  });
}

void encodingTests() {
  test('declaração us-ascii é trocada por UTF-8 ao regravar', () {
    final files = unzip(
        OdfDocument.createRichText(OdfRichTextDocument()..paragraph('{{x}}')));
    final content = utf8
        .decode(files['content.xml']!)
        .replaceFirst('<?xml version="1.0" encoding="UTF-8"?>',
            "<?xml version='1.0' encoding='us-ascii'?>")
        .replaceFirst('{{x}}', '&#x2022; {{x}}');
    files['content.xml'] = utf8.encode(content);
    final archive = Archive();
    files.forEach((name, bytes) =>
        archive.addFile(ArchiveFile(name, bytes.length, bytes)));
    final filled = OdfDocument.fillTemplate(
        OdfDocument.open(ZipEncoder().encode(archive)), {'x': 'ç'});
    final out = utf8.decode(unzip(filled)['content.xml']!);
    expect(out, startsWith("<?xml version='1.0' encoding='UTF-8'?>"));
    expect(OdfDocument.extractText(OdfDocument.open(filled)), '• ç');
  });
}
