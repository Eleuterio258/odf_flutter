/// Metadados do documento, gravados em `meta.xml`.
final class OdfMetadata {
  const OdfMetadata({
    this.title,
    this.subject,
    this.description,
    this.author,
    this.keywords = const [],
    this.language,
    this.created,
    this.modified,
    this.generator,
  });

  final String? title;
  final String? subject;
  final String? description;
  final String? author;
  final List<String> keywords;

  /// Código de idioma no formato `pt-BR`, `en-US`, etc.
  final String? language;
  final DateTime? created;
  final DateTime? modified;

  /// Aplicativo que gerou o documento (somente leitura; o escritor usa o próprio nome).
  final String? generator;

  @override
  String toString() =>
      'OdfMetadata(title: $title, author: $author, language: $language)';
}
