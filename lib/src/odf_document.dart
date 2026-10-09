import 'domain/entities/odf_presentation.dart';
import 'domain/entities/odf_rich_text.dart';
import 'domain/entities/odf_template_options.dart';
import 'domain/entities/odf_types.dart';
import 'domain/entities/odf_workbook.dart';
import 'domain/usecases/create_odf_documents.dart';
import 'domain/usecases/extract_odf_text.dart';
import 'domain/usecases/open_odf_package.dart';
import 'domain/usecases/rich_odf_documents.dart';
import 'data/repositories/odf_repository_impl.dart';
import 'odf_package.dart';

class OdfDocument {
  const OdfDocument._();

  static final _repository = OdfRepositoryImpl();
  static final _open = OpenOdfPackage(_repository);
  static final _createText = CreateTextOdt(_repository);
  static final _createSpreadsheet = CreateSpreadsheetOds(_repository);
  static const _extractText = ExtractOdfText();
  static final _createRichText = CreateRichTextOdt(_repository);
  static final _createWorkbook = CreateWorkbookOds(_repository);
  static final _createPresentation = CreatePresentationOdp(_repository);
  static final _readRichText = ReadRichText(_repository);
  static final _readWorkbook = ReadWorkbook(_repository);
  static final _readPresentation = ReadPresentation(_repository);
  static final _fillTemplate = FillOdfTemplate(_repository);

  static OdfPackage open(List<int> bytes) =>
      OdfPackage.fromEntity(_open(bytes));

  static List<int> createText(OdfTextDocument document) =>
      _createText(document);

  static List<int> createSpreadsheet(OdfSpreadsheet document) =>
      _createSpreadsheet(document);

  static String extractText(OdfPackage package) => _extractText(package.entity);

  /// ODT com estilos, listas, tabelas, imagens, cabeçalho/rodapé e metadados.
  static List<int> createRichText(OdfRichTextDocument document) =>
      _createRichText(document);

  /// ODS com valores tipados, fórmulas, formatos numéricos e mesclagens.
  static List<int> createWorkbook(OdfWorkbook workbook) =>
      _createWorkbook(workbook);

  /// ODP com títulos, caixas de texto, imagens, formas e anotações.
  static List<int> createPresentation(OdfPresentation presentation) =>
      _createPresentation(presentation);

  static OdfRichTextDocument readRichText(OdfPackage package) =>
      _readRichText(package.entity);

  static OdfWorkbook readWorkbook(OdfPackage package) =>
      _readWorkbook(package.entity);

  static OdfPresentation readPresentation(OdfPackage package) =>
      _readPresentation(package.entity);

  /// Preenche os `{{campos}}` de um modelo ODT, ODS ou ODP (inclusive .ott),
  /// preservando estilos, imagens e o restante do arquivo original.
  /// A sintaxe está descrita em [OdfTemplateOptions].
  static List<int> fillTemplate(
    OdfPackage template,
    Map<String, Object?> data, {
    OdfTemplateOptions options = const OdfTemplateOptions(),
  }) =>
      _fillTemplate(template.entity, data, options);

  /// Campos `{{...}}` encontrados no modelo.
  static List<String> templateFields(OdfPackage template) =>
      _repository.templateFields(template.entity);
}
