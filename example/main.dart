import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:odf_flutter/odf_flutter.dart';

/// Gera exemplo.odt, exemplo.ods e exemplo.odp e os relê.
/// Uso: dart run example/main.dart [pasta-de-saída]
void main(List<String> args) {
  final dir = args.isEmpty ? '.' : args.first;
  final logo = gradientPng(240, 120);

  // ------------------------------------------------------------------ ODT
  final text = OdfRichTextDocument(
    metadata: OdfMetadata(
        title: 'Relatório trimestral',
        author: 'odf_flutter',
        language: 'pt-BR'),
    header: [
      OdfParagraph.text('Relatório trimestral',
          style: const OdfTextStyle(italic: true))
    ],
    footer: [
      OdfParagraph(
        [
          const OdfSpan('Página '),
          const OdfPageNumber(),
          const OdfSpan(' de '),
          const OdfPageCount()
        ],
        style: const OdfParagraphStyle(align: OdfTextAlign.center),
      ),
    ],
  )
    ..heading('Resumo')
    ..rich([
      const OdfSpan('As vendas cresceram '),
      OdfSpan('15%',
          style: OdfTextStyle(bold: true, color: OdfColor.hex('#2e7d32'))),
      const OdfSpan(' no trimestre. Detalhes em '),
      const OdfLink('example.com', 'https://example.com',
          style: OdfTextStyle(underline: true)),
      const OdfSpan('.'),
    ],
        paragraphStyle: const OdfParagraphStyle(
            align: OdfTextAlign.justify, spaceAfter: 0.3))
    ..bullets(['Novos clientes', 'Retenção maior', 'Custos estáveis'])
    ..table([
      ['Mês', 'Receita', 'Meta'],
      ['Janeiro', 'R\$ 10.000', 'R\$ 9.000'],
      ['Fevereiro', 'R\$ 12.500', 'R\$ 11.000'],
    ], columnWidths: [
      7,
      5,
      5
    ])
    ..image(logo, description: 'Logotipo')
    ..pageBreak()
    ..heading('Próximos passos', level: 2)
    ..numbered(['Expandir equipe', 'Lançar produto']);

  // ------------------------------------------------------------------ ODS
  final sheet = OdfWorksheet.fromValues(
      'Vendas',
      [
        ['Produto', 'Qtd', 'Preço', 'Desconto', 'Data'],
        [
          'Caneta',
          10,
          const OdfCurrencyValue(2.5),
          const OdfPercentageValue(0.1),
          DateTime(2026, 3, 15)
        ],
        [
          'Caderno',
          3,
          const OdfCurrencyValue(12.9),
          const OdfPercentageValue(0.05),
          DateTime(2026, 3, 16)
        ],
      ],
      headerStyle: OdfCellStyle.header)
    ..columnWidths.addAll({0: 4.0, 4: 3.0})
    ..set('A5', 'Total', style: const OdfCellStyle(bold: true))
    ..set('B5', const OdfFormula('=SUM(B2:B3)'))
    ..set('C5', const OdfFormula('=SUMPRODUCT(B2:B3,C2:C3)'),
        style: const OdfCellStyle(
            bold: true, numberFormat: OdfNumberFormat.currency('BRL')));
  final workbook = OdfWorkbook(
      sheets: [sheet], metadata: const OdfMetadata(title: 'Vendas'));

  // ------------------------------------------------------------------ ODP
  final presentation = OdfPresentation(
    metadata: const OdfMetadata(title: 'Apresentação'),
    slides: [
      OdfSlide.bullets('Agenda', ['Resultados', 'Próximos passos'],
          notes: 'Abrir com os números.'),
      OdfSlide(title: 'Resultados', elements: [
        OdfTextBox([
          OdfParagraph.text('Crescimento de 15%',
              style: const OdfTextStyle(bold: true)),
          OdfList.of(['Janeiro: R\$ 10 mil', 'Fevereiro: R\$ 12,5 mil'],
              ordered: true),
        ]),
        OdfSlideImage.bytes(logo),
      ]),
      OdfSlide(background: OdfColor.hex('#eef3ff'), elements: [
        OdfShape(OdfShapeKind.ellipse,
            frame: const OdfFrame(9, 4, 10, 6),
            fill: OdfColor.hex('#3366ff'),
            text: 'Obrigado!',
            textStyle: const OdfTextStyle(
                bold: true, fontSize: 32, color: OdfColor.white)),
      ]),
    ],
  );

  // ------------------------------------------------------------- modelos
  // Normalmente o modelo é um arquivo feito no LibreOffice; aqui ele é gerado.
  final recibo =
      OdfDocument.open(OdfDocument.createRichText(OdfRichTextDocument()
        ..heading('Recibo de {{cliente.nome}}')
        ..paragraph('Emitido em {{data}}.\n{{obs}}')
        ..table([
          ['#', 'Item', 'Qtd'],
          ['{{@index}}', '{{itens.descricao}}', '{{itens.qtd}}'],
        ])
        ..paragraph('{{#vip}}')
        ..paragraph('Cliente VIP: desconto aplicado.',
            style: const OdfTextStyle(bold: true))
        ..paragraph('{{/vip}}')));
  final planilha =
      OdfDocument.open(OdfDocument.createWorkbook(OdfWorkbook(sheets: [
    OdfWorksheet.fromValues(
        'Itens',
        [
          ['Item', 'Qtd', 'Data'],
          ['{{itens.descricao}}', '{{itens.qtd}}', '{{data}}'],
        ],
        headerStyle: OdfCellStyle.header),
  ])));
  final dados = {
    'cliente': {'nome': 'Ana Souza'},
    'data': DateTime(2026, 10, 9),
    'obs': 'Pagamento à vista.\tObrigado!',
    'vip': true,
    'itens': [
      {'descricao': 'Caneta', 'qtd': 10},
      {'descricao': 'Caderno', 'qtd': 3},
    ],
  };
  print('Campos do modelo: ${OdfDocument.templateFields(recibo)}');

  final outputs = {
    'exemplo.odt': OdfDocument.createRichText(text),
    'exemplo.ods': OdfDocument.createWorkbook(workbook),
    'exemplo.odp': OdfDocument.createPresentation(presentation),
    'recibo.odt': OdfDocument.fillTemplate(recibo, dados),
    'itens.ods': OdfDocument.fillTemplate(planilha, dados),
  };
  outputs.forEach((name, bytes) {
    File('$dir/$name').writeAsBytesSync(bytes);
    print('Criado $name (${bytes.length} bytes)');
  });

  // Leitura estruturada.
  final odt =
      OdfDocument.readRichText(OdfDocument.open(outputs['exemplo.odt']!));
  print('ODT: ${odt.blocks.length} blocos; título "${odt.metadata.title}"');
  final ods =
      OdfDocument.readWorkbook(OdfDocument.open(outputs['exemplo.ods']!));
  print('ODS: ${ods.sheets.first.values}');
  final odp =
      OdfDocument.readPresentation(OdfDocument.open(outputs['exemplo.odp']!));
  print('ODP: ${odp.slides.map((s) => s.title ?? '(sem título)').join(', ')}');
}

/// PNG RGB com degradê, gerado sem dependências extras.
List<int> gradientPng(int width, int height) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filtro "none"
    for (var x = 0; x < width; x++) {
      raw.add([51 + 150 * x ~/ width, 102, 255 - 120 * y ~/ height]);
    }
  }

  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    return [..._u32(data.length), ...body, ..._u32(getCrc32(body))];
  }

  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ...chunk('IHDR', [..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]),
    ...chunk('IDAT', const ZLibEncoder().encode(raw.takeBytes())),
    ...chunk('IEND', const []),
  ];
}

List<int> _u32(int v) =>
    [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
