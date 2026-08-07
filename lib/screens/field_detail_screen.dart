import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import '../models/field_model.dart';

class FieldDetailScreen extends StatefulWidget {
  final FieldModel field;
  const FieldDetailScreen({super.key, required this.field});

  @override
  State<FieldDetailScreen> createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<FieldDetailScreen> {
  GoogleMapController? mapController;
  LocationData? currentLocation;
  final Location _location = Location();

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != PermissionStatus.granted) return;
    }

    final locationData = await _location.getLocation();
    setState(() {
      currentLocation = locationData;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nếu chưa có vị trí, hiện loading
    if (currentLocation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Tạo đối tượng camera cho bản đồ
    final cameraPosition = CameraPosition(
      target: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      zoom: 16,
    );

    // Tạo polygon nếu lô đất có dữ liệu
    Set<Polygon> polygons = {};
    if (widget.field.polygon.isNotEmpty) {
      polygons.add(
        Polygon(
          polygonId: PolygonId(widget.field.id),
          points: widget.field.polygon,
          fillColor: Colors.green.withOpacity(0.3),
          strokeColor: Colors.green,
          strokeWidth: 2,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.field.name),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Bản đồ Google Maps
          SizedBox(
            height: 300,
            child: GoogleMap(
              initialCameraPosition: cameraPosition,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              polygons: polygons,
              onMapCreated: (controller) {
                mapController = controller;
              },
              markers: {
                Marker(
                  markerId: const MarkerId('current'),
                  position: LatLng(
                    currentLocation!.latitude!,
                    currentLocation!.longitude!,
                  ),
                  infoWindow: const InfoWindow(title: 'Vị trí hiện tại'),
                ),
              },
            ),
          ),
          // Thông tin lô đất
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tên lô: ${widget.field.name}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Diện tích: ${widget.field.area} m²'),
                  Text('Cây trồng: ${widget.field.crop}'),
                  Text('Trạng thái: ${widget.field.status}'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          // Mở camera chụp ảnh (sẽ hướng dẫn sau)
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Chụp ảnh'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Xem nhật ký (sẽ hướng dẫn sau)
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('Nhật ký'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
