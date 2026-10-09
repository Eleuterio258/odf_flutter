import 'dart:convert';

import 'package:odf_flutter/odf_flutter.dart';
import 'package:test/test.dart';

import 'advanced_test.dart' show png;

OdfRichTextDocument sample() => OdfRichTextDocument(
    metadata: const OdfMetadata(title: 'Relatório <1>', language: 'pt-BR'))
  ..heading('Título')
  ..rich([
    const OdfSpan('Normal, '),
    const OdfSpan('negrito', style: OdfTextStyle(bold: true)),
    const OdfSpan(', '),
    const OdfSpan('itálico', style: OdfTextStyle(italic: true)),
    const OdfSpan(', '),
    const OdfSpan('tachado', style: OdfTextStyle(strikethrough: true)),
    const OdfSpan(', '),
    const OdfSpan('código', style: OdfTextStyle(fontFamily: 'Liberation Mono')),
    const OdfSpan(' e '),
    const OdfLink('link', 'https://example.com'),
    const OdfSpan('. Símbolos: *a* _b_ <c> & [d]'),
    OdfNote.text('Uma nota.'),
  ])
  ..blocks.add(OdfList([
    OdfListItem.text('Primeiro'),
    OdfListItem([
      OdfParagraph.text('Segundo'),
      OdfList.of(['2.a', '2.b'], ordered: true)
    ]),
  ]))
  ..table([
    ['Nome', 'Valor'],
    ['A | B', '10'],
  ])
  ..pageBreak()
  ..heading('Seção 2', level: 2)
  ..paragraph('Linha 1\nLinha 2')
  ..image(png, description: 'Logo');

void main() {
  group('HTML', () {
    final html = OdfConvert.toHtml(sample());

    test('página completa com metadados e escape', () {
      expect(html, startsWith('<!DOCTYPE html>\n<html lang="pt-BR">'));
      expect(html, contains('<title>Relatório &lt;1&gt;</title>'));
      expect(html, contains('<h1>Título</h1>'));
      expect(html, contains('<strong>negrito</strong>'));
      expect(html, contains('<em>itálico</em>'));
      expect(html, contains('<s>tachado</s>'));
      expect(html, contains('<a href="https://example.com">link</a>'));
      expect(html, contains('Símbolos: *a* _b_ &lt;c&gt; &amp; [d]'));
    });

    test('listas, tabelas, notas, imagens e quebras', () {
      expect(
          html,
          contains(
              '<ul>\n<li>Primeiro</li>\n<li><p>Segundo</p>\n<ol>\n<li>2.a</li>'));
      expect(html, contains('<thead>\n<tr><th><strong>Nome</strong></th>'));
      expect(html, contains('<td>A | B</td>'));
      expect(html, contains('<sup><a href="#nota-1">1</a></sup>'));
      expect(html, contains('<li id="nota-1">Uma nota.</li>'));
      expect(html, contains('<img src="data:image/png;base64,'));
      expect(html, contains('<hr class="page-break">'));
      expect(html, contains('<p>Linha 1<br>Linha 2</p>'));
    });

    test('fragmento sem <html>', () {
      final fragment = OdfConvert.toHtml(OdfRichTextDocument()..paragraph('x'),
          fragment: true);
      expect(fragment, '<p>x</p>\n');
    });

    test('mesclagens viram colspan e rowspan', () {
      final doc = OdfRichTextDocument(blocks: [
        OdfTable([
          OdfTableRow([
            OdfTableCell.text('a', colSpan: 2, rowSpan: 2),
            OdfTableCell.text('b')
          ]),
          OdfTableRow([OdfTableCell.text('c')]),
        ]),
      ]);
      expect(OdfConvert.toHtml(doc, fragment: true),
          '<table>\n<tr><td colspan="2" rowspan="2">a</td><td>b</td></tr>\n<tr><td>c</td></tr>\n</table>\n');
    });
  });

  group('Markdown', () {
    final markdown = OdfConvert.toMarkdown(sample());

    test('exportação', () {
      expect(
          markdown,
          startsWith(
              '# Título\n\nNormal, **negrito**, *itálico*, ~~tachado~~, `código` e '
              '[link](https://example.com). Símbolos: \\*a\\* \\_b\\_ \\<c\\> & \\[d\\][^1]\n'));
      expect(
          markdown, contains('- Primeiro\n- Segundo\n\n  1. 2.a\n  2. 2.b\n'));
      expect(
          markdown,
          contains(
              '| **Nome** | **Valor** |\n| --- | --- |\n| A \\| B | 10 |'));
      expect(markdown, contains('---\n\n## Seção 2\n\nLinha 1\\\nLinha 2\n'));
      expect(markdown, contains('![Logo](data:image/png;base64,'));
      expect(markdown, endsWith('[^1]: Uma nota.\n'));
    });

    test('ida e volta preserva estrutura e formatação', () {
      final back = OdfConvert.fromMarkdown(markdown);
      expect(back.blocks.map((b) => b.runtimeType), [
        OdfHeading,
        OdfParagraph,
        OdfList,
        OdfTable,
        OdfPageBreak,
        OdfHeading,
        OdfParagraph,
        OdfImage,
      ]);
      final original = sample().blocks[1] as OdfParagraph;
      final read = back.blocks[1] as OdfParagraph;
      expect(read.inlines.whereType<OdfSpan>(),
          original.inlines.whereType<OdfSpan>());
      expect(read.inlines.whereType<OdfLink>().single,
          const OdfLink('link', 'https://example.com'));
      expect(read.inlines.whereType<OdfNote>().single.bodyText, 'Uma nota.');
      final list = back.blocks[2] as OdfList;
      expect(list.items[1].blocks[1],
          isA<OdfList>().having((l) => l.ordered, 'ordered', isTrue));
      final table = back.blocks[3] as OdfTable;
      expect(table.headerRows, 1);
      expect(table.rows[1].cells.map((c) => c.plainText), ['A | B', '10']);
      expect(back.blocks[6].plainText, 'Linha 1\nLinha 2');
      expect((back.blocks[7] as OdfImage).data.bytes, png);
      expect((back.blocks[7] as OdfImage).description, 'Logo');
    });

    test('leitura de Markdown escrito à mão', () {
      const md = r'''
Título Principal
================

# Introdução

Texto com **negrito _e itálico_**, `x = 1`, <https://dart.dev> e nome_de_variavel.
Continua na mesma linha.\
Depois de quebra.

> Citação

```dart
void main() {}
```

* um
* dois
    * dois.a

3. três
4. quatro

| Esq | Centro | Dir |
|:----|:------:|----:|
| a   | b      | c   |
''';
      final doc = OdfConvert.fromMarkdown(md);
      final blocks = doc.blocks;
      expect(
          blocks[0],
          isA<OdfHeading>()
              .having((h) => h.plainText, 'texto', 'Título Principal'));
      expect(blocks[1],
          isA<OdfHeading>().having((h) => h.plainText, 'texto', 'Introdução'));
      final p = blocks[2] as OdfParagraph;
      expect(
          p.plainText,
          'Texto com negrito e itálico, x = 1, https://dart.dev e nome_de_variavel. '
          'Continua na mesma linha.\nDepois de quebra.');
      expect(
          p.inlines
              .whereType<OdfSpan>()
              .firstWhere((s) => s.text == 'e itálico')
              .style,
          const OdfTextStyle(bold: true, italic: true));
      expect(p.inlines.whereType<OdfLink>().single.url, 'https://dart.dev');
      expect((blocks[3] as OdfParagraph).style.indentLeft, 1);
      expect(
          (blocks[4] as OdfParagraph).inlines.single,
          const OdfSpan('void main() {}',
              style: OdfTextStyle(fontFamily: 'Liberation Mono')));
      final bullets = blocks[5] as OdfList;
      expect(bullets.ordered, isFalse);
      expect((bullets.items[1].blocks[1] as OdfList).items.single.plainText,
          'dois.a');
      expect((blocks[6] as OdfList).ordered, isTrue);
      final table = blocks[7] as OdfTable;
      expect(
          table.rows[1].cells
              .map((c) => (c.blocks.single as OdfParagraph).style.align),
          [OdfTextAlign.start, OdfTextAlign.center, OdfTextAlign.end]);
    });

    test('quebra com dois espaços no fim da linha', () {
      expect(OdfConvert.fromMarkdown('a${' ' * 2}\nb').plainText, 'a\nb');
    });

    test('o documento importado é um ODT válido', () {
      final doc = OdfConvert.fromMarkdown('# Olá\n\n- a\n- b\n');
      final read = OdfDocument.readRichText(
          OdfDocument.open(OdfDocument.createRichText(doc)));
      expect(read.plainText, 'Olá\na\nb');
    });
  });

  group('CSV', () {
    OdfWorksheet sheet() => OdfWorksheet.fromValues('S', [
          ['Nome', 'Valor', 'Data', 'Ok'],
          ['Texto, com "aspas"', 1.5, DateTime(2026, 1, 2), true],
          ['Linha\nquebrada', 007, DateTime(2026, 1, 2, 3, 4), false],
          [
            '007',
            null,
            const OdfFormula('=B2*2', result: OdfNumberValue(3)),
            const OdfPercentageValue(0.25)
          ],
        ]);

    test('exportação RFC 4180', () {
      expect(
          OdfConvert.toCsv(sheet()),
          'Nome,Valor,Data,Ok\r\n'
          '"Texto, com ""aspas""",1.5,2026-01-02,TRUE\r\n'
          '"Linha\nquebrada",7,2026-01-02T03:04:00,FALSE\r\n'
          '007,,3,0.25\r\n');
    });

    test('vírgula decimal usa ponto e vírgula', () {
      expect(OdfConvert.toCsv(sheet(), decimalComma: true).split('\r\n')[1],
          '"Texto, com ""aspas""";1,5;2026-01-02;TRUE');
    });

    test('ida e volta com tipos', () {
      final back = OdfConvert.fromCsv(OdfConvert.toCsv(sheet()));
      expect(back.values, [
        ['Nome', 'Valor', 'Data', 'Ok'],
        ['Texto, com "aspas"', 1.5, DateTime(2026, 1, 2), true],
        ['Linha\nquebrada', 7, DateTime(2026, 1, 2, 3, 4), false],
        ['007', null, 3, 0.25],
      ]);
    });

    test('detecta separador e vírgula decimal', () {
      final back =
          OdfConvert.fromCsv('﻿a;b\n1,5;"x;y"\n10%;', decimalComma: true);
      expect(back.values, [
        ['a', 'b'],
        [1.5, 'x;y'],
        [0.1, null],
      ]);
    });

    test('sem inferência mantém texto', () {
      expect(OdfConvert.fromCsv('1,TRUE', inferTypes: false).values, [
        ['1', 'TRUE'],
      ]);
    });
  });

  group('JSON', () {
    final workbook = OdfWorkbook(sheets: [
      OdfWorksheet.fromValues('Vendas', [
        ['Produto', 'Qtd', 'Data', null],
        ['Caneta', 10, DateTime(2026, 3, 15), 'x'],
        [null, null, null, null],
        ['Caderno', 3, null, null],
      ]),
    ]);

    test('pasta inteira serializável com jsonEncode', () {
      final json = jsonEncode(OdfConvert.toJson(workbook));
      expect(
          json,
          contains(
              '"Vendas":[["Produto","Qtd","Data",null],["Caneta",10,"2026-03-15T00:00:00.000","x"]'));
    });

    test('registros com cabeçalho e de volta', () {
      final records = OdfConvert.toRecords(workbook.sheets.single);
      expect(records, [
        {
          'Produto': 'Caneta',
          'Qtd': 10,
          'Data': DateTime(2026, 3, 15),
          'D': 'x'
        },
        {'Produto': 'Caderno', 'Qtd': 3, 'Data': null, 'D': null},
      ]);
      final sheet = OdfConvert.fromRecords('Nova', records,
          headerStyle: OdfCellStyle.header);
      expect(sheet.values.first, ['Produto', 'Qtd', 'Data', 'D']);
      expect(sheet.at('A1')!.style, OdfCellStyle.header);
      expect(sheet.at('C2')!.value, OdfDateValue(DateTime(2026, 3, 15)));
    });
  });
}
