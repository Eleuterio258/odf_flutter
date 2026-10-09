/// Imagem embutida no pacote ODF (pasta `Pictures/`).
final class OdfImageData {
  OdfImageData(List<int> bytes, {String? mimeType})
      : bytes = List<int>.unmodifiable(bytes),
        mimeType = mimeType ??
            detectMimeType(bytes) ??
            (throw ArgumentError(
                'Formato de imagem não reconhecido; informe mimeType.'));

  final List<int> bytes;
  final String mimeType;

  String get extension => switch (mimeType) {
        'image/png' => 'png',
        'image/jpeg' => 'jpg',
        'image/gif' => 'gif',
        'image/bmp' => 'bmp',
        'image/webp' => 'webp',
        'image/svg+xml' => 'svg',
        _ => 'bin',
      };

  /// Dimensões em pixels lidas do cabeçalho (PNG, JPEG, GIF e BMP).
  (int width, int height)? get pixelSize => _readPixelSize(bytes);

  static String? detectMimeType(List<int> b) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (starts(const [0x42, 0x4D])) return 'image/bmp';
    if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
        starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    final head =
        String.fromCharCodes(b.take(256).where((c) => c < 128)).trimLeft();
    if (head.startsWith('<svg') ||
        (head.startsWith('<?xml') && head.contains('<svg'))) {
      return 'image/svg+xml';
    }
    return null;
  }

  static (int, int)? _readPixelSize(List<int> b) {
    int be16(int i) => (b[i] << 8) | b[i + 1];
    int be32(int i) =>
        (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    int le16(int i) => b[i] | (b[i + 1] << 8);
    int le32(int i) =>
        (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24))
            .toSigned(32);

    switch (detectMimeType(b)) {
      case 'image/png' when b.length >= 24:
        return (be32(16), be32(20));
      case 'image/gif' when b.length >= 10:
        return (le16(6), le16(8));
      case 'image/bmp' when b.length >= 26:
        return (le32(18).abs(), le32(22).abs());
      case 'image/jpeg':
        var i = 2;
        while (i + 9 < b.length) {
          if (b[i] != 0xFF) {
            i++;
            continue;
          }
          final marker = b[i + 1];
          if (marker == 0xFF) {
            i++;
            continue;
          }
          if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
            i += 2;
            continue;
          }
          final isFrame = marker >= 0xC0 &&
              marker <= 0xCF &&
              marker != 0xC4 &&
              marker != 0xC8 &&
              marker != 0xCC;
          if (isFrame) return (be16(i + 7), be16(i + 5));
          i += 2 + be16(i + 2);
        }
        return null;
      default:
        return null;
    }
  }
}
