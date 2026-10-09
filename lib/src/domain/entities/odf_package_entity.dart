import '../exceptions/odf_exception.dart';
import 'odf_types.dart';

class OdfPackageEntity {
  OdfPackageEntity({
    required this.type,
    required this.version,
    this.isTemplate = false,
    required Map<String, List<int>> files,
  }) : _files = {
          for (final entry in files.entries)
            entry.key: List<int>.unmodifiable(entry.value),
        };

  final OdfDocumentType type;
  final String version;

  /// Verdadeiro para modelos (.ott, .ots, .otp).
  final bool isTemplate;
  final Map<String, List<int>> _files;

  List<int> file(String path) {
    final bytes = _files[path];
    if (bytes == null) throw OdfException('Arquivo interno ausente: $path');
    return bytes;
  }

  bool contains(String path) => _files.containsKey(path);

  /// Caminhos internos, na ordem do pacote.
  Iterable<String> get paths => _files.keys;

  List<int> get contentXml => file('content.xml');
}
