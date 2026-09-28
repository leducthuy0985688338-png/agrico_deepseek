# Lô đất qua khai hoang, phân mảnh và canh tác

- **Lô nguồn** giữ `LandParcel.id`, mã và từng phiên bản ranh giới. Trên màn **Hiện trạng và phân mảnh**, ghi một mốc *Trước khai hoang* tham chiếu R1/R2… và diện tích đo từ chính phiên bản đó. Không sao chép hoặc sửa geometry khi ghi mốc.
- Ghi *Sau khai hoang* và *Canh tác* bằng phiên bản ranh giới tương ứng. Nếu đo lại ranh giới, dùng quy trình GPS/KML và revision hiện có trước khi ghi mốc; mốc cũ vẫn trỏ phiên bản cũ.
- Khi tách/gộp, tạo lô mới bằng mã `…-L00001` rồi ghi liên kết **lô nguồn → lô mới** với loại và diện tích chuyển. Một lô nguồn có thể sinh nhiều lô, một lô mới có thể lấy từ nhiều nguồn. Mã/ID nguồn không đổi. Bản liên kết từ giai đoạn này là dữ liệu nghiệp vụ riêng, không thay thế quan hệ `PreCompensationParcel → LandParcel` cũ.
- Mỗi công việc khai hoang hoặc canh tác có ngày, mô tả, diện tích tùy chọn, máy và nhân công được chọn. Nguồn lực lưu trong SQLite theo trang trại với ID ổn định, loại, mã và tên. Giao diện nguồn lực mẫu cũ không phải danh mục cho tính năng này. Lưu công việc và các liên kết trong một giao dịch; không thể chọn nguồn lực khác trang trại hoặc sai loại.
- Những thửa/hộ đã lưu trước Sprint 17 vẫn nằm trong SQLite và bản sao lưu; giao diện v2 ngừng nhập và hiển thị dữ liệu hộ. Không tự cấp lại mã H cũ. Việc xóa dữ liệu hộ cũ cần quy trình xuất/đối soát riêng sau này.

Giai đoạn này ghi lịch sử và liên kết thủ công; không tự suy diễn diện tích từ polygon giao cắt, không tự chia hình học và không tính công/chi phí. Đó là các quy trình riêng trước khi coi diện tích chuyển là xác nhận kỹ thuật.
