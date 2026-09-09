import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'land_parcel_platform.dart';

class MobileLandParcelPlatformGateway implements LandParcelPlatformGateway {
  const MobileLandParcelPlatformGateway();

  static const MethodChannel _googleEarthChannel = MethodChannel(
    'com.agrico.erp/google_earth',
  );

  @override
  Future<PickedBoundaryFile?> pickKmlOrKmz() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kml', 'kmz'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final selected = result.files.single;
    final bytes =
        selected.bytes ??
        (selected.path == null
            ? null
            : await File(selected.path!).readAsBytes());

    return bytes == null
        ? null
        : PickedBoundaryFile(name: selected.name, bytes: bytes);
  }

  @override
  Future<bool> open({required String fileName, required Uint8List bytes}) =>
      saveAndOpen(fileName: fileName, bytes: bytes);

  @override
  Future<bool> saveAndOpen({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final safeName = path.basename(fileName);
      final file = File(path.join(directory.path, safeName));

      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFile.open(file.path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openInGoogleEarth({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final safeName = path.basename(fileName);
      final file = File(path.join(directory.path, safeName));

      await file.writeAsBytes(bytes, flush: true);

      final opened = await _googleEarthChannel.invokeMethod<bool>(
        'openGoogleEarth',
        <String, Object?>{'filePath': file.path},
      );

      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
