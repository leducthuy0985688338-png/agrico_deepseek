# Lô đất qua khai hoang, phân mảnh và canh tác

- **Lô nguồn** giữ `LandParcel.id`, mã và từng phiên bản ranh giới. Trên màn **Hiện trạng và phân mảnh**, ghi một mốc *Trước khai hoang* tham chiếu R1/R2… và diện tích đo từ chính phiên bản đó. Không sao chép hoặc sửa geometry khi ghi mốc.
- Ghi *Sau khai hoang* và *Canh tác* bằng phiên bản ranh giới tương ứng. Nếu đo lại ranh giới, dùng quy trình GPS/KML và revision hiện có trước khi ghi mốc; mốc cũ vẫn trỏ phiên bản cũ.
- Khi tách/gộp, tạo lô mới bằng mã `…-L00001` rồi ghi liên kết **lô nguồn → lô mới** với loại và diện tích chuyển. Một lô nguồn có thể sinh nhiều lô, một lô mới có thể lấy từ nhiều nguồn. Mã/ID nguồn không đổi. Bản liên kết từ giai đoạn này là dữ liệu nghiệp vụ riêng, không thay thế quan hệ `PreCompensationParcel → LandParcel` cũ.
- Mỗi công việc khai hoang hoặc canh tác có ngày, mô tả, diện tích tùy chọn, máy và nhân công được chọn. Nguồn lực lưu trong SQLite theo trang trại với ID ổn định, loại, mã và tên. Giao diện nguồn lực mẫu cũ không phải danh mục cho tính năng này. Lưu công việc và các liên kết trong một giao dịch; không thể chọn nguồn lực khác trang trại hoặc sai loại.
- Những thửa/hộ đã lưu trước Sprint 17 vẫn nằm trong SQLite và bản sao lưu; giao diện v2 ngừng nhập và hiển thị dữ liệu hộ. Không tự cấp lại mã H cũ. Việc xóa dữ liệu hộ cũ cần quy trình xuất/đối soát riêng sau này.

Liên kết lô đã tồn tại trước đó vẫn cho nhập thủ công; luồng tách lô mới ở dưới tính diện tích từ đường cắt được xem trước. Chưa tính công/chi phí hoặc tự gộp nhiều polygon.

## Tách lô bằng đường cắt

Trên **Hiện trạng và phân mảnh → Tách lô theo ranh giới**, chọn mảnh đang cắt rồi vẽ đa giác khép kín như Google Earth. Vùng nháp được tô màu và nối trực quan về điểm đầu sau mỗi lần chạm. Nếu đa giác nằm trọn bên trong lô, phần đất còn lại giữ nguyên biên ngoài và lưu vòng rỗng đúng bằng ranh giới lô mới. Nếu hình bắt đầu trên biên, đi dọc biên rồi cắt qua lô đến một điểm biên khác, ứng dụng dùng phần trong lô làm đường chia, lấy cạnh gốc để khép kín hai mảnh. Bấm **Khép kín và xem trước** sau khi vẽ; chạm lại điểm đầu cũng có thể kết thúc. Những hình tự cắt, vượt ra ngoài biên, chạm biên chỉ ở một điểm hoặc giao với lỗ đã có sẽ bị từ chối để tránh chồng lấn diện tích.

Vùng vẽ phóng riêng mảnh đang chọn để thao tác trên mảnh nhỏ; sơ đồ tổng thể hiển thị mọi mảnh theo tọa độ chung và cho chạm vào mảnh để chọn. Sau mỗi lần chia, có thể chọn mảnh khác để cắt tiếp trước khi lưu. Danh sách tên và diện tích tăng theo số mảnh cuối cùng. Ứng dụng chỉ chấp nhận đường cắt nằm trong lô, không tự cắt, và kiểm tra tổng diện tích trước khi lưu. Sơ đồ dùng WGS84, chưa có lớp ảnh vệ tinh nền. Các đa giác cuối cùng được khép kín bằng đường cắt cùng các cạnh nguồn, không tạo khe hở giữa hai mảnh.


Ứng dụng đối chiếu địa bàn với danh mục, kiểm tra phiên bản và tính nhất quán ranh giới nguồn. Tất cả mảnh cuối cùng nhận mã `L00001…` riêng trong phạm vi bản, SpatialFeature/R1 riêng và liên kết trực tiếp với lô nguồn trong **một giao dịch**. Nếu một bước lỗi, không lưu bất kỳ mảnh, mã hay liên kết nào. Lô nguồn cùng các revision cũ được giữ nguyên nhưng chuyển sang **ngừng hoạt động** để không tính trùng diện tích. Những lô mới có ranh giới nháp, cần đo/xác minh tại hiện trường. Không cho tách lại cùng lô nguồn; vẫn có thể tách một lô con trong một lần thao tác khác. Đường cắt nhiều nhánh hoặc đa giác nhiều phần cần quy trình riêng.

Lô con giữ đa giác tọa độ WGS84 (`EPSG:4326`) và có thể xuất riêng thành `.kml` hoặc `.kmz` tại màn chi tiết; Google Earth đọc được tên, mã lô và ranh giới khép kín. Mã và geometry lô nguồn không bị sửa khi chia. Nguồn đo GPS/Google Earth ban đầu tiếp tục được ghi trên lô nguồn và truy vết qua quan hệ phân mảnh; ranh giới con có thêm đường cắt mới nên được ghi `manual` và trạng thái nháp, không nhận nhầm chứng nhận đã đo từ lô nguồn. Việc tách không sao chép ảnh nền vệ tinh hoặc tệp gốc vào lô con; Google Earth sẽ hiển thị đa giác trên ảnh nền của chính Google Earth.
