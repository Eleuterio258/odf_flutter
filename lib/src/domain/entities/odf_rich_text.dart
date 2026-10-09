import 'odf_color.dart';
import 'odf_image.dart';
import 'odf_metadata.dart';

enum OdfTextAlign { start, center, end, justify }

/// Formatação de caracteres (negrito, itálico, fonte, cor...).
final class OdfTextStyle {
  const OdfTextStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.superscript = false,
    this.subscript = false,
    this.fontSize,
    this.fontFamily,
    this.color,
    this.backgroundColor,
  });

  static const plain = OdfTextStyle();

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool superscript;
  final bool subscript;

  /// Tamanho em pontos.
  final double? fontSize;
  final String? fontFamily;
  final OdfColor? color;
  final OdfColor? backgroundColor;

  bool get isPlain => this == plain;

  OdfTextStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? superscript,
    bool? subscript,
    double? fontSize,
    String? fontFamily,
    OdfColor? color,
    OdfColor? backgroundColor,
  }) =>
      OdfTextStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        superscript: superscript ?? this.superscript,
        subscript: subscript ?? this.subscript,
        fontSize: fontSize ?? this.fontSize,
        fontFamily: fontFamily ?? this.fontFamily,
        color: color ?? this.color,
        backgroundColor: backgroundColor ?? this.backgroundColor,
      );

  @override
  bool operator ==(Object other) =>
      other is OdfTextStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.superscript == superscript &&
      other.subscript == subscript &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.color == color &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strikethrough,
      superscript, subscript, fontSize, fontFamily, color, backgroundColor);

  @override
  String toString() => 'OdfTextStyle(${[
        if (bold) 'bold',
        if (italic) 'italic',
        if (underline) 'underline',
        if (strikethrough) 'strikethrough',
        if (superscript) 'superscript',
        if (subscript) 'subscript',
        if (fontSize != null) '${fontSize}pt',
        if (fontFamily != null) fontFamily,
        if (color != null) 'color ${color!.toHex()}',
        if (backgroundColor != null) 'background ${backgroundColor!.toHex()}',
      ].join(', ')})';
}

/// Formatação de parágrafo. Medidas em centímetros.
final class OdfParagraphStyle {
  const OdfParagraphStyle({
    this.align,
    this.spaceBefore,
    this.spaceAfter,
    this.indentLeft,
    this.firstLineIndent,
    this.lineSpacing,
    this.backgroundColor,
  });

  static const normal = OdfParagraphStyle();

  final OdfTextAlign? align;
  final double? spaceBefore;
  final double? spaceAfter;
  final double? indentLeft;
  final double? firstLineIndent;

  /// Múltiplo da altura da linha: `1.5` equivale a 150%.
  final double? lineSpacing;
  final OdfColor? backgroundColor;

  bool get isNormal => this == normal;

  @override
  bool operator ==(Object other) =>
      other is OdfParagraphStyle &&
      other.align == align &&
      other.spaceBefore == spaceBefore &&
      other.spaceAfter == spaceAfter &&
      other.indentLeft == indentLeft &&
      other.firstLineIndent == firstLineIndent &&
      other.lineSpacing == lineSpacing &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(align, spaceBefore, spaceAfter, indentLeft,
      firstLineIndent, lineSpacing, backgroundColor);
}

// ---------------------------------------------------------------------------
// Conteúdo em linha
// ---------------------------------------------------------------------------

sealed class OdfInline {
  const OdfInline();

  String get plainText;
}

final class OdfSpan extends OdfInline {
  const OdfSpan(this.text, {this.style = OdfTextStyle.plain});

  /// Pode conter `\n` (quebra de linha) e `\t` (tabulação).
  final String text;
  final OdfTextStyle style;

  @override
  String get plainText => text;

  @override
  bool operator ==(Object other) =>
      other is OdfSpan && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => 'OdfSpan(${_quote(text)}, $style)';
}

final class OdfLink extends OdfInline {
  const OdfLink(this.text, this.url, {this.style = OdfTextStyle.plain});

  final String text;
  final String url;
  final OdfTextStyle style;

  @override
  String get plainText => text;

  @override
  bool operator ==(Object other) =>
      other is OdfLink &&
      other.text == text &&
      other.url == url &&
      other.style == style;

  @override
  int get hashCode => Object.hash(text, url, style);

  @override
  String toString() => 'OdfLink(${_quote(text)} -> $url)';
}

final class OdfLineBreak extends OdfInline {
  const OdfLineBreak();

  @override
  String get plainText => '\n';
}

final class OdfTab extends OdfInline {
  const OdfTab();

  @override
  String get plainText => '\t';
}

/// Campo com o número da página atual (útil em cabeçalhos e rodapés).
final class OdfPageNumber extends OdfInline {
  const OdfPageNumber({this.style = OdfTextStyle.plain});

  final OdfTextStyle style;

  @override
  String get plainText => '#';
}

/// Campo com o total de páginas.
final class OdfPageCount extends OdfInline {
  const OdfPageCount({this.style = OdfTextStyle.plain});

  final OdfTextStyle style;

  @override
  String get plainText => '#';
}

/// Nota de rodapé (ou de fim, com [endnote]) ancorada neste ponto do texto.
/// A numeração é automática; [citation] só é usado se informado.
final class OdfNote extends OdfInline {
  OdfNote(List<OdfBlock> body, {this.endnote = false, this.citation})
      : body = List.unmodifiable(body);

  factory OdfNote.text(String text, {bool endnote = false}) =>
      OdfNote([OdfParagraph.text(text)], endnote: endnote);

  final List<OdfBlock> body;
  final bool endnote;
  final String? citation;

  /// O texto da nota não entra no texto corrido.
  @override
  String get plainText => '';

  String get bodyText => body.map((b) => b.plainText).join('\n');

  @override
  String toString() => 'OdfNote(${_quote(bodyText)})';
}

// ---------------------------------------------------------------------------
// Blocos
// ---------------------------------------------------------------------------

sealed class OdfBlock {
  const OdfBlock();

  String get plainText;
}

final class OdfParagraph extends OdfBlock {
  OdfParagraph(List<OdfInline> inlines, {this.style = OdfParagraphStyle.normal})
      : inlines = List.unmodifiable(inlines);

  factory OdfParagraph.text(
    String text, {
    OdfTextStyle style = OdfTextStyle.plain,
    OdfParagraphStyle paragraphStyle = OdfParagraphStyle.normal,
  }) =>
      OdfParagraph([if (text.isNotEmpty) OdfSpan(text, style: style)],
          style: paragraphStyle);

  final List<OdfInline> inlines;
  final OdfParagraphStyle style;

  @override
  String get plainText => inlines.map((i) => i.plainText).join();

  @override
  String toString() => 'OdfParagraph(${_quote(plainText)})';
}

final class OdfHeading extends OdfBlock {
  OdfHeading(List<OdfInline> inlines,
      {this.level = 1, this.style = OdfParagraphStyle.normal})
      : assert(level >= 1 && level <= 6),
        inlines = List.unmodifiable(inlines);

  factory OdfHeading.text(String text,
          {int level = 1, OdfTextStyle style = OdfTextStyle.plain}) =>
      OdfHeading([OdfSpan(text, style: style)], level: level);

  final int level;
  final List<OdfInline> inlines;
  final OdfParagraphStyle style;

  @override
  String get plainText => inlines.map((i) => i.plainText).join();

  @override
  String toString() => 'OdfHeading($level, ${_quote(plainText)})';
}

final class OdfListItem {
  /// Itens podem conter parágrafos, títulos, imagens e listas aninhadas.
  OdfListItem(List<OdfBlock> blocks) : blocks = List.unmodifiable(blocks);

  factory OdfListItem.text(String text,
          {OdfTextStyle style = OdfTextStyle.plain}) =>
      OdfListItem([OdfParagraph.text(text, style: style)]);

  final List<OdfBlock> blocks;

  String get plainText => blocks.map((b) => b.plainText).join('\n');
}

final class OdfList extends OdfBlock {
  OdfList(List<OdfListItem> items, {this.ordered = false})
      : items = List.unmodifiable(items);

  factory OdfList.of(List<String> items, {bool ordered = false}) =>
      OdfList(items.map(OdfListItem.text).toList(), ordered: ordered);

  final List<OdfListItem> items;
  final bool ordered;

  @override
  String get plainText => items.map((i) => i.plainText).join('\n');

  @override
  String toString() =>
      'OdfList(${ordered ? 'numerada' : 'marcadores'}, ${items.length} itens)';
}

final class OdfTableCell {
  OdfTableCell(List<OdfBlock> blocks,
      {this.colSpan = 1, this.rowSpan = 1, this.backgroundColor})
      : assert(colSpan >= 1 && rowSpan >= 1),
        blocks = List.unmodifiable(blocks);

  factory OdfTableCell.text(
    String text, {
    OdfTextStyle style = OdfTextStyle.plain,
    int colSpan = 1,
    int rowSpan = 1,
    OdfColor? backgroundColor,
  }) =>
      OdfTableCell(
        [OdfParagraph.text(text, style: style)],
        colSpan: colSpan,
        rowSpan: rowSpan,
        backgroundColor: backgroundColor,
      );

  final List<OdfBlock> blocks;
  final int colSpan;
  final int rowSpan;
  final OdfColor? backgroundColor;

  String get plainText => blocks.map((b) => b.plainText).join('\n');
}

final class OdfTableRow {
  OdfTableRow(List<OdfTableCell> cells) : cells = List.unmodifiable(cells);

  factory OdfTableRow.text(List<String> values,
          {OdfTextStyle style = OdfTextStyle.plain}) =>
      OdfTableRow([for (final v in values) OdfTableCell.text(v, style: style)]);

  final List<OdfTableCell> cells;
}

final class OdfTable extends OdfBlock {
  OdfTable(List<OdfTableRow> rows,
      {this.headerRows = 0, List<double>? columnWidths, this.name})
      : rows = List.unmodifiable(rows),
        columnWidths =
            columnWidths == null ? null : List.unmodifiable(columnWidths);

  /// Cria uma tabela de texto; a primeira linha vira cabeçalho quando [header] é verdadeiro.
  factory OdfTable.fromValues(List<List<String>> values,
          {bool header = true, List<double>? columnWidths}) =>
      OdfTable(
        [
          for (var i = 0; i < values.length; i++)
            OdfTableRow.text(values[i],
                style: header && i == 0
                    ? const OdfTextStyle(bold: true)
                    : OdfTextStyle.plain),
        ],
        headerRows: header && values.isNotEmpty ? 1 : 0,
        columnWidths: columnWidths,
      );

  final List<OdfTableRow> rows;
  final int headerRows;

  /// Larguras em centímetros; quando nulo, a largura útil da página é dividida igualmente.
  final List<double>? columnWidths;
  final String? name;

  @override
  String get plainText =>
      rows.map((r) => r.cells.map((c) => c.plainText).join('\t')).join('\n');

  @override
  String toString() => 'OdfTable(${rows.length} linhas)';
}

final class OdfImage extends OdfBlock {
  OdfImage(this.data, {this.width, this.height, this.align, this.description});

  factory OdfImage.bytes(
    List<int> bytes, {
    String? mimeType,
    double? width,
    double? height,
    OdfTextAlign? align,
    String? description,
  }) =>
      OdfImage(OdfImageData(bytes, mimeType: mimeType),
          width: width, height: height, align: align, description: description);

  final OdfImageData data;

  /// Medidas em centímetros. Se ausentes, são calculadas pelos pixels (96 DPI),
  /// mantendo a proporção e limitadas à largura útil da página.
  final double? width;
  final double? height;
  final OdfTextAlign? align;
  final String? description;

  @override
  String get plainText => '';

  @override
  String toString() => 'OdfImage(${data.mimeType}, $width x $height cm)';
}

final class OdfPageBreak extends OdfBlock {
  const OdfPageBreak();

  @override
  String get plainText => '';

  @override
  String toString() => 'OdfPageBreak()';
}

// ---------------------------------------------------------------------------
// Documento
// ---------------------------------------------------------------------------

/// Tamanho e margens da página, em centímetros.
final class OdfPageLayout {
  const OdfPageLayout({
    this.width = 21.0,
    this.height = 29.7,
    this.marginTop = 2.0,
    this.marginBottom = 2.0,
    this.marginLeft = 2.0,
    this.marginRight = 2.0,
  });

  static const a4 = OdfPageLayout();
  static const letter = OdfPageLayout(width: 21.59, height: 27.94);

  final double width;
  final double height;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;

  bool get isLandscape => width > height;

  OdfPageLayout get landscape => isLandscape
      ? this
      : OdfPageLayout(
          width: height,
          height: width,
          marginTop: marginTop,
          marginBottom: marginBottom,
          marginLeft: marginLeft,
          marginRight: marginRight,
        );

  double get contentWidth => width - marginLeft - marginRight;

  @override
  bool operator ==(Object other) =>
      other is OdfPageLayout &&
      other.width == width &&
      other.height == height &&
      other.marginTop == marginTop &&
      other.marginBottom == marginBottom &&
      other.marginLeft == marginLeft &&
      other.marginRight == marginRight;

  @override
  int get hashCode => Object.hash(
      width, height, marginTop, marginBottom, marginLeft, marginRight);
}

/// Documento de texto com formatação completa (ODT).
///
/// As listas são mutáveis, e os métodos auxiliares permitem montar o documento
/// em cascata:
///
/// ```dart
/// final doc = OdfRichTextDocument()
///   ..heading('Relatório')
///   ..paragraph('Resumo', style: const OdfTextStyle(italic: true))
///   ..bullets(['Primeiro', 'Segundo']);
/// ```
final class OdfRichTextDocument {
  OdfRichTextDocument({
    List<OdfBlock>? blocks,
    this.metadata = const OdfMetadata(),
    this.pageLayout = OdfPageLayout.a4,
    List<OdfBlock>? header,
    List<OdfBlock>? footer,
  })  : blocks = List.of(blocks ?? const []),
        header = List.of(header ?? const []),
        footer = List.of(footer ?? const []);

  final List<OdfBlock> blocks;
  final List<OdfBlock> header;
  final List<OdfBlock> footer;
  OdfMetadata metadata;
  OdfPageLayout pageLayout;

  String get plainText =>
      blocks.map((b) => b.plainText).where((t) => t.isNotEmpty).join('\n');

  void heading(String text, {int level = 1}) =>
      blocks.add(OdfHeading.text(text, level: level));

  void paragraph(String text,
          {OdfTextStyle style = OdfTextStyle.plain,
          OdfParagraphStyle? paragraphStyle}) =>
      blocks.add(OdfParagraph.text(text,
          style: style,
          paragraphStyle: paragraphStyle ?? OdfParagraphStyle.normal));

  void rich(List<OdfInline> inlines,
          {OdfParagraphStyle paragraphStyle = OdfParagraphStyle.normal}) =>
      blocks.add(OdfParagraph(inlines, style: paragraphStyle));

  void bullets(List<String> items) => blocks.add(OdfList.of(items));

  void numbered(List<String> items) =>
      blocks.add(OdfList.of(items, ordered: true));

  void table(List<List<String>> values,
          {bool header = true, List<double>? columnWidths}) =>
      blocks.add(OdfTable.fromValues(values,
          header: header, columnWidths: columnWidths));

  void image(List<int> bytes,
          {double? width,
          double? height,
          OdfTextAlign? align,
          String? description}) =>
      blocks.add(OdfImage.bytes(bytes,
          width: width,
          height: height,
          align: align,
          description: description));

  void pageBreak() => blocks.add(const OdfPageBreak());
}

String _quote(String text) =>
    '"${text.length > 40 ? '${text.substring(0, 40)}…' : text}"';
