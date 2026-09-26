import 'dart:typed_data';

Future<void> applyPendingRestore() async {}

Future<void> scheduleLocalRestore(Uint8List bytes) async {
  throw UnsupportedError('Local restore requires a device filesystem.');
}

Future<String?> localRestoreStatus() async => null;
