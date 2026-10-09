enum OdfDocumentType {
  text('application/vnd.oasis.opendocument.text', 'odt'),
  spreadsheet('application/vnd.oasis.opendocument.spreadsheet', 'ods'),
  presentation('application/vnd.oasis.opendocument.presentation', 'odp'),
  database('application/vnd.oasis.opendocument.database', 'odb'),
  graphics('application/vnd.oasis.opendocument.graphics', 'odg'),
  formula('application/vnd.oasis.opendocument.formula', 'odf');

  const OdfDocumentType(this.mimeType, this.extension);
  final String mimeType;
  final String extension;

  /// Modelos (`...-template`, ex.: .ott, .ots, .otp) são mapeados para o tipo base.
  static OdfDocumentType fromMimeType(String mimeType) {
    final base = isTemplateMimeType(mimeType)
        ? mimeType.substring(0, mimeType.length - '-template'.length)
        : mimeType;
    return values.firstWhere(
      (type) => type.mimeType == base,
      orElse: () =>
          throw ArgumentError('Tipo MIME ODF não suportado: $mimeType'),
    );
  }

  static bool isTemplateMimeType(String mimeType) =>
      mimeType.endsWith('-template');
}

class OdfTextDocument {
  OdfTextDocument({this.title, List<String>? paragraphs})
      : paragraphs = List<String>.from(paragraphs ?? const []);

  String? title;
  final List<String> paragraphs;
}

class OdfSheet {
  OdfSheet(this.name, {List<List<String>>? rows})
      : rows = rows?.map(List<String>.from).toList() ?? <List<String>>[];

  String name;
  final List<List<String>> rows;
}

class OdfSpreadsheet {
  OdfSpreadsheet({List<OdfSheet>? sheets})
      : sheets = List<OdfSheet>.from(sheets ?? const []);

  final List<OdfSheet> sheets;
}
