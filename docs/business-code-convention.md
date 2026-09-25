# Quy chuẩn mã nghiệp vụ AGRICO (bản đầu)

- Địa bàn: danh mục `AdministrativeUnit` giữ `id` ổn định, `code` được quản trị và duy nhất trong cùng cha và cùng cấp. Tên tiếng Việt/Lào/Anh dùng để hiển thị, không làm nguồn cấp mã. Chọn quốc gia → tỉnh → huyện → bản bằng danh mục theo quan hệ cha; ứng dụng tự điền mã, người nhập không gõ mã. Không mặc định mã địa phương chưa được xác thực. Đổi tên không đổi mã hoặc ID; thay đổi địa giới cần lưu lịch sử ánh xạ riêng.
- Thửa đất: giữ nguyên mã đã cấp. Mã mới dùng các mã địa bàn đã được duyệt, mã hộ và số thửa theo phạm vi hộ. `LandParcel.id`, `parcelCode` và `SpatialFeature.id` là ba danh tính riêng. Chưa tự sinh hoặc đổi mã thửa cũ cho đến khi có danh mục địa bàn và quy tắc đối soát dữ liệu.
- Chứng từ: `THU-YYYYMM-NNN`, `CHI-YYYYMM-NNN`, `NHAP-YYYYMM-NNN`, `XUAT-YYYYMM-NNN`. Mỗi loại có dãy số riêng theo tháng và năm, `001`–`999`; hết dải thì báo lỗi, không quay vòng. Ngày ghi trên chứng từ quyết định tháng mã. Sửa ngày sang tháng khác cần quy trình hủy/đổi mã có nhật ký, không sửa ngầm. Mã không thay cho ID kỹ thuật.
- Cấp số: chọn số kế tiếp và lưu chứng từ trong **cùng một giao dịch** với ràng buộc duy nhất theo phạm vi tổ chức, loại và kỳ. Không cấp số bằng cách đếm bản ghi trên biểu mẫu; khi đồng bộ từ nhiều thiết bị ngoại tuyến phải giải quyết xung đột bằng ID ổn định và quy tắc cấp số trên máy chủ trước khi dùng mã như mã chính thức. Không cấp mã mới cho bản ghi cũ khi chưa đối soát.

`BusinessReferenceCode` chỉ định dạng và xác thực; `AdministrativeCodeCatalog` chỉ tra cứu danh mục đã nạp. Việc nối vào biểu mẫu, bảng dữ liệu và cấp số giao dịch được triển khai theo từng phân hệ.

## Mã nội bộ AGRICO đã duyệt

- Địa bàn khởi tạo: Lào `LA` → Savannakhet `SVK` → Nong `NONG` → Ta Ko `TAKO`. `SVK`, `NONG`, `TAKO` là mã quản trị nội bộ, không phải mã hành chính chính thức. Mỗi địa bàn mới được thêm vào danh mục theo cấp cha; mã duy nhất trong cùng cha và cấp, giữ nguyên khi thay đổi tên hiển thị.
- Hộ trong mỗi trang trại: `H001`–`H999`. Dãy số duy nhất và tăng dần trong cả trang trại, không phụ thuộc tỉnh/huyện/bản; tối đa 999 hộ trước khi phải duyệt mở rộng quy tắc. Không quay vòng hoặc tái sử dụng số khi hộ chuyển bản. Thửa trong mỗi hộ: `001`–`999`.
- Mã thửa: `LA-SVK-NONG-TAKO-H001-001`. `LandParcelReferenceCode` định dạng và kiểm tra dải, không tự cấp số hoặc thay thế `LandParcel.id`. Cấp số hộ/thửa cần giao dịch lưu và ràng buộc duy nhất trước khi nối vào biểu mẫu. Mã cũ không tự thay đổi.
