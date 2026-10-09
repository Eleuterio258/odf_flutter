import '../entities/odf_metadata.dart';
import '../entities/odf_rich_text.dart';
import '../entities/odf_types.dart';
import '../entities/odf_workbook.dart';
import '../repositories/odf_repository.dart';

/// API simples: delega ao escritor completo, que gera styles.xml e meta.xml.
class CreateTextOdt {
  const CreateTextOdt(this._repository);
  final OdfRepository _repository;

  List<int> call(OdfTextDocument document) =>
      _repository.writeText(OdfRichTextDocument(
        metadata: OdfMetadata(title: document.title),
        blocks: [
          if (document.title != null) OdfHeading.text(document.title!),
          for (final text in document.paragraphs) OdfParagraph.text(text),
        ],
      ));
}

class CreateSpreadsheetOds {
  const CreateSpreadsheetOds(this._repository);
  final OdfRepository _repository;

  List<int> call(OdfSpreadsheet document) =>
      _repository.writeWorkbook(OdfWorkbook(sheets: [
        for (final sheet in document.sheets)
          OdfWorksheet(sheet.name, rows: [
            for (final row in sheet.rows)
              OdfRow([for (final value in row) OdfCell(OdfStringValue(value))]),
          ]),
      ]));
}
