class OdfException implements Exception {
  const OdfException(this.message);
  final String message;

  @override
  String toString() => 'OdfException: $message';
}
