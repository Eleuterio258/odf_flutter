# odf_flutter

Biblioteca Dart e Flutter para criar, ler, preencher e converter documentos OpenDocument: textos (`.odt`), planilhas (`.ods`) e apresentações (`.odp`). Funciona na Dart VM e em Flutter (Android, iOS, desktop e Web) sem LibreOffice nem plugins nativos.

## Sumário

- [Instalação](#instalação)
- [Conceitos](#conceitos)
- [Documentos de texto (ODT)](#documentos-de-texto-odt)
- [Planilhas (ODS)](#planilhas-ods)
- [Apresentações (ODP)](#apresentações-odp)
- [Abrir e ler arquivos](#abrir-e-ler-arquivos)
- [Preencher modelos](#preencher-modelos)
- [Converter para HTML, Markdown, CSV e JSON](#converter-para-html-markdown-csv-e-json)
- [Salvar e abrir arquivos no Flutter](#salvar-e-abrir-arquivos-no-flutter)
- [Erros](#erros)
- [Limitações](#limitações)

## Instalação

```yaml
dependencies:
  odf_flutter:
    git: https://github.com/Eleuterio258/odf_flutter.git
```

```dart
import 'package:odf_flutter/odf_flutter.dart';
```

## Conceitos

Toda a API passa por duas classes estáticas:

- `OdfDocument`: cria, abre, lê e preenche documentos.
- `OdfConvert`: converte para outros formatos e de volta.

A biblioteca nunca lê nem grava arquivos: ela recebe e devolve bytes (`List<int>`). Gravar no disco, compartilhar ou enviar fica a cargo da sua aplicação (veja [Salvar e abrir arquivos](#salvar-e-abrir-arquivos-no-flutter)).

As medidas (margens, larguras, posições) são em **centímetros**, e os tamanhos de fonte em **pontos**.

## Documentos de texto (ODT)

### Documento simples

```dart
final doc = OdfRichTextDocument()
  ..heading('Relatório mensal')
  ..paragraph('Este relatório resume os resultados do mês.')
  ..bullets(['Vendas', 'Clientes', 'Custos'])
  ..numbered(['Revisar metas', 'Enviar à diretoria'])
  ..table([
    ['Mês', 'Receita'],
    ['Janeiro', 'R\$ 10.000'],
    ['Fevereiro', 'R\$ 12.500'],
  ]);

final List<int> bytes = OdfDocument.createRichText(doc);
```

Na tabela, a primeira linha vira cabeçalho (em negrito e repetida em cada página). Use `header: false` para desligar.

### Formatação de texto

Um parágrafo com formatações diferentes é montado com trechos (`OdfSpan`):

```dart
doc.rich([
  const OdfSpan('Texto normal, '),
  const OdfSpan('negrito', style: OdfTextStyle(bold: true)),
  const OdfSpan(', '),
  const OdfSpan('itálico e sublinhado', style: OdfTextStyle(italic: true, underline: true)),
  const OdfSpan(', H'),
  const OdfSpan('2', style: OdfTextStyle(subscript: true)),
  const OdfSpan('O e '),
  OdfSpan('vermelho em 14pt', style: OdfTextStyle(color: OdfColor.hex('#c62828'), fontSize: 14)),
  const OdfSpan('. Veja o '),
  const OdfLink('site', 'https://example.com'),
  const OdfSpan('.'),
]);
```

`OdfTextStyle` aceita `bold`, `italic`, `underline`, `strikethrough`, `superscript`, `subscript`, `fontSize`, `fontFamily`, `color` e `backgroundColor`.

Dentro do texto, `\n` vira quebra de linha e `\t` vira tabulação. Espaços repetidos são mantidos.

### Formatação de parágrafo

```dart
doc.paragraph(
  'Parágrafo justificado, com recuo e espaçamento de 1,5.',
  paragraphStyle: const OdfParagraphStyle(
    align: OdfTextAlign.justify,
    firstLineIndent: 1.25, // cm
    spaceAfter: 0.3,       // cm
    lineSpacing: 1.5,
  ),
);
```

### Títulos, listas aninhadas e tabelas avançadas

```dart
doc
  ..heading('Capítulo 1')
  ..heading('Seção 1.1', level: 2) // níveis 1 a 6
  ..blocks.add(OdfList([
    OdfListItem.text('Item simples'),
    OdfListItem([
      OdfParagraph.text('Item com sublista'),
      OdfList.of(['a', 'b'], ordered: true),
    ]),
  ]))
  ..blocks.add(OdfTable(
    [
      OdfTableRow.text(['Produto', 'Jan', 'Fev'], style: const OdfTextStyle(bold: true)),
      OdfTableRow([
        OdfTableCell.text('Caneta', rowSpan: 2), // mescla duas linhas
        OdfTableCell.text('10'),
        OdfTableCell.text('12', backgroundColor: OdfColor.yellow),
      ]),
      OdfTableRow([OdfTableCell.text('Total do bimestre: 22', colSpan: 2)]), // mescla duas colunas
    ],
    headerRows: 1,
    columnWidths: [8, 4, 4], // cm
  ));
```

### Imagens, notas e quebras de página

```dart
doc
  ..image(pngBytes, description: 'Gráfico de vendas') // PNG, JPEG, GIF, BMP, WebP ou SVG
  ..image(pngBytes, width: 5) // altura calculada pela proporção
  ..rich([
    const OdfSpan('Dado citado'),
    OdfNote.text('Fonte: IBGE, 2025.'), // nota de rodapé numerada automaticamente
    const OdfSpan(' e outro'),
    OdfNote.text('Ver anexo.', endnote: true), // nota de fim
  ])
  ..pageBreak();
```

Sem `width` e `height`, a imagem usa o tamanho em pixels (96 DPI), limitado à largura útil da página.

### Página, cabeçalho, rodapé e metadados

```dart
final doc = OdfRichTextDocument(
  pageLayout: OdfPageLayout.a4.landscape, // ou OdfPageLayout.letter, ou medidas próprias
  metadata: OdfMetadata(
    title: 'Relatório mensal',
    author: 'Equipe financeira',
    keywords: ['vendas', '2026'],
    language: 'pt-BR',
  ),
  header: [OdfParagraph.text('Empresa XYZ', style: const OdfTextStyle(italic: true))],
  footer: [
    OdfParagraph(
      [const OdfSpan('Página '), const OdfPageNumber(), const OdfSpan(' de '), const OdfPageCount()],
      style: const OdfParagraphStyle(align: OdfTextAlign.center),
    ),
  ],
);
```

### API simples

Para casos rápidos, a API mais antiga continua disponível:

```dart
final bytes = OdfDocument.createText(
  OdfTextDocument(title: 'Aviso', paragraphs: ['Primeiro parágrafo', 'Segundo parágrafo']),
);
```

## Planilhas (ODS)

### A partir de valores

```dart
final sheet = OdfWorksheet.fromValues(
  'Vendas',
  [
    ['Produto', 'Qtd', 'Preço', 'Desconto', 'Data', 'Pago'],
    ['Caneta', 10, const OdfCurrencyValue(2.5), const OdfPercentageValue(0.1), DateTime(2026, 3, 15), true],
    ['Caderno', 3, const OdfCurrencyValue(12.9), const OdfPercentageValue(0.05), DateTime(2026, 3, 16), false],
  ],
  headerStyle: OdfCellStyle.header, // negrito, fundo cinza e borda
);

final bytes = OdfDocument.createWorkbook(OdfWorkbook(sheets: [sheet]));
```

Os valores Dart viram o tipo certo da planilha:

| Valor | Na planilha |
| --- | --- |
| `String` | Texto |
| `int`, `double` | Número |
| `bool` | Verdadeiro/falso |
| `DateTime` | Data (com hora, se a hora não for zero) |
| `Duration` | Hora |
| `OdfCurrencyValue(2.5, currency: 'BRL')` | Moeda (BRL, USD, EUR, GBP, JPY, AOA, MZN...) |
| `OdfPercentageValue(0.1)` | 10% |
| `OdfFormula('=SUM(B2:B3)')` | Fórmula |
| `null` | Célula vazia |

### Células pela referência

```dart
sheet
  ..set('A5', 'Total', style: const OdfCellStyle(bold: true))
  ..set('B5', const OdfFormula('=SUM(B2:B3)'))
  ..set('C5', const OdfFormula('=SUMPRODUCT(B2:B3,C2:C3)'),
      style: const OdfCellStyle(numberFormat: OdfNumberFormat.currency('BRL')));

print(sheet.at('B2')!.value); // OdfNumberValue(10)
```

`set` cria as linhas e células que faltarem.

### Fórmulas

Escreva as fórmulas como no LibreOffice ou no Excel, em inglês: `SUM`, `IF`, `AVERAGE` e assim por diante. A biblioteca converte para o formato do ODF.

```dart
const OdfFormula('=IF(A1>10,"alto","baixo")');
const OdfFormula('=SUM(Dados!A:A)');        // coluna inteira de outra aba
const OdfFormula("=SUM('Minha aba'!B2:B9)"); // aba com espaço: use aspas simples
const OdfFormula('=SUM(Plan1:Plan3!A1)');    // a mesma célula em várias abas
const OdfFormula('=ROUND(1,5;0)');           // com ";" entre argumentos, a vírgula é decimal
```

A biblioteca não calcula fórmulas; o LibreOffice calcula ao abrir. Para que o valor já apareça em leitores que não recalculam, informe o resultado: `OdfFormula('=SUM(B2:B3)', result: OdfNumberValue(13))`.

### Formatação, larguras, mesclagem e notas

```dart
sheet
  ..columnWidths[0] = 5.0 // coluna A com 5 cm
  ..set('E2', 1234.5678,
      style: OdfCellStyle(
        numberFormat: const OdfNumberFormat.number(decimals: 2),
        align: OdfTextAlign.end,
        color: OdfColor.hex('#1565c0'),
        border: true,
      ))
  ..set('F2', DateTime(2026, 3, 15, 14, 30),
      style: const OdfCellStyle(numberFormat: OdfNumberFormat.date('dd/MM/yyyy HH:mm')));

sheet.rows[0].height = 1.0; // altura da linha 1 em cm

final title = sheet.set('A8', 'Título mesclado em 3 colunas');
title.colSpan = 3;
title.note = 'Comentário exibido na célula';
```

Numa mesclagem, `cells[i]` continua sendo sempre a coluna `i`. As posições cobertas existem na lista, mas não aparecem. Para obter a célula visível de uma posição, use `sheet.visibleAt('B8')`.

### Várias abas

```dart
final workbook = OdfWorkbook(metadata: const OdfMetadata(title: 'Vendas 2026'));
final janeiro = workbook.addSheet('Janeiro')..set('A1', 'Receita');
final resumo = workbook.addSheet('Resumo')..set('A1', const OdfFormula('=Janeiro!B2*12'));
```

## Apresentações (ODP)

```dart
final presentation = OdfPresentation(
  size: OdfSlideSize.widescreen, // 16:9; ou OdfSlideSize.standard (4:3)
  metadata: const OdfMetadata(title: 'Resultados'),
  slides: [
    OdfSlide.bullets('Agenda', ['Resultados', 'Próximos passos'],
        notes: 'Anotação visível só para quem apresenta.'),
    OdfSlide(title: 'Resultados', elements: [
      OdfTextBox([
        OdfParagraph.text('Crescimento de 15%', style: const OdfTextStyle(bold: true)),
        OdfList.of(['Janeiro: R\$ 10 mil', 'Fevereiro: R\$ 12,5 mil'], ordered: true),
      ]),
      OdfSlideImage.bytes(pngBytes),
    ]),
    OdfSlide(background: OdfColor.hex('#eef3ff'), elements: [
      OdfShape(
        OdfShapeKind.ellipse,
        frame: const OdfFrame(9, 4, 10, 6), // x, y, largura, altura em cm
        fill: OdfColor.hex('#3366ff'),
        text: 'Obrigado!',
        textStyle: const OdfTextStyle(bold: true, fontSize: 32, color: OdfColor.white),
      ),
    ]),
  ],
);

final bytes = OdfDocument.createPresentation(presentation);
```

Elementos sem `frame` são posicionados sozinhos: um ocupa a área toda, dois ficam lado a lado, três ou mais são empilhados. Imagens mantêm a proporção.

## Abrir e ler arquivos

```dart
final package = OdfDocument.open(bytes);

print(package.type);       // OdfDocumentType.text, .spreadsheet, .presentation...
print(package.version);    // '1.2', '1.3'...
print(package.isTemplate); // true para .ott, .ots e .otp

switch (package.type) {
  case OdfDocumentType.text:
    final doc = OdfDocument.readRichText(package);
    print(doc.metadata.title);
    for (final block in doc.blocks) {
      if (block is OdfHeading) print('Título ${block.level}: ${block.plainText}');
      if (block is OdfTable) print('Tabela com ${block.rows.length} linhas');
    }
  case OdfDocumentType.spreadsheet:
    final workbook = OdfDocument.readWorkbook(package);
    final sheet = workbook.sheet('Vendas')!;
    print(sheet.values); // List<List<Object?>> com valores Dart
    print(sheet.at('C2')!.value.dartValue);
  case OdfDocumentType.presentation:
    final presentation = OdfDocument.readPresentation(package);
    for (final slide in presentation.slides) {
      print('${slide.title}: ${slide.elements.length} elementos');
    }
  default:
    break;
}
```

Para obter só o texto, sem estrutura:

```dart
final text = OdfDocument.extractText(package); // um parágrafo por linha
```

Os arquivos internos do pacote também ficam acessíveis:

```dart
if (package.contains('settings.xml')) {
  final xml = utf8.decode(package.file('settings.xml')); // import 'dart:convert';
}
```

## Preencher modelos

Crie o documento no LibreOffice (ODT, ODS ou ODP) com campos entre chaves duplas e preencha pelo código. Estilos, imagens, cabeçalhos e o restante do arquivo ficam como estavam.

**Modelo (`recibo.odt`):**

```text
Recibo de {{cliente.nome}}
Emitido em {{data}}.

| #          | Item                 | Qtd            |
| {{@index}} | {{itens.descricao}}  | {{itens.qtd}}  |

{{#vip}}
Cliente VIP: desconto aplicado.
{{/vip}}
```

**Código:**

```dart
final modelo = OdfDocument.open(modeloBytes);

print(OdfDocument.templateFields(modelo));
// [cliente.nome, data, @index, itens.descricao, itens.qtd, vip]

final recibo = OdfDocument.fillTemplate(modelo, {
  'cliente': {'nome': 'Ana Souza'},
  'data': DateTime(2026, 10, 9),
  'vip': true,
  'itens': [
    {'descricao': 'Caneta', 'qtd': 10},
    {'descricao': 'Caderno', 'qtd': 3},
  ],
});
```

### Sintaxe

| No modelo | Resultado |
| --- | --- |
| `{{nome}}`, `{{cliente.endereco.cidade}}` | O valor; pontos navegam em mapas |
| `{{itens.descricao}}` numa linha de tabela | A linha é repetida para cada item da lista `itens` |
| `{{itens.descricao}}` num item de lista | O item é repetido para cada elemento |
| `{{@index}}` | Posição do item repetido, a partir de 1 |
| Parágrafo `{{#chave}}` … parágrafo `{{/chave}}` | Mostra o trecho se o valor for verdadeiro; repete se for lista; some se for falso, nulo ou lista vazia |
| Parágrafo `{{^chave}}` … parágrafo `{{/chave}}` | O contrário: mostra só se for falso ou vazio |
| `{{.}}` | O item atual, dentro de um bloco repetido de uma lista simples |
| Célula de planilha contendo só `{{campo}}` | Número, data ou booleano gravado com o tipo certo |

Dentro de um bloco `{{#itens}}`, os campos do item são usados diretamente: `{{descricao}}` em vez de `{{itens.descricao}}`.

Os campos funcionam mesmo se o editor tiver dividido o texto em vários trechos de formatação (por exemplo, com metade do campo em negrito). O valor fica com a formatação do início do campo.

### Opções

```dart
final bytes = OdfDocument.fillTemplate(
  modelo,
  dados,
  options: OdfTemplateOptions(
    missing: OdfMissingField.error, // .empty (padrão), .keep ou .error
    format: (value) => switch (value) {
      final double v => v.toStringAsFixed(2).replaceAll('.', ','),
      final DateTime d => '${d.day}/${d.month}/${d.year}',
      _ => '$value',
    },
  ),
);
```

Por padrão, inteiros saem sem casas decimais, datas em `dd/MM/yyyy` (com `HH:mm` se houver hora) e booleanos como `Sim`/`Não`.

Preencher um modelo `.ott` gera um documento `.odt`.

## Converter para HTML, Markdown, CSV e JSON

### HTML

```dart
final html = OdfConvert.toHtml(doc);                    // página completa
final fragment = OdfConvert.toHtml(doc, fragment: true); // só o conteúdo
```

Imagens são embutidas como `data:` URIs e as notas viram uma lista no fim.

### Markdown

```dart
final markdown = OdfConvert.toMarkdown(doc);

final doc2 = OdfConvert.fromMarkdown('''
# Título

Texto com **negrito**, *itálico*, ~~tachado~~, `código` e [link](https://dart.dev).

- item
  1. subitem

| Nome | Valor |
|:-----|------:|
| A    | 10    |
''');
final bytes = OdfDocument.createRichText(doc2);
```

Segue o Markdown do GitHub: tabelas, `~~tachado~~` e notas `[^1]`. Quebras de página viram `---`, e `---` volta a ser quebra de página.

As imagens são embutidas como `data:` URIs. Para gravá-las em arquivos separados, use `imageUrl`. Na leitura, imagens com outros endereços são carregadas por `imageLoader`.

### CSV

```dart
final csv = OdfConvert.toCsv(sheet);                         // separador "," e ponto decimal
final csvBr = OdfConvert.toCsv(sheet, decimalComma: true);    // ";" e vírgula decimal (Excel em português)

final imported = OdfConvert.fromCsv(csvText, name: 'Importado'); // detecta , ; ou tabulação
```

Na importação, números, `TRUE`/`FALSE`, porcentagens e datas ISO (`2026-03-15`) viram valores tipados. Textos como `007` continuam texto, para não perder os zeros. Use `inferTypes: false` para manter tudo como texto.

### JSON

```dart
import 'dart:convert';

final json = jsonEncode(OdfConvert.toJson(workbook)); // {"Vendas": [[...], ...]}

final records = OdfConvert.toRecords(sheet);
// [{'Produto': 'Caneta', 'Qtd': 10, ...}, ...]  (primeira linha = nomes das colunas)

final fromApi = OdfConvert.fromRecords('Clientes', [
  {'nome': 'Ana', 'idade': 30},
  {'nome': 'Bruno', 'idade': 25},
], headerStyle: OdfCellStyle.header);
```

Use `toRecords(sheet, jsonSafe: true)` para receber datas como texto ISO, prontas para `jsonEncode`.

## Salvar e abrir arquivos no Flutter

Dart VM, desktop e mobile:

```dart
import 'dart:io';

await File('relatorio.odt').writeAsBytes(OdfDocument.createRichText(doc));
final package = OdfDocument.open(await File('planilha.ods').readAsBytes());
```

Mobile, numa pasta do app (pacote `path_provider`):

```dart
final dir = await getApplicationDocumentsDirectory();
final file = File('${dir.path}/relatorio.odt');
await file.writeAsBytes(bytes);
```

Compartilhar (pacote `share_plus`):

```dart
await Share.shareXFiles([
  XFile.fromData(Uint8List.fromList(bytes),
      name: 'relatorio.odt', mimeType: 'application/vnd.oasis.opendocument.text'),
]);
```

Escolher um arquivo do usuário (pacote `file_picker`):

```dart
final result = await FilePicker.platform.pickFiles(withData: true);
final package = OdfDocument.open(result!.files.single.bytes!);
```

Tipos MIME para baixar ou enviar:

| Extensão | MIME |
| --- | --- |
| `.odt` | `application/vnd.oasis.opendocument.text` |
| `.ods` | `application/vnd.oasis.opendocument.spreadsheet` |
| `.odp` | `application/vnd.oasis.opendocument.presentation` |

Também estão em `OdfDocumentType.text.mimeType`, e a extensão em `OdfDocumentType.text.extension`.

Planilhas grandes podem levar alguns segundos para serem lidas. Para não travar a interface, leia em segundo plano:

```dart
final workbook = await Isolate.run(() => OdfDocument.readWorkbook(OdfDocument.open(bytes)));
```

## Erros

Problemas com o arquivo geram `OdfException`, com mensagem em português:

```dart
try {
  final package = OdfDocument.open(bytes);
  final doc = OdfDocument.readRichText(package);
} on OdfException catch (e) {
  print(e.message);
  // "O arquivo não é um pacote ZIP/ODF válido (...)"
  // "O documento está protegido por senha; ..."
  // "Esperado documento ODT, mas o pacote é ODS."
}
```

Para se proteger de arquivos maliciosos, a leitura tem limites: até 10.000 arquivos internos, até 512 MB descompactados, e planilhas com até 1.048.576 linhas e 16.384 colunas com dados. Acima disso, a leitura gera `OdfException` em vez de esgotar a memória.

## Limitações

- **Documentos protegidos por senha** não podem ser abertos.
- **Fórmulas** não são calculadas; o LibreOffice calcula ao abrir.
- **Datas** não guardam fuso horário: são gravados os campos do `DateTime` (dia, hora...) sem conversão. Use `toLocal()` antes, se for o caso.
- **Ler e regravar** (`readRichText` e depois `createRichText`) mantém só o que o modelo representa: texto, formatação, listas, tabelas, imagens, notas, cabeçalho e rodapé. Estilos com nome, sumários, comentários, gráficos e macros se perdem. Para alterar um arquivo mantendo tudo, use [modelos](#preencher-modelos).
- **`.odb`, `.odg` e `.odf`** são abertos, mas sem leitura estruturada; os arquivos internos podem ser lidos com `package.file(...)`.
- **HTML** só é exportado; não há importação de HTML.
