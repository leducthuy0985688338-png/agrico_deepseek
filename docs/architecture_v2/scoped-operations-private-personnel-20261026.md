# Phân quyền kho, máy, bộ phận và thông tin nhân sự riêng tư

Ngày 26/10/2026. Nền đã chốt trên GitHub: `ea0d642860560e716cca3dc32466521043b1e49e`. Nhánh làm việc: `feature/scoped-operations-private-personnel-20261026`.

## Hợp đồng đã duyệt

Người dùng chọn **nhiều kho**: cùng một vật tư dùng chung có tồn riêng ở từng kho. Phạm vi quyền dùng mã định danh đã lưu, không dùng tên hiển thị và không tự cấp allFarm.

| Phần việc | Hành vi |
|---|---|
| Kho | Tồn theo `(warehouse_id,item_id)`; tổng tồn nông trại vẫn là tổng các kho. |
| Nhập/xuất | Chọn kho, kiểm tra đúng tồn kho đó, không mượn tồn từ kho khác. Thủ kho có inventory.receive được nhập không giá trong kho được giao. |
| Giá xuất | Vẫn do người có inventory.price phạm vi nông trại nhập; quyền nhập/xuất kho không tự cấp quyền giá. |
| Chuyển kho | inventory.view và inventory.transfer phải cùng cho phép cả kho đi và kho đến. Hai vế giao dịch nguyên tử, lặp cùng yêu cầu không ghi trùng. |
| Máy | machine.view/log/maintain/verify cùng các quyền tài chính liên quan được đối chiếu với máy đã lưu trong nguồn. |
| Bộ phận | Worker gắn department_id chuẩn. Chỉ người chỉnh sửa nhân sự toàn nông trại mới được đổi bộ phận. |
| Thông tin riêng tư | Quyền mới employee.sensitive.view: identityNo, birthOn, bankName, bankAccount. employee.edit không tự cho đọc/ghi các trường này. |
| Xuất file | Dữ liệu xuất là giao của quyền xem, tài chính/bảng lương, báo cáo và data.export. Không chỉ kiểm tra nút xuất. |

Hai quyền mới được liệt kê trong màn quyền tài khoản. Admin hệ thống có quyền qua PermissionCodes.values; HR có employee.sensitive.view theo bộ phận đang được giao. Không thay phạm vi mặc định của các vai trò còn lại. inventory.transfer cần Admin cấp thêm nếu muốn giao cho tài khoản khác.

## Dữ liệu và nâng cấp

- `inventory_warehouses_v1`: kho cùng nông trại, mã tự sinh `KHO-001…`; kho mặc định `KHO-000`, ID `warehouse:default:<farmId>`.
- `inventory_warehouse_sequences_v1`: bộ đếm mã kho, cùng giao dịch tạo kho.
- `inventory_warehouse_stock_v1`: số lượng dạng micro-unit chính xác, không âm, tổng khớp inventory_items_v2.stock_units.
- `inventory_transfers_v1`: nguồn chuyển kho bất biến qua API, hai movement receipt/issue có transfer_id; không tự gán giá, tiền tệ, chi phí sản xuất hoặc dòng tiền.
- Movement thêm warehouse_id, transfer_id. Danh mục vật tư vẫn dùng một identity chung, không nhân bản vật tư theo kho.
- `personnel_departments_v1` và `personnel_department_sequences_v1`: bộ phận mã tự sinh `BP-001…`; profile thêm department_id nullable. Tên bộ phận nhập tự do trước đây không tự trở thành quyền truy cập.

Nâng cấp số tồn đang có đưa toàn bộ lịch sử và tồn của mô hình một kho vào KHO-000, không đổi tổng tồn, giá, mã chứng từ hay danh tính vật tư. Bước thêm chiều kho và backfill chạy trong một SQLite transaction; lỗi giữa chừng không để lại cột đánh dấu đã nâng cấp dở. Chạy lại schema không nhân đôi số tồn.

Kho chưa có số dư của một vật tư được hiển thị là 0. Các writer kho, mua bán và nhiên liệu đều đi qua recordInTransaction để cập nhật tổng tồn và tồn kho cùng giao dịch. Luồng mua bán/thu hoạch/nhiên liệu hiện tiếp tục dùng kho mặc định; hoàn nhiên liệu giữ kho của phiếu nguồn. Chuyển kho mới áp dụng vật tư, chưa chuyển lô thành phẩm giữa kho vì lô bán hàng cần giữ nguyên nguồn và số tồn riêng của lô.

Cutover dữ liệu test V2 cũ chỉ dọn thêm projection kho khi marker cũ chưa có; marker hoàn tất của bản đang dùng vẫn chặn chạy lại. Không reset dữ liệu app trong đợt này. Không sửa GIS, hình học hay identity không gian.

## Kiểm tra quyền

LiveAuthorization kiểm tra phiên hiện tại. readScoped chụp dấu quyền và tập ID trước/sau I/O; đổi phạm vi trong lúc đọc sẽ bỏ kết quả dù mã quyền vẫn tồn tại. permissionScopes cụ thể có ưu tiên hơn dataScopes hợp nhất.

OperationScope sinh điều kiện SQL theo từng quyền, nối AND giữa các quyền. Những phạm vi không có liên kết dữ liệu hỗ trợ bị từ chối, không tự chuyển thành toàn nông trại. ID được quote như giá trị, không dùng làm tên cột/bảng.

SQLite repository lọc máy/nhân sự trước khi trả kết quả. Quyền xem tiền và trường riêng tư được kiểm tra theo từng dòng, nên có thể thấy danh sách cơ bản của nhiều bộ phận nhưng chỉ thấy thông tin riêng tư của bộ phận được cấp. Phiếu duyệt/hủy tra lại worker/machine của bản ghi thật trong transaction; không tin worker/machine gắn trong object từ UI. Chạm vào hồ sơ mở bản chỉ đọc sau khi tải lại quyền/dữ liệu, không cần employee.edit. Sửa profile không có quyền riêng tư giữ nguyên các trường riêng tư đã bị che; gửi các trường đó lên bị chặn.

Xuất Máy/Nhân sự dùng repository gắn thêm phạm vi report/data.export, tải lại dữ liệu và kiểm tra dấu phiên trước writer. Lịch sử kho giữ kho đang chọn khi mở màn và khi xuất. Màn quản trị tài khoản có bộ chọn kho, máy và bộ phận bằng tên/mã từ dữ liệu cục bộ; các ID cũ chưa có trong danh bạ vẫn hiện để Admin chủ động kiểm tra.

Mô hình này kiểm tra quyền trong ứng dụng offline với nguồn cấp quyền hiện hành. Không thay cơ chế đăng nhập, hạn offline hoặc bổ sung đồng bộ đa thiết bị trong đợt này.

## Sao lưu/khôi phục

Bản sao lưu mới mang theo kho, số dư, cặp chuyển kho, bộ phận và bộ đếm. Preflight đối chiếu tổng tồn, tồn từng kho, movement, hai vế chuyển kho, quan hệ cùng nông trại và bộ đếm mã. Payload lệch bị từ chối trước khi ghi database thật.

**Bản sao lưu cũ có tồn/lịch sử kho nhưng thiếu chiều kho bị chặn khôi phục**, tránh mất hoặc gán sai liên kết mới. Dữ liệu app hiện tại vẫn nâng cấp trực tiếp vào kho mặc định. Nên tạo một bản sao lưu mới sau khi kiểm tra APK này. Bản cũ rỗng hợp lệ có thể khôi phục; activation xóa các bảng cấu hình phạm vi mới bị thiếu trong payload để không giữ lại số dư/cấu hình từ trạng thái hiện tại.

## Kiểm chứng đã thực hiện

- 255 test Dart/SQLite qua trên 16 file: kho/kế hoạch, nhân sự, máy, mua bán, tích hợp, danh mục, quyền, cutover test và preflight backup.
- 5 test khôi phục IO qua, gồm thay hai database nguyên tử, rollback khi chèn lỗi, thứ tự cha/con, media và bản cũ rỗng. Các test dùng thư mục được truyền vào; shim path_provider chỉ chặn đường lấy thư mục nền tảng vốn không được gọi trong test. Không đưa shim vào mã app.
- Trong đó có 23 test scope/đa kho mới, 2 test backup mới, 1 test activation mới; thêm 3 widget test cho chọn kho, tài khoản thủ kho và xem hồ sơ riêng tư chỉ đọc.
- Phân tích tĩnh nguồn liên quan không có error/warning; còn lint info. git diff --check đạt.
- Chưa chạy Flutter/widget/full suite, Android build hoặc thử điện thoại ở môi trường này. Đây là cổng kiểm tra Windows bắt buộc.

## Windows sau khi nhánh đã được xuất bản

Giữ analysis_options.yaml và bảy generated files cục bộ. Không dùng reset/stash hoặc bỏ thay đổi. Chỉ chạy các lệnh fetch/switch sau khi đã xác nhận nhánh sửa được đưa lên GitHub.

```powershell
Set-Location C:\dev\AGRICO\agrico_production_review
git fetch origin feature/scoped-operations-private-personnel-20261026
if ($LASTEXITCODE -ne 0) { throw 'Fetch failed.' }
git switch -c feature/scoped-operations-private-personnel-20261026 --track origin/feature/scoped-operations-private-personnel-20261026
if ($LASTEXITCODE -ne 0) { throw 'Switch failed.' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Verify-Scoped-Operations.ps1 -Full -Build
```

Runner kiểm tra đúng nhánh/nền, không có stage hoặc thay đổi lạ; chạy pub get, analyzer, test tập trung, toàn bộ test và build debug. APK lưu Downloads. Không tự cài máy, xóa data, commit, push hay merge.

## Năm mục kiểm tra trên điện thoại

1. Admin thấy dữ liệu cũ trong KHO-000. Tạo hai kho, nhập cùng vật tư vào hai kho với số lượng khác nhau; đổi bộ chọn phải hiện đúng số tồn riêng. Mã kho tự sinh không trùng.
2. Chuyển một lượng lẻ giữa hai kho: tổng tồn không đổi, kho đi giảm và kho đến tăng. Xuất vượt tồn riêng phải thất bại dù kho khác còn nhiều. Thủ kho chỉ thấy kho được giao, không tự nhập được giá xuất hay chuyển tới kho không được giao.
3. Giao một máy và công việc cho tài khoản vận hành: chỉ thấy dữ liệu máy đó, ghi công việc hợp lệ; không mở/duyệt/hủy dữ liệu máy khác. Người không có quyền tài chính không thấy giá ca máy.
4. Admin tạo bộ phận, gắn worker vào bộ phận, giao bộ phận cho HR trong màn tài khoản. HR chỉ thấy worker thuộc phạm vi; bỏ employee.sensitive.view phải che bốn trường riêng tư. Sửa thông tin thường không làm mất số giấy tờ/tài khoản ngân hàng đã che. Gán lại bộ phận cần người chỉnh sửa toàn nông trại.
5. Xuất báo cáo theo đúng phạm vi, kiểm tra số kho/cặp chuyển kho và VND/LAK; tạo backup mới và khôi phục phải giữ đúng tồn, bộ phận và dữ liệu nghiệp vụ. Mua bán, bảng lương và chi phí sản xuất không bị cộng thêm do chuyển kho.
