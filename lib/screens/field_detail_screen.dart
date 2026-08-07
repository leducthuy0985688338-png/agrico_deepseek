import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../providers/machine_provider.dart';
import '../widgets/photo_gallery.dart';
import 'machine_assignment_screen.dart';

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

  // Provider để cập nhật dữ liệu
  late FieldProvider _fieldProvider;
  late MachineProvider _machineProvider;

  @override
  void initState() {
    super.initState();
    _fieldProvider = FieldProvider();
    _machineProvider = MachineProvider();
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

  // Hàm thêm ảnh mới
  void _addPhoto(String photoPath) {
    _fieldProvider.addPhotoToField(widget.field.id, photoPath);
    final updatedField = _fieldProvider.getFieldById(widget.field.id);
    if (updatedField != null) {
      setState(() {
        widget.field.photoPaths.clear();
        widget.field.photoPaths.addAll(updatedField.photoPaths);
      });
    }
  }

  // Lấy danh sách máy đang làm trên lô này
  List<dynamic> getMachinesOnField() {
    return _machineProvider.getMachinesByField(widget.field.id);
  }

  @override
  Widget build(BuildContext context) {
    if (currentLocation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cameraPosition = CameraPosition(
      target: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      zoom: 16,
    );

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

    // Lấy danh sách máy trên lô
    final machinesOnField = getMachinesOnField();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.field.name),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bản đồ
            SizedBox(
              height: 250,
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
            // Thông tin lô
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.field.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Diện tích: ${widget.field.area} m²'),
                  Text('Cây trồng: ${widget.field.crop}'),
                  Text('Trạng thái: ${widget.field.status}'),
                  const Divider(height: 24),

                  // ----- DANH SÁCH MÁY TRÊN LÔ -----
                  if (machinesOnField.isNotEmpty) ...[
                    const Text(
                      'Máy móc đang làm trên lô:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...machinesOnField.map((machine) {
                      return Card(
                        color: Colors.green.shade50,
                        child: ListTile(
                          leading: const Icon(
                            Icons.agriculture,
                            color: Colors.green,
                          ),
                          title: Text(machine.name),
                          subtitle: Text(
                            '${machine.type} - ${machine.status} | Giờ: ${machine.totalHours}h',
                          ),
                          trailing: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                  ],

                  // ----- PHẦN ẢNH -----
                  PhotoGallery(
                    photoPaths: widget.field.photoPaths,
                    onAddPhoto: _addPhoto,
                  ),
                  const SizedBox(height: 20),

                  // ================================================
                  // ==== PHẦN NÚT CHỨC NĂNG (QUAN TRỌNG NHẤT) ====
                  // ================================================
                  Row(
                    children: [
                      // Nút GÁN MÁY
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Mở màn hình gán máy
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MachineAssignmentScreen(),
                              ),
                            ).then((_) {
                              // Refresh lại khi quay về
                              setState(() {});
                            });
                          },
                          icon: const Icon(Icons.agriculture),
                          label: const Text('Gán máy'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Nút NHẬT KÝ MÁY
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Mở nhật ký máy trên lô này
                            _showMachineLogDialog();
                          },
                          icon: const Icon(Icons.history),
                          label: const Text('Nhật ký máy'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Nút CHI PHÍ (tùy chọn)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Thêm chi phí (sẽ thêm sau)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tính năng đang phát triển'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.money),
                          label: const Text('Chi phí'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Thu hoạch (sẽ thêm sau)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tính năng đang phát triển'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.assignment),
                          label: const Text('Thu hoạch'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // ================================================
                  // ==== KẾT THÚC PHẦN NÚT CHỨC NĂNG ============
                  // ================================================
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Hàm hiển thị hộp thoại nhật ký máy
  void _showMachineLogDialog() {
    // Lấy tất cả máy có lịch sử trên lô này
    final allMachines = _machineProvider.machines;
    final logs = <Map<String, dynamic>>[];

    for (var machine in allMachines) {
      for (var record in machine.fieldHistory) {
        if (record.fieldId == widget.field.id) {
          logs.add({
            'machineName': machine.name,
            'startDate': record.startDate,
            'endDate': record.endDate,
            'hoursWorked': record.hoursWorked,
            'fuelUsed': record.fuelUsed,
            'operator': record.operatorName ?? 'Chưa có',
          });
        }
      }
    }

    // Sắp xếp theo ngày mới nhất
    logs.sort((a, b) => b['startDate'].compareTo(a['startDate']));

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Nhật ký máy - ${widget.field.name}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: logs.isEmpty
                ? const Center(
                    child: Text('Chưa có máy nào làm việc trên lô này'),
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (ctx, index) {
                      final log = logs[index];
                      return Card(
                        child: ListTile(
                          title: Text(log['machineName']),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ngày bắt đầu: ${log['startDate'].day}/${log['startDate'].month}/${log['startDate'].year}',
                              ),
                              if (log['endDate'] != null)
                                Text(
                                  'Ngày kết thúc: ${log['endDate'].day}/${log['endDate'].month}/${log['endDate'].year}',
                                ),
                              Text('Giờ làm: ${log['hoursWorked']}h'),
                              Text('Nhiên liệu: ${log['fuelUsed']}L'),
                              Text('Người vận hành: ${log['operator']}'),
                            ],
                          ),
                          leading: const Icon(
                            Icons.history,
                            color: Colors.orange,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }
}
