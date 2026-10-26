import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:excel/excel.dart';

List<int> encodeReportWorkbook(Excel workbook) {
  final archive = ZipDecoder().decodeBytes(workbook.encode()!);
  XmlDocument read(String path) => XmlDocument.parse(
    utf8.decode(archive.findFile(path)!.content as List<int>),
  );
  final book = read('xl/workbook.xml');
  final rels = read('xl/_rels/workbook.xml.rels');
  final targets = {
    for (final r in rels.rootElement.childElements)
      r.getAttribute('Id'): r.getAttribute('Target')!,
  };
  final modified = <String, List<int>>{};
  for (final sheet in book.findAllElements('sheet')) {
    final target = targets[sheet.getAttribute('r:id')];
    if (target == null) continue;
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final document = read(path);
    final root = document.rootElement;
    root.children.removeWhere(
      (n) => n is XmlElement && n.name.local == 'sheetViews',
    );
    final views = XmlElement(XmlName('sheetViews'), [], [
      XmlElement(
        XmlName('sheetView'),
        [XmlAttribute(XmlName('workbookViewId'), '0')],
        [
          XmlElement(XmlName('pane'), [
            XmlAttribute(XmlName('ySplit'), '1'),
            XmlAttribute(XmlName('topLeftCell'), 'A2'),
            XmlAttribute(XmlName('activePane'), 'bottomLeft'),
            XmlAttribute(XmlName('state'), 'frozen'),
          ]),
        ],
      ),
    ]);
    final dimension = root.childElements
        .where((e) => e.name.local == 'dimension')
        .firstOrNull;
    root.children.insert(
      dimension == null ? 0 : root.children.indexOf(dimension) + 1,
      views,
    );
    if (sheet.getAttribute('name') != 'THONG TIN') {
      final range = dimension?.getAttribute('ref');
      if (range != null) {
        root.children.removeWhere(
          (n) => n is XmlElement && n.name.local == 'autoFilter',
        );
        final data = root.childElements.firstWhere(
          (e) => e.name.local == 'sheetData',
        );
        root.children.insert(
          root.children.indexOf(data) + 1,
          XmlElement(XmlName('autoFilter'), [
            XmlAttribute(XmlName('ref'), range),
          ]),
        );
      }
    }
    modified[path] = utf8.encode(document.toXmlString());
  }
  final out = Archive();
  for (final file in archive) {
    final data = modified[file.name] ?? file.content as List<int>;
    out.addFile(ArchiveFile(file.name, data.length, data));
  }
  return ZipEncoder().encode(out)!;
}
