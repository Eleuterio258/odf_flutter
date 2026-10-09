import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:odf_flutter/odf_flutter.dart';
import 'package:odf_flutter/src/data/odf/odf_formula.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Cabeçalho PNG de 400x200 px (suficiente para detectar tipo e tamanho).
final png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
  0, 0, 0x01, 0x90, 0, 0, 0, 0xC8,
  8, 2, 0, 0, 0,
];

Map<String, List<int>> unzip(List<int> bytes) =>
    {for (final f in ZipDecoder().decodeBytes(bytes).files) f.name: f.content};

void main() {
  group('ODT rico', () {
    late OdfRichTextDocument doc;
    late OdfRichTextDocument read;

    setUp(() {
      doc = OdfRichTextDocument(
        metadata: OdfMetadata(
          title: 'Relatório',
          author: 'Equipe',
          keywords: ['odf', 'dart'],
          language: 'pt-BR',
          created: DateTime.utc(2026, 1, 2, 3, 4, 5),
        ),
        pageLayout: OdfPageLayout.a4.landscape,
        header: [
          OdfParagraph.text('Cabeçalho',
              style: const OdfTextStyle(italic: true))
        ],
        footer: [
          OdfParagraph([
            const OdfSpan('Página '),
            const OdfPageNumber(),
            const OdfSpan(' de '),
            const OdfPageCount()
          ], style: const OdfParagraphStyle(align: OdfTextAlign.center)),
        ],
      )
        ..heading('Título principal')
        ..rich([
          const OdfSpan('Normal, '),
          const OdfSpan('negrito', style: OdfTextStyle(bold: true)),
          const OdfSpan(' e '),
          OdfSpan('vermelho',
              style: OdfTextStyle(
                  italic: true, color: OdfColor.hex('#cc0000'), fontSize: 14)),
          const OdfSpan('. Veja '),
          const OdfLink('o site', 'https://example.com',
              style: OdfTextStyle(underline: true)),
        ],
            paragraphStyle: const OdfParagraphStyle(
                align: OdfTextAlign.justify, spaceAfter: 0.5, lineSpacing: 1.5))
        ..paragraph('  espaços   múltiplos\tcom tab\ne quebra')
        ..blocks.add(OdfList([
          OdfListItem.text('Primeiro'),
          OdfListItem([
            OdfParagraph.text('Segundo'),
            OdfList.of(['2.a', '2.b'], ordered: true),
          ]),
        ]))
        ..blocks.add(OdfTable(
            [
              OdfTableRow.text(['Nome', 'Valor', 'Obs'],
                  style: const OdfTextStyle(bold: true)),
              OdfTableRow([
                OdfTableCell.text('A', rowSpan: 2),
                OdfTableCell.text('10', colSpan: 2)
              ]),
              OdfTableRow([
                OdfTableCell.text('20'),
                OdfTableCell.text('x', backgroundColor: OdfColor.yellow)
              ]),
            ],
            headerRows: 1,
            columnWidths: [8, 4, 5]))
        ..pageBreak()
        ..heading('Segunda página', level: 2)
        ..image(png, description: 'Gráfico');

      final package = OdfDocument.open(OdfDocument.createRichText(doc));
      expect(package.type, OdfDocumentType.text);
      read = OdfDocument.readRichText(package);
    });

    test('preserva blocos e tipos', () {
      expect(read.blocks.map((b) => b.runtimeType).toList(), [
        OdfHeading,
        OdfParagraph,
        OdfParagraph,
        OdfList,
        OdfTable,
        OdfPageBreak,
        OdfHeading,
        OdfImage,
      ]);
    });

    test('preserva formatação de caracteres e links', () {
      final p = read.blocks[1] as OdfParagraph;
      expect(p.inlines, [
        const OdfSpan('Normal, '),
        const OdfSpan('negrito', style: OdfTextStyle(bold: true)),
        const OdfSpan(' e '),
        OdfSpan('vermelho',
            style: OdfTextStyle(
                italic: true, color: OdfColor.hex('#cc0000'), fontSize: 14)),
        const OdfSpan('. Veja '),
        const OdfLink('o site', 'https://example.com',
            style: OdfTextStyle(underline: true)),
      ]);
      expect(
          p.style,
          const OdfParagraphStyle(
              align: OdfTextAlign.justify, spaceAfter: 0.5, lineSpacing: 1.5));
    });

    test('preserva espaços, tabulações e quebras de linha', () {
      expect(
          read.blocks[2].plainText, '  espaços   múltiplos\tcom tab\ne quebra');
    });

    test('preserva listas aninhadas', () {
      final list = read.blocks[3] as OdfList;
      expect(list.ordered, isFalse);
      expect(list.items.first.plainText, 'Primeiro');
      final nested = list.items[1].blocks[1] as OdfList;
      expect(nested.ordered, isTrue);
      expect(nested.items.map((i) => i.plainText), ['2.a', '2.b']);
    });

    test('preserva tabela com cabeçalho, mesclagens e larguras', () {
      final table = read.blocks[4] as OdfTable;
      expect(table.headerRows, 1);
      expect(table.columnWidths, [8, 4, 5]);
      expect(table.rows[1].cells.map((c) => (c.colSpan, c.rowSpan)),
          [(1, 2), (2, 1)]);
      expect(table.rows[2].cells.map((c) => c.plainText), ['20', 'x']);
      expect(table.rows[2].cells[1].backgroundColor, OdfColor.yellow);
    });

    test('preserva quebra de página, título nível 2 e imagem', () {
      expect((read.blocks[6] as OdfHeading).level, 2);
      final image = read.blocks[7] as OdfImage;
      expect(image.data.mimeType, 'image/png');
      expect(image.data.pixelSize, (400, 200));
      expect(image.width, closeTo(400 * 2.54 / 96, 0.001));
      expect(image.description, 'Gráfico');
    });

    test('preserva cabeçalho, rodapé, página e metadados', () {
      expect(read.header.single.plainText, 'Cabeçalho');
      final footer = read.footer.single as OdfParagraph;
      expect(footer.inlines.whereType<OdfPageNumber>(), hasLength(1));
      expect(footer.inlines.whereType<OdfPageCount>(), hasLength(1));
      expect(read.pageLayout, OdfPageLayout.a4.landscape);
      expect(read.metadata.title, 'Relatório');
      expect(read.metadata.author, 'Equipe');
      expect(read.metadata.keywords, ['odf', 'dart']);
      expect(read.metadata.language, 'pt-BR');
      expect(read.metadata.created, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(read.metadata.generator, startsWith('odf_flutter'));
    });

    test(
        'gera pacote válido: mimetype primeiro e sem compressão, manifesto com imagem',
        () {
      final bytes = OdfDocument.createRichText(doc);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.first.name, 'mimetype');
      expect(archive.files.first.compression, CompressionType.none);
      final files = unzip(bytes);
      final manifest = utf8.decode(files['META-INF/manifest.xml']!);
      expect(
          manifest,
          contains(
              'manifest:full-path="Pictures/image1.png" manifest:media-type="image/png"'));
      expect(
          manifest, contains('manifest:full-path="/" manifest:version="1.2"'));
      for (final name in ['content.xml', 'styles.xml', 'meta.xml']) {
        expect(
            () => XmlDocument.parse(utf8.decode(files[name]!)), returnsNormally,
            reason: name);
      }
    });

    test('a API simples continua extraindo texto do ODT rico', () {
      final package = OdfDocument.open(OdfDocument.createRichText(doc));
      expect(OdfDocument.extractText(package), contains('negrito'));
    });

    test('quebras de página seguidas são preservadas', () {
      final doc = OdfRichTextDocument()
        ..paragraph('a')
        ..pageBreak()
        ..pageBreak()
        ..paragraph('b');
      final read = OdfDocument.readRichText(
          OdfDocument.open(OdfDocument.createRichText(doc)));
      expect(read.blocks.map((b) => b.runtimeType),
          [OdfParagraph, OdfPageBreak, OdfPageBreak, OdfParagraph]);
    });

    test('tabela dentro de lista é rejeitada', () {
      final invalid = OdfRichTextDocument(blocks: [
        OdfList([
          OdfListItem([
            OdfTable.fromValues([
              ['x']
            ])
          ]),
        ]),
      ]);
      expect(() => OdfDocument.createRichText(invalid),
          throwsA(isA<OdfException>()));
    });
  });

  group('ODS tipado', () {
    late OdfWorkbook read;

    setUp(() {
      final sheet = OdfWorksheet.fromValues(
          'Vendas',
          [
            ['Produto', 'Qtd', 'Preço', 'Desconto', 'Data', 'Pago'],
            [
              'Caneta',
              10,
              const OdfCurrencyValue(2.5),
              const OdfPercentageValue(0.1),
              DateTime(2026, 3, 15),
              true
            ],
            [
              'Caderno',
              3,
              const OdfCurrencyValue(12.9),
              const OdfPercentageValue(0),
              DateTime(2026, 3, 16, 14, 30),
              false
            ],
          ],
          headerStyle: OdfCellStyle.header)
        ..columnWidths[0] = 5.0
        ..set('A5', 'Total', style: const OdfCellStyle(bold: true))
        ..set('B5', const OdfFormula('=SUM(B2:B3)', result: OdfNumberValue(13)))
        ..set('C5', const OdfFormula('=SUMPRODUCT(B2:B3,C2:C3)'))
        ..set('D7', const Duration(hours: 1, minutes: 30))
        ..set('E7', 1234.5678,
            style: const OdfCellStyle(
                numberFormat: OdfNumberFormat.number(decimals: 2)));
      sheet.rows[4].height = 1.2;
      sheet.at('A5')!.note = 'Linha de total';
      sheet.rows
        ..add(OdfRow([
          OdfCell(const OdfStringValue('Mesclada'), colSpan: 3, rowSpan: 2)
        ]))
        ..add(OdfRow.values([null, null, null, 'fim']));

      final workbook = OdfWorkbook(
        sheets: [
          sheet,
          OdfWorksheet.fromValues('Outra aba', [
            ['=texto, não fórmula']
          ])
        ],
        metadata: const OdfMetadata(title: 'Planilha'),
      );
      final package = OdfDocument.open(OdfDocument.createWorkbook(workbook));
      expect(package.type, OdfDocumentType.spreadsheet);
      read = OdfDocument.readWorkbook(package);
    });

    test('preserva abas e valores tipados', () {
      expect(read.sheets.map((s) => s.name), ['Vendas', 'Outra aba']);
      final sheet = read.sheet('Vendas')!;
      expect(sheet.values[1],
          ['Caneta', 10, 2.5, 0.1, DateTime(2026, 3, 15), true]);
      expect(sheet.at('C2')!.value, const OdfCurrencyValue(2.5));
      expect(sheet.at('D3')!.value, const OdfPercentageValue(0));
      expect(sheet.at('E3')!.value,
          OdfDateValue(DateTime(2026, 3, 16, 14, 30), includeTime: true));
      expect(sheet.at('F3')!.value, const OdfBooleanValue(false));
      expect(sheet.at('D7')!.value,
          const OdfTimeValue(Duration(hours: 1, minutes: 30)));
      expect(read.sheet('Outra aba')!.at('A1')!.value,
          const OdfStringValue('=texto, não fórmula'));
    });

    test('preserva fórmulas e resultado em cache', () {
      final sheet = read.sheet('Vendas')!;
      expect(sheet.at('B5')!.value,
          const OdfFormula('=SUM(B2:B3)', result: OdfNumberValue(13)));
      expect(
          sheet.at('C5')!.value, const OdfFormula('=SUMPRODUCT(B2:B3,C2:C3)'));
    });

    test('preserva estilos, formatos, nota, larguras, alturas e mesclagem', () {
      final sheet = read.sheet('Vendas')!;
      expect(sheet.at('A1')!.style, OdfCellStyle.header);
      expect(sheet.at('A5')!.style, const OdfCellStyle(bold: true));
      expect(sheet.at('A5')!.note, 'Linha de total');
      expect(sheet.at('C2')!.style, isNull,
          reason: 'formato padrão de moeda não vira estilo');
      expect(sheet.at('E7')!.style!.numberFormat,
          const OdfNumberFormat.number(decimals: 2));
      expect(sheet.columnWidths[0], 5.0);
      expect(sheet.rows[4].height, 1.2);
      final merged = sheet.rows[7].cells.single;
      expect((merged.colSpan, merged.rowSpan), (3, 2));
    });

    test('grava OpenFormula e formatos numéricos no XML', () {
      final workbook = OdfWorkbook(sheets: [
        OdfWorksheet('S')
          ..set('A1', const OdfFormula('=IF(Dados!A1>10,"a,b",SUM(\$B\$1:B2))'))
          ..set('A2', DateTime(2026, 1, 1)),
      ]);
      final content = utf8
          .decode(unzip(OdfDocument.createWorkbook(workbook))['content.xml']!);
      expect(
          content,
          contains(
              'table:formula="of:=IF([\$Dados.A1]>10;&quot;a,b&quot;;SUM([.\$B\$1:.B2]))"'));
      expect(content, contains('<number:date-style'));
      expect(content, contains('office:date-value="2026-01-01"'));
      expect(content, contains('<text:p>01/01/2026</text:p>'));
    });

    test('ignora linhas e colunas vazias repetidas (arquivos do LibreOffice)',
        () {
      const content = '<?xml version="1.0" encoding="UTF-8"?>'
          '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
          'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
          'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.3">'
          '<office:body><office:spreadsheet><table:table table:name="P">'
          '<table:table-column table:number-columns-repeated="1024"/>'
          '<table:table-row><table:table-cell office:value-type="float" office:value="1"><text:p>1</text:p>'
          '</table:table-cell><table:table-cell table:number-columns-repeated="1023"/></table:table-row>'
          '<table:table-row table:number-rows-repeated="1048575"><table:table-cell table:number-columns-repeated="1024"/>'
          '</table:table-row></table:table></office:spreadsheet></office:body></office:document-content>';
      final bytes = OdfRepositoryImpl()
          .create(type: OdfDocumentType.spreadsheet, contentXml: content);
      final sheet =
          OdfDocument.readWorkbook(OdfDocument.open(bytes)).sheets.single;
      expect(sheet.values, [
        [1],
      ]);
    });
  });

  group('Conversor de fórmulas', () {
    final cases = {
      '=SUM(A1:A3)': 'of:=SUM([.A1:.A3])',
      '=A1+\$B\$2*2': 'of:=[.A1]+[.\$B\$2]*2',
      '=Dados!C3': 'of:=[\$Dados.C3]',
      "='Minha aba'!A1:B2": "of:=[\$'Minha aba'.A1:.B2]",
      '=LOG10(A1)': 'of:=LOG10([.A1])',
      '=IF(A1="x,y";1;2)': 'of:=IF([.A1]="x,y";1;2)',
      '=CONCATENATE("A1";B1)': 'of:=CONCATENATE("A1";[.B1])',
      '=SUM(A:A)': 'of:=SUM([.A:.A])',
      '=SUM(\$B:\$D,2:3)': 'of:=SUM([.\$B:.\$D];[.2:.3])',
      '=SUM(Dados!C:C)': 'of:=SUM([\$Dados.C:.C])',
      '=SUM(Plan1:Plan3!A1)': 'of:=SUM([\$Plan1.A1:\$Plan3.A1])',
      '=ROUND(1,5;0)': 'of:=ROUND(1.5;0)',
      '=ROUND(1.5,0)+1E3': 'of:=ROUND(1.5;0)+1E3',
      '=A1*12': 'of:=[.A1]*12',
    };
    cases.forEach((input, expected) {
      test(input, () {
        expect(OdfFormulaConverter.toOpenFormula(input), expected);
      });
    });

    test('volta para o estilo de planilha', () {
      expect(
          OdfFormulaConverter.fromOpenFormula(
              'of:=SUM([.A1:.A3];[\$Dados.C3])'),
          '=SUM(A1:A3,Dados!C3)');
      expect(OdfFormulaConverter.fromOpenFormula("of:=[\$'Minha aba'.A1:.B2]"),
          "='Minha aba'!A1:B2");
      expect(OdfFormulaConverter.fromOpenFormula('of:=SUM([.A:.A];[.2:.3])'),
          '=SUM(A:A,2:3)');
      expect(
          OdfFormulaConverter.fromOpenFormula(
              'of:=SUM([\$Plan1.A1:\$Plan3.A1])'),
          '=SUM(Plan1:Plan3!A1)');
    });
  });

  group('ODP', () {
    test('preserva slides, textos, imagens, formas, fundo e notas', () {
      final presentation = OdfPresentation(
        metadata: const OdfMetadata(title: 'Apresentação'),
        slides: [
          OdfSlide.bullets(
              'Agenda', ['Contexto', 'Proposta', 'Próximos passos'],
              notes: 'Falar devagar'),
          OdfSlide(
            title: 'Resultados',
            background: OdfColor.hex('#f0f0ff'),
            elements: [
              OdfTextBox([
                OdfParagraph.text('Crescimento',
                    style: const OdfTextStyle(bold: true, fontSize: 28)),
                OdfList.of(['Q1: 10%', 'Q2: 15%'], ordered: true),
              ]),
              OdfSlideImage.bytes(png),
            ],
          ),
          OdfSlide(elements: [
            OdfShape(OdfShapeKind.ellipse,
                frame: const OdfFrame(2, 2, 6, 4),
                fill: OdfColor.hex('#3366ff'),
                text: 'Destaque'),
            OdfShape(OdfShapeKind.rectangle,
                frame: const OdfFrame(10, 2, 6, 4), stroke: OdfColor.black),
          ]),
        ],
      );
      final package =
          OdfDocument.open(OdfDocument.createPresentation(presentation));
      expect(package.type, OdfDocumentType.presentation);
      final read = OdfDocument.readPresentation(package);

      expect(read.size, OdfSlideSize.widescreen);
      expect(read.metadata.title, 'Apresentação');
      expect(read.slides, hasLength(3));

      final agenda = read.slides[0];
      expect(agenda.title, 'Agenda');
      expect(agenda.notes, 'Falar devagar');
      final bullets =
          (agenda.elements.single as OdfTextBox).blocks.single as OdfList;
      expect(bullets.items.map((i) => i.plainText),
          ['Contexto', 'Proposta', 'Próximos passos']);

      final results = read.slides[1];
      expect(results.background, OdfColor.hex('#f0f0ff'));
      final box = results.elements[0] as OdfTextBox;
      final heading = box.blocks[0] as OdfParagraph;
      expect((heading.inlines.single as OdfSpan).style,
          const OdfTextStyle(bold: true, fontSize: 28));
      expect((box.blocks[1] as OdfList).ordered, isTrue);
      final image = results.elements[1] as OdfSlideImage;
      expect(image.image.mimeType, 'image/png');
      // Duas colunas automáticas; a imagem 2:1 é centralizada na sua coluna.
      expect(image.frame!.width / image.frame!.height, closeTo(2, 0.01));
      expect(box.frame!.x, lessThan(image.frame!.x));

      final shapes = read.slides[2].elements.cast<OdfShape>();
      expect(shapes.map((s) => s.kind),
          [OdfShapeKind.ellipse, OdfShapeKind.rectangle]);
      expect(shapes.first.fill, OdfColor.hex('#3366ff'));
      expect(shapes.first.stroke, isNull);
      expect(shapes.first.text, 'Destaque');
      expect(shapes.last.fill, isNull);
      expect(shapes.last.stroke, OdfColor.black);
      expect(shapes.last.frame, const OdfFrame(10, 2, 6, 4));
    });
  });

  group('Erros', () {
    test('bytes que não são ZIP geram OdfException', () {
      expect(
          () => OdfDocument.open([1, 2, 3, 4]), throwsA(isA<OdfException>()));
    });

    test('ler planilha como texto gera OdfException', () {
      final package =
          OdfDocument.open(OdfDocument.createWorkbook(OdfWorkbook()));
      expect(() => OdfDocument.readRichText(package),
          throwsA(isA<OdfException>()));
    });

    test('abas com nome repetido são rejeitadas', () {
      final workbook =
          OdfWorkbook(sheets: [OdfWorksheet('A'), OdfWorksheet('A')]);
      expect(() => OdfDocument.createWorkbook(workbook), throwsArgumentError);
    });
  });

  group('Utilitários', () {
    test('OdfCellRef converte notação A1', () {
      expect(OdfCellRef.parse('A1'), const OdfCellRef(0, 0));
      expect(OdfCellRef.parse('\$AB\$12'), const OdfCellRef(11, 27));
      expect(OdfCellRef.columnName(27), 'AB');
      expect(const OdfCellRef(0, 701).toString(), 'ZZ1');
    });

    test('OdfColor aceita formatos curtos', () {
      expect(OdfColor.hex('#fff'), OdfColor.white);
      expect(OdfColor.tryParse('xyz'), isNull);
    });
  });
}
