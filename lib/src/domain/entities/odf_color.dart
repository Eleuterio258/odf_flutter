/// Cor RGB usada em textos, fundos de células, slides e formas.
final class OdfColor {
  const OdfColor(this.red, this.green, this.blue)
      : assert(red >= 0 && red <= 255),
        assert(green >= 0 && green <= 255),
        assert(blue >= 0 && blue <= 255);

  /// Aceita `#RRGGBB`, `RRGGBB` ou a forma curta `#RGB`.
  factory OdfColor.hex(String hex) {
    final color = tryParse(hex);
    if (color == null) {
      throw ArgumentError.value(hex, 'hex', 'Cor hexadecimal inválida');
    }
    return color;
  }

  static OdfColor? tryParse(String? hex) {
    if (hex == null) return null;
    var value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 3) value = value.split('').map((c) => '$c$c').join();
    if (value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;
    return OdfColor((parsed >> 16) & 0xff, (parsed >> 8) & 0xff, parsed & 0xff);
  }

  final int red;
  final int green;
  final int blue;

  static const black = OdfColor(0, 0, 0);
  static const white = OdfColor(255, 255, 255);
  static const yellow = OdfColor(255, 255, 0);
  static const gray = OdfColor(128, 128, 128);
  static const lightGray = OdfColor(221, 221, 221);

  String toHex() => '#${[
        red,
        green,
        blue
      ].map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';

  @override
  bool operator ==(Object other) =>
      other is OdfColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'OdfColor(${toHex()})';
}
