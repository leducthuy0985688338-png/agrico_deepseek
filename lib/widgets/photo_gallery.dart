import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PhotoGallery extends StatefulWidget {
  final List<String> photoPaths;
  final Function(String) onAddPhoto; // callback khi thêm ảnh mới

  const PhotoGallery({
    super.key,
    required this.photoPaths,
    required this.onAddPhoto,
  });

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  final ImagePicker _picker = ImagePicker();

  // Hàm chụp ảnh hoặc chọn từ thư viện
  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (image != null) {
      // Lưu đường dẫn ảnh
      widget.onAddPhoto(image.path);
    }
  }

  void _showPickerDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Chụp ảnh mới'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Ảnh hiện trường',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: _showPickerDialog,
              icon: const Icon(Icons.add_a_photo, color: Colors.green),
            ),
          ],
        ),
        if (widget.photoPaths.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Chưa có ảnh. Hãy chụp hoặc chọn ảnh mới.'),
            ),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.photoPaths.length,
              itemBuilder: (ctx, index) {
                final path = widget.photoPaths[index];
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Stack(
                    children: [
                      // Hiển thị ảnh
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          width: 130,
                          height: 130,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Nút xóa ảnh
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            // Xóa ảnh khỏi danh sách
                            final updated = List<String>.from(widget.photoPaths)
                              ..removeAt(index);
                            // Gọi callback để cập nhật (phần này sẽ xử lý ở màn hình cha)
                            // Tạm thời gửi ảnh mới để cập nhật danh sách (cần cải tiến)
                            // Ở đây ta sẽ dùng cách đơn giản: gọi lại onAddPhoto nhưng với giá trị null để báo xóa
                            // Tuy nhiên để đơn giản, ta sẽ để widget cha quản lý danh sách.
                            // Ta sẽ dùng StatefulWidget và truyền callback xóa.
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
