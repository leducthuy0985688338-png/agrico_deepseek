import 'dart:convert';

class WorkspaceFailure implements Exception {
  const WorkspaceFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

class WorkspaceRejected extends WorkspaceFailure {
  const WorkspaceRejected(super.code);
}

typedef Json = Map<String, dynamic>;
Json jsonMap(Object? value) => Map<String, dynamic>.from(value as Map);
String canonical(Object? value) {
  Object? order(Object? v) => v is Map
      ? {
          for (final k in v.keys.map((e) => e.toString()).toList()..sort())
            k: order(v[k]),
        }
      : v is List
      ? v.map(order).toList()
      : v;
  return jsonEncode(order(value));
}

abstract interface class WorkspaceTransport {
  Future<Json> send(String farm, String uid, String operation, Json command);
  Future<Json> upload(
    String farm,
    String uid,
    List<int> bytes,
    String name, {
    bool snapshot = false,
  });
  Future<List<int>> download(String path);
}

abstract interface class WorkspaceStore {
  Future<List<Json>> pending(String farm, String uid);
  Future<void> enqueue(String farm, String uid, Json command);
  Future<void> accept(String farm, String uid, String id, Json response);
  Future<void> reject(String farm, String uid, String id, String error);
  Future<void> discard(String farm, String uid, String id);
  Future<List<Json>> records(String farm, String uid);
  Future<void> replace(
    String farm,
    String uid,
    List<Json> records,
    int generation,
  );
  Future<Json?> value(String farm, String uid, String key);
  Future<void> putValue(String farm, String uid, String key, Json value);
  Future<void> clearCache(String farm, String uid);
}

/// Proposed reconciliation only; this does not write any cash or debt ledger.
class AdvanceSettlementBalance {
  AdvanceSettlementBalance(String received, String spent, this.currency) {
    if (!['VND', 'LAK'].contains(currency)) {
      throw const WorkspaceFailure('invalidCurrency');
    }
    BigInt units(String text) {
      if (!RegExp(r'^(0|[1-9]\d{0,14})(\.\d{1,4})?$').hasMatch(text)) {
        throw const WorkspaceFailure('invalidAmount');
      }
      final parts = text.split('.');
      return BigInt.parse(parts[0]) * BigInt.from(10000) +
          BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(4, '0'));
    }

    difference = units(received) - units(spent);
  }
  final String currency;
  late final BigInt difference;
  bool get returnRequired => difference > BigInt.zero;
  bool get additionalRequired => difference < BigInt.zero;
  String get amount {
    final digits = difference.abs().toString().padLeft(5, '0');
    return '${digits.substring(0, digits.length - 4)}.${digits.substring(digits.length - 4)}'
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

String attachmentFileName(Json file) {
  final original = (file['name'] as String? ?? 'attachment')
      .split(RegExp(r'[/\\]'))
      .last;
  var safe = original
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (safe.isEmpty) safe = 'attachment';
  final extension = safe.split('.').last.toLowerCase();
  if (!{
    'pdf',
    'docx',
    'xlsx',
    'csv',
    'txt',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'heic',
    'kml',
    'kmz',
  }.contains(extension)) {
    safe += '.bin';
  }
  return 'AGRICO-${(file['sha256'] as String).substring(0, 12)}-$safe';
}
