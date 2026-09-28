# Danh sách hộ v2 — bước đọc dữ liệu

- Mục **Phân hệ → Hộ gia đình** đọc bảng `households` theo trang trại hiện tại. Chỉ người có quyền `field.view` và phạm vi `allFarm` được mở; phạm vi hẹp hơn chưa có truy vấn theo hộ phù hợp nên không được xem toàn bộ danh sách.
- Tra cứu tại chỗ theo mã `H00001`, tên chủ hộ hoặc tên bản; dữ liệu Unicode tiếng Lào/Việt được giữ nguyên. Danh sách hiển thị mã, chủ hộ, bản, huyện và tình trạng ngừng hoạt động. Nút làm mới đọc lại SQLite, có trạng thái trống và lỗi.
- Đây là màn chỉ đọc: không tự tạo, sửa, xóa, chuyển bản hoặc cấp lại mã. Hộ vẫn được tạo trong giao dịch tạo thửa hiện hành; danh sách phản ánh bản ghi đã lưu.
- Chạm vào hộ để xem địa bàn, liên hệ và các thửa liên kết. Quan hệ được xác định bằng `LandParcel.ownerHouseholdId == Household.id` trong cùng trang trại, bao gồm thửa ngừng hoạt động; tên chủ hộ và mã hiển thị không được dùng để ghép. Chạm vào thửa để mở màn chi tiết thửa hiện có. Truy vấn vẫn yêu cầu `field.view` và `allFarm`, không trả về hộ khác trang trại.
- Bước tiếp theo cần hợp đồng riêng để quản lý hộ độc lập, ghi lịch sử thay đổi và nối nhiều thửa vào hộ trước khi mở quyền sửa dữ liệu hộ.
