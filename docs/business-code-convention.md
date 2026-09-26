# Quy chuẩn mã nghiệp vụ AGRICO (bản đầu)

- Địa bàn: danh mục `AdministrativeUnit` giữ `id` ổn định, `code` được quản trị và duy nhất trong cùng cha và cùng cấp. Tên tiếng Việt/Lào/Anh dùng để hiển thị, không làm nguồn cấp mã. Chọn quốc gia → tỉnh → huyện → bản bằng danh mục theo quan hệ cha; ứng dụng tự điền mã, người nhập không gõ mã. Không mặc định mã địa phương chưa được xác thực. Đổi tên không đổi mã hoặc ID; thay đổi địa giới cần lưu lịch sử ánh xạ riêng.
- Thửa đất: giữ nguyên mã đã cấp. Mã mới dùng các mã địa bàn đã được duyệt, mã hộ và số thửa theo phạm vi hộ. `LandParcel.id`, `parcelCode` và `SpatialFeature.id` là ba danh tính riêng. Biểu mẫu v2 cấp mã cho thửa mới từ danh mục địa bàn đã duyệt; thửa cũ không tự đổi mã khi chưa đối soát dữ liệu.
- Chứng từ: `THU-YYYYMM-NNN`, `CHI-YYYYMM-NNN`, `NHAP-YYYYMM-NNN`, `XUAT-YYYYMM-NNN`. Mỗi loại có dãy số riêng theo tháng và năm, `001`–`999`; hết dải thì báo lỗi, không quay vòng. Ngày ghi trên chứng từ quyết định tháng mã. Sửa ngày sang tháng khác cần quy trình hủy/đổi mã có nhật ký, không sửa ngầm. Mã không thay cho ID kỹ thuật.
- Cấp số: chọn số kế tiếp và lưu chứng từ trong **cùng một giao dịch** với ràng buộc duy nhất theo phạm vi tổ chức, loại và kỳ. Không cấp số bằng cách đếm bản ghi trên biểu mẫu; khi đồng bộ từ nhiều thiết bị ngoại tuyến phải giải quyết xung đột bằng ID ổn định và quy tắc cấp số trên máy chủ trước khi dùng mã như mã chính thức. Không cấp mã mới cho bản ghi cũ khi chưa đối soát.

`BusinessReferenceCode` chỉ định dạng và xác thực; `AdministrativeCodeCatalog` chỉ tra cứu danh mục đã nạp. Việc nối vào biểu mẫu, bảng dữ liệu và cấp số giao dịch được triển khai theo từng phân hệ.

## Mã nội bộ AGRICO đã duyệt

- Địa bàn khởi tạo: Lào `LA` → Savannakhet `SVK` → Nong `NONG` → Ta Ko `TAKO`. `SVK`, `NONG`, `TAKO` là mã quản trị nội bộ, không phải mã hành chính chính thức. Mỗi địa bàn mới được thêm vào danh mục theo cấp cha; mã duy nhất trong cùng cha và cấp, giữ nguyên khi thay đổi tên hiển thị.
- Hộ trong mỗi trang trại: `H00001`–`H99999`. Dãy số duy nhất và tăng dần trong cả trang trại, không phụ thuộc tỉnh/huyện/bản; tối đa 99999 hộ trước khi phải duyệt mở rộng quy tắc. Không quay vòng hoặc tái sử dụng số khi hộ chuyển bản. Thửa trong mỗi hộ: `001`–`999`.
- Mã thửa: `LA-SVK-NONG-TAKO-H00001-001`. `LandParcelReferenceCode` định dạng và kiểm tra dải, không tự cấp số hoặc thay thế `LandParcel.id`. Cấp số hộ/thửa cho bản ghi mới đã nối vào biểu mẫu v2 trong cùng giao dịch SQLite với ràng buộc duy nhất. Mã cũ không tự thay đổi.

## Danh mục địa bàn trên ứng dụng v2

- Người có quyền `administrative_catalog.manage` có thể thêm tỉnh dưới quốc gia Lào, huyện dưới tỉnh, bản dưới huyện. Mã mới là mã nội bộ AGRICO, dùng chữ A–Z hoặc số 0–9; cùng cấp và cùng địa bàn cha không được trùng mã. Danh mục khởi tạo `LA → SVK → NONG → TAKO` giữ nguyên.
- Danh mục chỉ cho thêm và xem. Mã/ID đã cấp không được sửa hoặc tái sử dụng. Thêm địa bàn không tự chuyển địa bàn, đổi tên hoặc cấp lại mã cho hộ/thửa hiện có.
- Biểu mẫu tạo thửa đọc lại danh mục từ SQLite mỗi lần mở, nên địa bàn mới xuất hiện trong trình chọn ngay sau khi thêm. Danh mục lưu cục bộ trên thiết bị; đồng bộ giữa nhiều thiết bị chưa được triển khai.
