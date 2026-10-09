import '../../domain/entities/odf_package_entity.dart';
import '../../domain/entities/odf_presentation.dart';
import '../../domain/entities/odf_rich_text.dart';
import '../../domain/entities/odf_template_options.dart';
import '../../domain/entities/odf_types.dart';
import '../../domain/entities/odf_workbook.dart';
import '../../domain/repositories/odf_repository.dart';
import '../datasources/odf_zip_data_source.dart';
import '../odf/odf_document_readers.dart';
import '../odf/odf_document_writers.dart';
import '../odf/odf_template_engine.dart';

class OdfRepositoryImpl implements OdfRepository {
  OdfRepositoryImpl({OdfZipDataSource? dataSource})
      : _dataSource = dataSource ?? OdfZipDataSource();

  final OdfZipDataSource _dataSource;

  @override
  OdfPackageEntity open(List<int> bytes) {
    final files = _dataSource.decode(bytes);
    _dataSource.ensureNotEncrypted(files);
    return OdfPackageEntity(
      type: _dataSource.readType(files),
      version: _dataSource.readVersion(files),
      isTemplate: _dataSource.isTemplate(files),
      files: files,
    );
  }

  @override
  List<int> create(
          {required OdfDocumentType type, required String contentXml}) =>
      _dataSource.encode(type: type, contentXml: contentXml);

  @override
  List<int> writeText(OdfRichTextDocument document) =>
      _encode(OdtWriter().write(document));

  @override
  List<int> writeWorkbook(OdfWorkbook workbook) =>
      _encode(OdsWriter().write(workbook));

  @override
  List<int> writePresentation(OdfPresentation presentation) =>
      _encode(OdpWriter().write(presentation));

  @override
  OdfRichTextDocument readText(OdfPackageEntity package) =>
      OdtReader().read(package);

  @override
  OdfWorkbook readWorkbook(OdfPackageEntity package) =>
      OdsReader().read(package);

  @override
  OdfPresentation readPresentation(OdfPackageEntity package) =>
      OdpReader().read(package);

  @override
  List<int> fillTemplate(OdfPackageEntity package, Map<String, Object?> data,
          OdfTemplateOptions options) =>
      _dataSource.encodeFiles(OdfTemplateEngine(options).fill(package, data));

  @override
  List<String> templateFields(OdfPackageEntity package) =>
      OdfTemplateEngine.fields(package);

  List<int> _encode(OdfPackageFiles files) =>
      _dataSource.encodePackage(type: files.type, entries: files.entries);
}
