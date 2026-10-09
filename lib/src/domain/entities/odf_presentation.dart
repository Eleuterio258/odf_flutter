import 'odf_color.dart';
import 'odf_image.dart';
import 'odf_metadata.dart';
import 'odf_rich_text.dart';

/// Posição e tamanho de um elemento no slide, em centímetros.
final class OdfFrame {
  const OdfFrame(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is OdfFrame &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'OdfFrame($x, $y, $width x $height)';
}

sealed class OdfSlideElement {
  const OdfSlideElement();

  /// Quando nulo, o elemento é posicionado automaticamente na área de conteúdo.
  OdfFrame? get frame;
}

/// Caixa de texto; aceita parágrafos, títulos e listas.
final class OdfTextBox extends OdfSlideElement {
  OdfTextBox(List<OdfBlock> blocks, {this.frame})
      : blocks = List.unmodifiable(blocks);

  factory OdfTextBox.text(String text,
          {OdfTextStyle style = OdfTextStyle.plain, OdfFrame? frame}) =>
      OdfTextBox([
        for (final line in text.split('\n'))
          OdfParagraph.text(line, style: style)
      ], frame: frame);

  factory OdfTextBox.bullets(List<String> items,
          {bool ordered = false, OdfFrame? frame}) =>
      OdfTextBox([OdfList.of(items, ordered: ordered)], frame: frame);

  final List<OdfBlock> blocks;

  @override
  final OdfFrame? frame;

  String get plainText => blocks.map((b) => b.plainText).join('\n');
}

final class OdfSlideImage extends OdfSlideElement {
  OdfSlideImage(this.image, {this.frame});

  factory OdfSlideImage.bytes(List<int> bytes,
          {String? mimeType, OdfFrame? frame}) =>
      OdfSlideImage(OdfImageData(bytes, mimeType: mimeType), frame: frame);

  final OdfImageData image;

  @override
  final OdfFrame? frame;
}

enum OdfShapeKind { rectangle, ellipse }

final class OdfShape extends OdfSlideElement {
  const OdfShape(
    this.kind, {
    required OdfFrame this.frame,
    this.fill,
    this.stroke,
    this.text,
    this.textStyle = OdfTextStyle.plain,
  });

  final OdfShapeKind kind;

  @override
  final OdfFrame? frame;

  /// Cor de preenchimento; nulo deixa a forma transparente.
  final OdfColor? fill;

  /// Cor da borda; nulo remove a borda.
  final OdfColor? stroke;
  final String? text;
  final OdfTextStyle textStyle;
}

final class OdfSlide {
  OdfSlide({
    this.title,
    List<OdfSlideElement>? elements,
    this.notes,
    this.background,
    this.titleStyle = OdfTextStyle.plain,
  }) : elements = List.of(elements ?? const []);

  /// Slide de título com uma lista de marcadores.
  factory OdfSlide.bullets(String title, List<String> items, {String? notes}) =>
      OdfSlide(
          title: title, elements: [OdfTextBox.bullets(items)], notes: notes);

  String? title;

  /// Formatação aplicada sobre o padrão do título (36pt, negrito, centralizado).
  OdfTextStyle titleStyle;
  final List<OdfSlideElement> elements;

  /// Anotações do apresentador.
  String? notes;
  OdfColor? background;
}

/// Tamanho do slide, em centímetros.
final class OdfSlideSize {
  const OdfSlideSize(this.width, this.height);

  static const widescreen = OdfSlideSize(28.0, 15.75);
  static const standard = OdfSlideSize(28.0, 21.0);

  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is OdfSlideSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'OdfSlideSize($width x $height)';
}

final class OdfPresentation {
  OdfPresentation({
    List<OdfSlide>? slides,
    this.metadata = const OdfMetadata(),
    this.size = OdfSlideSize.widescreen,
  }) : slides = List.of(slides ?? const []);

  final List<OdfSlide> slides;
  OdfMetadata metadata;
  OdfSlideSize size;
}
