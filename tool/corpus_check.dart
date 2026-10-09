import 'dart:convert';
import 'dart:io';

import 'package:odf_flutter/odf_flutter.dart';

/// Abre todos os .odt/.ods/.odp de uma pasta com a leitura estruturada e
/// relata exceções, tempos lentos e um resumo.
///
/// Uso: `dart run tool/corpus_check.dart PASTA [-v] [--out SAIDA]`
///
/// Com `--out`, grava os documentos regravados em SAIDA (para validar com o
/// ODF Validator, por exemplo). Com `--fill`, em vez de regravar pelo modelo,
/// preenche o arquivo como modelo (sem dados) e grava o resultado.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/corpus_check.dart <pasta> [-v]');
    exit(64);
  }
  final verbose = args.contains('-v');
  final outIndex = args.indexOf('--out');
  final out =
      outIndex >= 0 && outIndex + 1 < args.length ? args[outIndex + 1] : null;
  if (out != null) Directory(out).createSync(recursive: true);
  final fill = args.contains('--fill');
  final files = Directory(args.first)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => RegExp(r'\.od[tsp]$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final failures = <String, String>{};
  final expected = <String, String>{};
  var ok = 0;
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final watch = Stopwatch()..start();
    try {
      final package = OdfDocument.open(file.readAsBytesSync());
      if (fill) {
        save(out, name, OdfDocument.fillTemplate(package, const {}));
        ok++;
        continue;
      }
      final summary = switch (package.type) {
        OdfDocumentType.text => () {
            final doc = OdfDocument.readRichText(package);
            save(out, name, OdfDocument.createRichText(doc));
            OdfConvert.toHtml(doc);
            OdfDocument.createRichText(
                OdfConvert.fromMarkdown(OdfConvert.toMarkdown(doc)));
            return '${doc.blocks.length} blocos';
          }(),
        OdfDocumentType.spreadsheet => () {
            final wb = OdfDocument.readWorkbook(package);
            save(out, name, OdfDocument.createWorkbook(wb));
            jsonEncode(OdfConvert.toJson(wb));
            for (final sheet in wb.sheets) {
              OdfConvert.fromCsv(OdfConvert.toCsv(sheet));
              jsonEncode(OdfConvert.toRecords(sheet, jsonSafe: true));
            }
            return '${wb.sheets.length} abas, ${wb.sheets.fold<int>(0, (n, s) => n + s.rows.length)} linhas';
          }(),
        OdfDocumentType.presentation => () {
            final p = OdfDocument.readPresentation(package);
            save(out, name, OdfDocument.createPresentation(p));
            return '${p.slides.length} slides';
          }(),
        _ => 'tipo ${package.type.name} (ignorado)',
      };
      OdfDocument.extractText(package);
      ok++;
      if (verbose || watch.elapsedMilliseconds > 2000) {
        print('ok   $name: $summary (${watch.elapsedMilliseconds} ms)');
      }
    } on OdfException catch (e) {
      // Erros esperados e claros (ex.: senha) contam à parte.
      expected[name] = e.message;
    } catch (e, stack) {
      failures[name] = '$e\n${stack.toString().split('\n').take(4).join('\n')}';
    }
  }

  print(
      '\n${files.length} arquivos: $ok ok, ${expected.length} recusados com OdfException, '
      '${failures.length} falhas inesperadas');
  expected.forEach((name, message) => print('  recusado $name: $message'));
  failures.forEach((name, error) => print('\nFALHA $name\n$error'));
  if (failures.isNotEmpty) exitCode = 1;
}

void save(String? dir, String name, List<int> bytes) {
  if (dir != null) File('$dir/$name').writeAsBytesSync(bytes);
}
