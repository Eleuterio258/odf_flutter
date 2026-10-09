import '../domain/entities/odf_image.dart';
import '../domain/entities/odf_metadata.dart';
import '../domain/entities/odf_rich_text.dart';
import '../domain/entities/odf_workbook.dart';
import 'odf_html.dart';
import 'odf_markdown.dart';
import 'odf_tabular.dart' as tabular;

/// Conversões entre os modelos ODF e formatos comuns.
abstract final class OdfConvert {
  /// Documento de texto em HTML (página completa, ou só o conteúdo com [fragment]).
  static String toHtml(OdfRichTextDocument document, {bool fragment = false}) =>
      OdfHtmlWriter(fragment: fragment).write(document);

  /// Documento de texto em Markdown (GitHub). Quebras de página viram `---`.
  static String toMarkdown(OdfRichTextDocument document,
          {String Function(OdfImageData image, int index)? imageUrl}) =>
      OdfMarkdownWriter(imageUrl: imageUrl).write(document);

  /// Markdown para documento de texto. `---` vira quebra de página.
  static OdfRichTextDocument fromMarkdown(String markdown,
          {OdfMetadata metadata = const OdfMetadata(),
          List<int>? Function(String url)? imageLoader}) =>
      OdfMarkdownReader(imageLoader: imageLoader)
          .read(markdown, metadata: metadata);

  static String toCsv(OdfWorksheet sheet,
          {String? separator,
          bool decimalComma = false,
          String lineEnding = '\r\n'}) =>
      tabular.worksheetToCsv(sheet,
          separator: separator,
          decimalComma: decimalComma,
          lineEnding: lineEnding);

  static OdfWorksheet fromCsv(
    String csv, {
    String name = 'Planilha1',
    String? separator,
    bool decimalComma = false,
    bool inferTypes = true,
    OdfCellStyle? headerStyle,
  }) =>
      tabular.worksheetFromCsv(csv,
          name: name,
          separator: separator,
          decimalComma: decimalComma,
          inferTypes: inferTypes,
          headerStyle: headerStyle);

  static Map<String, Object?> toJson(OdfWorkbook workbook) =>
      tabular.workbookToJson(workbook);

  static List<Map<String, Object?>> toRecords(OdfWorksheet sheet,
          {int headerRow = 0, bool jsonSafe = false}) =>
      tabular.worksheetToRecords(sheet,
          headerRow: headerRow, jsonSafe: jsonSafe);

  static OdfWorksheet fromRecords(
          String name, List<Map<String, Object?>> records,
          {OdfCellStyle? headerStyle}) =>
      tabular.worksheetFromRecords(name, records, headerStyle: headerStyle);
}
