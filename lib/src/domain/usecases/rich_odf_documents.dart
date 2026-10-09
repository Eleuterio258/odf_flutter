import '../entities/odf_package_entity.dart';
import '../entities/odf_presentation.dart';
import '../entities/odf_rich_text.dart';
import '../entities/odf_template_options.dart';
import '../entities/odf_workbook.dart';
import '../repositories/odf_repository.dart';

class CreateRichTextOdt {
  const CreateRichTextOdt(this._repository);
  final OdfRepository _repository;

  List<int> call(OdfRichTextDocument document) =>
      _repository.writeText(document);
}

class CreateWorkbookOds {
  const CreateWorkbookOds(this._repository);
  final OdfRepository _repository;

  List<int> call(OdfWorkbook workbook) => _repository.writeWorkbook(workbook);
}

class CreatePresentationOdp {
  const CreatePresentationOdp(this._repository);
  final OdfRepository _repository;

  List<int> call(OdfPresentation presentation) =>
      _repository.writePresentation(presentation);
}

class FillOdfTemplate {
  const FillOdfTemplate(this._repository);
  final OdfRepository _repository;

  List<int> call(OdfPackageEntity package, Map<String, Object?> data,
          OdfTemplateOptions options) =>
      _repository.fillTemplate(package, data, options);
}

class ReadRichText {
  const ReadRichText(this._repository);
  final OdfRepository _repository;

  OdfRichTextDocument call(OdfPackageEntity package) =>
      _repository.readText(package);
}

class ReadWorkbook {
  const ReadWorkbook(this._repository);
  final OdfRepository _repository;

  OdfWorkbook call(OdfPackageEntity package) =>
      _repository.readWorkbook(package);
}

class ReadPresentation {
  const ReadPresentation(this._repository);
  final OdfRepository _repository;

  OdfPresentation call(OdfPackageEntity package) =>
      _repository.readPresentation(package);
}
