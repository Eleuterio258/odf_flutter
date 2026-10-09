import 'domain/entities/odf_package_entity.dart';
import 'domain/entities/odf_types.dart';
import 'data/repositories/odf_repository_impl.dart';

class OdfPackage {
  OdfPackage._(this._entity);

  factory OdfPackage.fromEntity(OdfPackageEntity entity) =>
      OdfPackage._(entity);

  final OdfPackageEntity _entity;

  static OdfPackage decode(List<int> bytes) =>
      OdfPackage._(OdfRepositoryImpl().open(bytes));

  OdfDocumentType get type => _entity.type;
  String get version => _entity.version;
  bool get isTemplate => _entity.isTemplate;
  List<int> get contentXml => _entity.contentXml;
  List<int> file(String path) => _entity.file(path);
  bool contains(String path) => _entity.contains(path);

  OdfPackageEntity get entity => _entity;
}
