import 'dart:typed_data';

import '../controllers/land_parcel_controller.dart';

class PickedBoundaryFile {
  const PickedBoundaryFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
  bool get isKmz => name.toLowerCase().endsWith('.kmz');
}

abstract interface class LandParcelPlatformGateway
    implements ExternalFileOpener {
  Future<PickedBoundaryFile?> pickKmlOrKmz();
  Future<bool> saveAndOpen({
    required String fileName,
    required Uint8List bytes,
  });
}
