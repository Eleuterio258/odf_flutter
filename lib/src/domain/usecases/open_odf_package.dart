import '../entities/odf_package_entity.dart';
import '../repositories/odf_repository.dart';

class OpenOdfPackage {
  const OpenOdfPackage(this._repository);
  final OdfRepository _repository;

  OdfPackageEntity call(List<int> bytes) => _repository.open(bytes);
}
