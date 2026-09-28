# Lô đất qua khai hoang, phân mảnh và canh tác

- **Lô nguồn** giữ `LandParcel.id`, mã và từng phiên bản ranh giới. Trên màn **Hiện trạng và phân mảnh**, ghi một mốc *Trước khai hoang* tham chiếu R1/R2… và diện tích đo từ chính phiên bản đó. Không sao chép hoặc sửa geometry khi ghi mốc.
- Ghi *Sau khai hoang* và *Canh tác* bằng phiên bản ranh giới tương ứng. Nếu đo lại ranh giới, dùng quy trình GPS/KML và revision hiện có trước khi ghi mốc; mốc cũ vẫn trỏ phiên bản cũ.
- Khi tách/gộp, tạo lô mới bằng mã `…-L00001` rồi ghi liên kết **lô nguồn → lô mới** với loại và diện tích chuyển. Một lô nguồn có thể sinh nhiều lô, một lô mới có thể lấy từ nhiều nguồn. Mã/ID nguồn không đổi. Bản liên kết từ giai đoạn này là dữ liệu nghiệp vụ riêng, không thay thế quan hệ `PreCompensationParcel → LandParcel` cũ.
- Mỗi công việc khai hoang hoặc canh tác có ngày, mô tả, diện tích tùy chọn, máy và nhân công được chọn. Nguồn lực lưu trong SQLite theo trang trại với ID ổn định, loại, mã và tên. Giao diện nguồn lực mẫu cũ không phải danh mục cho tính năng này. Lưu công việc và các liên kết trong một giao dịch; không thể chọn nguồn lực khác trang trại hoặc sai loại.
- Những thửa/hộ đã lưu trước Sprint 17 vẫn nằm trong SQLite và bản sao lưu; giao diện v2 ngừng nhập và hiển thị dữ liệu hộ. Không tự cấp lại mã H cũ. Việc xóa dữ liệu hộ cũ cần quy trình xuất/đối soát riêng sau này.

Liên kết lô đã tồn tại trước đó vẫn cho nhập thủ công; luồng tách lô mới ở dưới tính diện tích từ đường cắt được xem trước. Chưa tính công/chi phí hoặc tự gộp nhiều polygon.

## Tách lô bằng đường cắt

Trên **Hiện trạng và phân mảnh → Tách lô theo ranh giới**, chọn mảnh đang cắt, chạm điểm đầu trên biên và các điểm uốn ở bên trong. Bấm **Chọn điểm cuối trên biên** rồi chạm điểm cuối; các điểm đã vẽ được giữ nguyên trong lúc thêm góc uốn. Sau mỗi đường cắt, chọn một mảnh hiện có để cắt tiếp. Danh sách ô tên và diện tích tăng theo số mảnh cuối cùng; đặt tên cho từng mảnh rồi lưu toàn bộ một lần. Có thể vẽ lại đường cắt đang làm hoặc xóa toàn bộ bản xem trước. Sơ đồ dùng tọa độ WGS84, chưa có lớp ảnh vệ tinh nền. Mỗi đường cắt phải nằm trong mảnh đã chọn, không tự cắt hoặc xuyên qua cạnh/đỉnh khác.

Ứng dụng đối chiếu địa bàn với danh mục, kiểm tra phiên bản và tính nhất quán ranh giới nguồn. Tất cả mảnh cuối cùng nhận mã `L00001…` riêng trong phạm vi bản, SpatialFeature/R1 riêng và liên kết trực tiếp với lô nguồn trong **một giao dịch**. Nếu một bước lỗi, không lưu bất kỳ mảnh, mã hay liên kết nào. Lô nguồn cùng các revision cũ được giữ nguyên nhưng chuyển sang **ngừng hoạt động** để không tính trùng diện tích. Những lô mới có ranh giới nháp, cần đo/xác minh tại hiện trường. Không cho tách lại cùng lô nguồn; vẫn có thể tách một lô con trong một lần thao tác khác. Đường cắt nhiều nhánh hoặc đa giác nhiều phần cần quy trình riêng.
