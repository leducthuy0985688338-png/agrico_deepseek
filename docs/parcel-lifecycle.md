# Lô đất qua khai hoang, phân mảnh và canh tác

- **Lô nguồn** giữ `LandParcel.id`, mã và từng phiên bản ranh giới. Trên màn **Hiện trạng và phân mảnh**, ghi một mốc *Trước khai hoang* tham chiếu R1/R2… và diện tích đo từ chính phiên bản đó. Không sao chép hoặc sửa geometry khi ghi mốc.
- Ghi *Sau khai hoang* và *Canh tác* bằng phiên bản ranh giới tương ứng. Nếu đo lại ranh giới, dùng quy trình GPS/KML và revision hiện có trước khi ghi mốc; mốc cũ vẫn trỏ phiên bản cũ.
- Khi tách/gộp, tạo lô mới bằng mã `…-L00001` rồi ghi liên kết **lô nguồn → lô mới** với loại và diện tích chuyển. Một lô nguồn có thể sinh nhiều lô, một lô mới có thể lấy từ nhiều nguồn. Mã/ID nguồn không đổi. Bản liên kết từ giai đoạn này là dữ liệu nghiệp vụ riêng, không thay thế quan hệ `PreCompensationParcel → LandParcel` cũ.
- Mỗi công việc khai hoang hoặc canh tác có ngày, mô tả, diện tích tùy chọn, máy và nhân công được chọn. Nguồn lực lưu trong SQLite theo trang trại với ID ổn định, loại, mã và tên. Giao diện nguồn lực mẫu cũ không phải danh mục cho tính năng này. Lưu công việc và các liên kết trong một giao dịch; không thể chọn nguồn lực khác trang trại hoặc sai loại.
- Những thửa/hộ đã lưu trước Sprint 17 vẫn nằm trong SQLite và bản sao lưu; giao diện v2 ngừng nhập và hiển thị dữ liệu hộ. Không tự cấp lại mã H cũ. Việc xóa dữ liệu hộ cũ cần quy trình xuất/đối soát riêng sau này.

Liên kết lô đã tồn tại trước đó vẫn cho nhập thủ công; luồng tách lô mới ở dưới tính diện tích từ đường cắt được xem trước. Chưa tính công/chi phí hoặc tự gộp nhiều polygon.

## Tách lô bằng đường cắt

Trên **Hiện trạng và phân mảnh → Tách lô theo ranh giới**, chạm hai điểm trên đường bao lô nguồn. Sơ đồ ranh giới tại đây dùng tọa độ WGS84 của lô, chưa có lớp ảnh vệ tinh nền. Đường cắt phải nằm trong lô, không xuyên qua cạnh hoặc đỉnh khác. Màn hình xem trước diện tích hai lô; nhập hai tên rồi lưu.

Ứng dụng đối chiếu mã quốc gia/tỉnh/huyện/bản với danh mục hiện hành, kiểm tra phiên bản ranh giới nguồn chưa đổi, cấp hai mã `L00001…` trong cùng phạm vi bản và ghi hai lô, hai SpatialFeature/R1 và hai liên kết phân mảnh trong **một giao dịch**. Nếu bước nào lỗi, không lưu lô/mã/liên kết nào. Lô nguồn và toàn bộ revision cũ vẫn còn nguyên; lô mới bắt đầu ở trạng thái ranh giới nháp, cần đo/xác minh tại hiện trường. Có thể tiếp tục tách một lô con thành các lô nhỏ hơn. Đường cắt nhiều nhánh, đa giác nhiều phần hoặc lô cũ không có địa bàn khớp danh mục phải được đối soát riêng.
