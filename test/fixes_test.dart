import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:odf_flutter/odf_flutter.dart';
import 'package:test/test.dart';

import 'advanced_test.dart' show png, unzip;

List<int> zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  positionTests();

  test('extractText inclui títulos, tabulações, quebras e espaços, sem notas',
      () {
    final doc = OdfRichTextDocument()
      ..heading('Título')
      ..rich([const OdfSpan('a  b\tc\nd'), OdfNote.text('nota')])
      ..table([
        ['x', 'y'],
      ]);
    final text = OdfDocument.extractText(
        OdfDocument.open(OdfDocument.createRichText(doc)));
    expect(text, 'Título\na  b\tc\nd\nx\ny');
  });

  test('notas de rodapé e de fim fazem ida e volta', () {
    final doc = OdfRichTextDocument()
      ..rich([
        const OdfSpan('Texto'),
        OdfNote([
          OdfParagraph.text('Fonte: IBGE',
              style: const OdfTextStyle(italic: true))
        ]),
        const OdfSpan(' e mais'),
        OdfNote.text('Ver anexo', endnote: true),
        OdfNote.text('Terceira'),
      ]);
    final withLabel = OdfRichTextDocument()
      ..rich([
        OdfNote([OdfParagraph.text('x')], citation: '*')
      ]);

    final read = OdfDocument.readRichText(
        OdfDocument.open(OdfDocument.createRichText(doc)));
    final notes = (read.blocks.single as OdfParagraph)
        .inlines
        .whereType<OdfNote>()
        .toList();
    expect(notes, hasLength(3));
    expect(notes[0].endnote, isFalse);
    expect((notes[0].body.single as OdfParagraph).inlines.single,
        const OdfSpan('Fonte: IBGE', style: OdfTextStyle(italic: true)));
    expect(notes[1].endnote, isTrue);
    expect(notes[1].bodyText, 'Ver anexo');
    expect(read.blocks.single.plainText, 'Texto e mais');

    final labeled = OdfDocument.readRichText(
        OdfDocument.open(OdfDocument.createRichText(withLabel)));
    expect(
        ((labeled.blocks.single as OdfParagraph).inlines.single as OdfNote)
            .citation,
        '*');
  });

  test('documento protegido por senha gera mensagem clara', () {
    final bytes = zip({
      'mimetype': 'application/vnd.oasis.opendocument.text',
      'META-INF/manifest.xml':
          '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">'
              '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml">'
              '<manifest:encryption-data manifest:checksum-type="SHA1" manifest:checksum="x"/>'
              '</manifest:file-entry></manifest:manifest>',
      'content.xml': '\u0000ÿ binário',
    });
    expect(
      () => OdfDocument.open(bytes),
      throwsA(isA<OdfException>()
          .having((e) => e.message, 'message', contains('senha'))),
    );
  });

  test(
      'ODP preserva estilo do título, do texto das formas e das caixas de texto',
      () {
    final presentation = OdfPresentation(slides: [
      OdfSlide(
        title: 'Título',
        titleStyle: OdfTextStyle(color: OdfColor.hex('#aa0000'), italic: true),
        elements: [
          OdfShape(OdfShapeKind.rectangle,
              frame: const OdfFrame(1, 1, 4, 2),
              text: 'Forma',
              textStyle: const OdfTextStyle(
                  bold: true, fontSize: 18, color: OdfColor.white)),
          OdfTextBox.text('Caixa', style: const OdfTextStyle(underline: true)),
        ],
      ),
      OdfSlide(title: 'Simples'),
    ]);
    final read = OdfDocument.readPresentation(
        OdfDocument.open(OdfDocument.createPresentation(presentation)));
    final slide = read.slides.first;
    expect(slide.titleStyle,
        OdfTextStyle(color: OdfColor.hex('#aa0000'), italic: true));
    expect((slide.elements[0] as OdfShape).textStyle,
        const OdfTextStyle(bold: true, fontSize: 18, color: OdfColor.white));
    final box = slide.elements[1] as OdfTextBox;
    expect(
        ((box.blocks.single as OdfParagraph).inlines.single as OdfSpan).style,
        const OdfTextStyle(underline: true));
    expect(read.slides[1].titleStyle, OdfTextStyle.plain);
  });

  test('imagens com bytes iguais são gravadas uma vez', () {
    final doc = OdfRichTextDocument()
      ..image(png)
      ..image(List.of(png))
      ..image([...png, 0]);
    final files = unzip(OdfDocument.createRichText(doc));
    expect(files.keys.where((k) => k.startsWith('Pictures/')),
        ['Pictures/image1.png', 'Pictures/image2.png']);
  });
}

void positionTests() {
  group('Posições reais nas planilhas', () {
    OdfWorksheet roundTrip(OdfWorksheet sheet) =>
        OdfDocument.readWorkbook(OdfDocument.open(
                OdfDocument.createWorkbook(OdfWorkbook(sheets: [sheet]))))
            .sheets
            .single;

    test('at() aponta para a coluna certa abaixo e à direita de mesclagens',
        () {
      final sheet = OdfWorksheet('S')
        ..set('A1', 'mesclada')
        ..set('D1', 'd1')
        ..set('D2', 'd2')
        ..set('C3', 'c3');
      sheet.at('A1')!
        ..colSpan = 3
        ..rowSpan = 2;
      final read = roundTrip(sheet);
      expect(read.at('A1')!.value, const OdfStringValue('mesclada'));
      expect((read.at('A1')!.colSpan, read.at('A1')!.rowSpan), (3, 2));
      expect(read.at('D1')!.value, const OdfStringValue('d1'));
      expect(read.at('D2')!.value, const OdfStringValue('d2'));
      expect(read.at('C3')!.value, const OdfStringValue('c3'));
      expect(read.at('B2')!.value, const OdfEmptyValue());
      expect(read.visibleAt('B2'), same(read.at('A1')));
      expect(read.visibleAt('D2'), same(read.at('D2')));
      expect(read.columnCount, 4);
    });

    test('conteúdo oculto sob mesclagem é preservado', () {
      final sheet = OdfWorksheet('S')
        ..set('A1', 'origem')
        ..set('B1', 'oculto');
      sheet.at('A1')!.colSpan = 2;
      final content = utf8.decode(
          unzip(OdfDocument.createWorkbook(OdfWorkbook(sheets: [sheet])))[
              'content.xml']!);
      expect(
          content,
          contains(
              '<table:covered-table-cell office:value-type="string"><text:p>oculto</text:p>'));
      expect(roundTrip(sheet).at('B1')!.value, const OdfStringValue('oculto'));
    });

    test('células vazias consecutivas são compactadas', () {
      final sheet = OdfWorksheet('S')
        ..set('A1', 1)
        ..set('Z1', 2);
      final content = utf8.decode(
          unzip(OdfDocument.createWorkbook(OdfWorkbook(sheets: [sheet])))[
              'content.xml']!);
      expect(content, contains('table:number-columns-repeated="24"'));
      expect(roundTrip(sheet).at('Z1')!.value, const OdfNumberValue(2));
    });

    test(
        'dados além do limite de linhas geram OdfException em vez de esgotar a memória',
        () {
      const content = '<?xml version="1.0" encoding="UTF-8"?>'
          '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
          'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
          'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.3">'
          '<office:body><office:spreadsheet><table:table table:name="P">'
          '<table:table-row table:number-rows-repeated="16777212"><table:table-cell/></table:table-row>'
          '<table:table-row><table:table-cell office:value-type="float" office:value="11"/></table:table-row>'
          '</table:table></office:spreadsheet></office:body></office:document-content>';
      final package = OdfDocument.open(OdfRepositoryImpl()
          .create(type: OdfDocumentType.spreadsheet, contentXml: content));
      expect(
          () => OdfDocument.readWorkbook(package),
          throwsA(isA<OdfException>()
              .having((e) => e.message, 'message', contains('maxRows'))));
    });
  });

  test('modelos (.ott) são abertos como o tipo base', () {
    final bytes = zip({
      'mimetype': 'application/vnd.oasis.opendocument.text-template',
      'content.xml':
          '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
              'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">'
              '<office:body><office:text><text:p>Modelo</text:p></office:text></office:body></office:document-content>',
    });
    final package = OdfDocument.open(bytes);
    expect(package.type, OdfDocumentType.text);
    expect(package.isTemplate, isTrue);
    expect(OdfDocument.readRichText(package).plainText, 'Modelo');
  });
}
