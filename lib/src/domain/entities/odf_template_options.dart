/// O que fazer quando um campo do modelo não existe nos dados.
enum OdfMissingField {
  /// Substitui por texto vazio.
  empty,

  /// Mantém o `{{campo}}` no documento.
  keep,

  /// Lança [OdfException] listando os campos ausentes.
  error,
}

/// Opções de preenchimento de modelos.
///
/// Sintaxe aceita nos documentos (ODT, ODS e ODP, inclusive cabeçalho e rodapé):
///
/// * `{{nome}}` e `{{cliente.endereco.cidade}}`: valor (caminho em mapas).
/// * Tabela ou lista com `{{itens.descricao}}`, sendo `itens` uma lista de mapas:
///   a linha (ou o item de lista) é repetida para cada elemento.
///   `{{@index}}` é a posição, a partir de 1.
/// * Parágrafos `{{#chave}}` ... `{{/chave}}`: o trecho entre eles some se o
///   valor for falso, nulo ou lista vazia, e é repetido se for uma lista.
///   `{{^chave}}` ... `{{/chave}}` faz o inverso. `{{.}}` é o item atual.
///
/// Numa planilha, uma célula cujo texto é só `{{campo}}` recebe o tipo do valor
/// (número, data, booleano), e não apenas o texto.
final class OdfTemplateOptions {
  const OdfTemplateOptions({this.missing = OdfMissingField.empty, this.format});

  final OdfMissingField missing;

  /// Converte valores em texto. Quando ausente: inteiros sem casas, datas em
  /// `dd/MM/yyyy` (com `HH:mm` se houver hora), booleanos como `Sim`/`Não`.
  final String Function(Object? value)? format;
}
