import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/workspace.dart';

class WorkspaceDocumentExport {
  static List<int> create(Json record, int language) {
    String text(Object? v) => XmlText(v?.toString() ?? '').toXmlString();
    String p(Object? value) =>
        '<w:p><w:r><w:t xml:space="preserve">${text(value)}</w:t></w:r></w:p>';
    final content = jsonMap(record['content']);
    final t = jsonMap(content['template']);
    final rows = [
      p((t['names'] as List)[language]),
      p(record['code']),
      p('${record['creatorName']} · ${record['createdAt']}'),
      p(
        '${record['state']} · ${jsonMap(record['lastEvent'] ?? {})['name'] ?? ''}',
      ),
    ];
    for (final raw in t['fields'] as List) {
      final f = jsonMap(raw);
      rows.add(
        p(
          '${(f['label'] as List)[language]}: ${jsonMap(content['fields'])[f['key']] ?? ''}',
        ),
      );
    }
    rows.add(
      p(
        [
          'Đề nghị hành chính; chưa phải chứng từ thu chi.',
          'Administrative request; not a cash posting.',
          'ໃບສະເໜີ; ບໍ່ແມ່ນການລົງບັນຊີ.',
        ][language],
      ),
    );
    rows.add(
      p(
        [
          'Người đề nghị                         Người duyệt (ký trực tiếp)',
          'Requester                             Approver (signature)',
          'ຜູ້ສະເໜີ                               ຜູ້ອະນຸມັດ (ລາຍເຊັນ)',
        ][language],
      ),
    );
    if (t['id'] == 'advanceSettlement') {
      final f = jsonMap(content['fields']);
      final balance = AdvanceSettlementBalance(
        f['received'] as String,
        f['spent'] as String,
        f['currency'] as String,
      );
      final label = balance.returnRequired
          ? ['Đề nghị hoàn trả', 'Proposed return', 'ສະເໜີຄືນເງິນ']
          : balance.additionalRequired
          ? [
              'Đề nghị chi bổ sung',
              'Proposed additional payment',
              'ສະເໜີຈ່າຍເພີ່ມ',
            ]
          : ['Đã cân đối đề nghị', 'Proposed amounts balanced', 'ສະເໜີສົມດຸນ'];
      rows.add(p('${label[language]}: ${balance.amount} ${balance.currency}'));
    }
    final files = {
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/document.xml':
          '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${rows.join()}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1417"/></w:sectPr></w:body></w:document>',
    };
    final archive = Archive();
    for (final f in files.entries) {
      final bytes = utf8.encode(f.value);
      archive.addFile(ArchiveFile(f.key, bytes.length, bytes));
    }
    return ZipEncoder().encode(archive)!;
  }
}
