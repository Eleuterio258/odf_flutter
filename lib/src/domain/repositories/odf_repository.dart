import '../entities/odf_package_entity.dart';
import '../entities/odf_presentation.dart';
import '../entities/odf_rich_text.dart';
import '../entities/odf_template_options.dart';
import '../entities/odf_types.dart';
import '../entities/odf_workbook.dart';

abstract interface class OdfRepository {
  OdfPackageEntity open(List<int> bytes);
  List<int> create({required OdfDocumentType type, required String contentXml});

  List<int> writeText(OdfRichTextDocument document);
  List<int> writeWorkbook(OdfWorkbook workbook);
  List<int> writePresentation(OdfPresentation presentation);

  OdfRichTextDocument readText(OdfPackageEntity package);
  OdfWorkbook readWorkbook(OdfPackageEntity package);
  OdfPresentation readPresentation(OdfPackageEntity package);

  List<int> fillTemplate(OdfPackageEntity package, Map<String, Object?> data,
      OdfTemplateOptions options);
  List<String> templateFields(OdfPackageEntity package);
}
