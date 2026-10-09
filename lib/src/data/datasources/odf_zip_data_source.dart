import 'dart:convert';

import 'package:archive/archive.dart';

import '../../domain/entities/odf_types.dart';
import '../../domain/exceptions/odf_exception.dart';

/// Arquivo a ser gravado no pacote, com o tipo registrado no manifesto.
class OdfZipEntry {
  OdfZipEntry(this.path, this.bytes, this.mediaType);

  final String path;
  final List<int> bytes;
  final String mediaType;
}

class OdfZipDataSource {
  OdfZipDataSource(
      {this.maxEntries = 10000, this.maxUncompressedBytes = 512 * 1024 * 1024});

  /// Limites contra pacotes maliciosos (*zip bombs*).
  final int maxEntries;
  final int maxUncompressedBytes;

  Map<String, List<int>> decode(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw OdfException('O arquivo não é um pacote ZIP/ODF válido ($e).');
    }
    final files = archive.files.where((f) => f.isFile).toList();
    if (files.length > maxEntries) {
      throw OdfException(
          'O pacote tem ${files.length} arquivos; o limite é $maxEntries.');
    }
    var total = 0;
    final result = <String, List<int>>{};
    for (final file in files) {
      total += file.size;
      if (total > maxUncompressedBytes) {
        throw OdfException(
            'O conteúdo descompactado excede $maxUncompressedBytes bytes.');
      }
      try {
        result[file.name] = file.content;
      } on Object catch (e) {
        throw OdfException('Não foi possível descompactar ${file.name} ($e).');
      }
    }
    return result;
  }

  OdfDocumentType readType(Map<String, List<int>> files) {
    final mimetype = files['mimetype'];
    if (mimetype == null) {
      throw const OdfException('O pacote não contém o arquivo mimetype.');
    }
    final mime = decodeUtf8(mimetype, 'mimetype').trim();
    try {
      return OdfDocumentType.fromMimeType(mime);
    } on ArgumentError {
      throw OdfException('Tipo MIME ODF não suportado: $mime');
    }
  }

  bool isTemplate(Map<String, List<int>> files) {
    final mimetype = files['mimetype'];
    return mimetype != null &&
        OdfDocumentType.isTemplateMimeType(
            utf8.decode(mimetype, allowMalformed: true).trim());
  }

  /// Documentos protegidos por senha têm `content.xml` criptografado; sem esta
  /// verificação o erro apareceria como "XML inválido".
  void ensureNotEncrypted(Map<String, List<int>> files) {
    final manifest = files['META-INF/manifest.xml'];
    if (manifest != null &&
        utf8
            .decode(manifest, allowMalformed: true)
            .contains('encryption-data')) {
      throw const OdfException(
          'O documento está protegido por senha; documentos criptografados não são suportados.');
    }
  }

  String readVersion(Map<String, List<int>> files) {
    final content = files['content.xml'];
    if (content == null) {
      throw const OdfException('O pacote não contém content.xml.');
    }
    final xml = decodeUtf8(content, 'content.xml');
    return RegExp(r"""office:version=["']([^"']+)["']""")
            .firstMatch(xml)
            ?.group(1) ??
        '1.2';
  }

  List<int> encode(
          {required OdfDocumentType type, required String contentXml}) =>
      encodePackage(type: type, entries: [
        OdfZipEntry('content.xml', utf8.encode(contentXml), 'text/xml')
      ]);

  /// Grava o pacote: `mimetype` primeiro e sem compressão (exigência do ODF),
  /// seguido das entradas e do manifesto.
  List<int> encodePackage(
      {required OdfDocumentType type, required List<OdfZipEntry> entries}) {
    final archive = Archive();
    final mimetype = utf8.encode(type.mimeType);
    archive
        .addFile(ArchiveFile.noCompress('mimetype', mimetype.length, mimetype));
    for (final entry in entries) {
      archive.addFile(ArchiveFile(entry.path, entry.bytes.length, entry.bytes));
    }
    final manifest = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8"?>')
      ..write(
          '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
          'manifest:version="1.2">')
      ..write(
          '<manifest:file-entry manifest:full-path="/" manifest:version="1.2" '
          'manifest:media-type="${type.mimeType}"/>');
    for (final entry in entries) {
      manifest.write(
          '<manifest:file-entry manifest:full-path="${_escapeAttribute(entry.path)}" '
          'manifest:media-type="${_escapeAttribute(entry.mediaType)}"/>');
    }
    manifest.write('</manifest:manifest>');
    final manifestBytes = utf8.encode(manifest.toString());
    archive.addFile(ArchiveFile(
        'META-INF/manifest.xml', manifestBytes.length, manifestBytes));
    return ZipEncoder().encode(archive);
  }

  /// Regrava um pacote existente: `mimetype` primeiro e sem compressão, e os
  /// demais arquivos (inclusive o manifesto original) na ordem recebida.
  List<int> encodeFiles(Map<String, List<int>> files) {
    final mimetype = files['mimetype'];
    if (mimetype == null) {
      throw const OdfException('O pacote não contém o arquivo mimetype.');
    }
    final archive = Archive()
      ..addFile(ArchiveFile.noCompress('mimetype', mimetype.length, mimetype));
    files.forEach((path, bytes) {
      if (path != 'mimetype') {
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }
    });
    return ZipEncoder().encode(archive);
  }

  static String decodeUtf8(List<int> bytes, String path) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw OdfException('$path não está em UTF-8 válido.');
    }
  }

  static String _escapeAttribute(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');
}
