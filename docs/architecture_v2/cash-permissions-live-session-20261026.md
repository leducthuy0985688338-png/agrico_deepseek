# Quyền quỹ và phiên hiện hành — 26/10/2026

Nền GitHub đã xác minh: 9e6741a70b62fe5beced0440e0f7bb266d16af3e, nhánh feature/report-input-completion-20261026. Nhánh sửa: fix/cash-permissions-live-session-20261026.

## Hành vi mới

| Thao tác thu/chi độc lập | Quyền cần có cùng phạm vi nguồn |
|---|---|
| Xem phiếu, tổng tiền và chi tiết | finance.view + cash.view |
| Tạo THU/CHI | Các quyền xem + finance.create + cash.record |
| Xem báo cáo tiền/chi phí từ phiếu tiền | Các quyền xem + report.finance |
| Ghi file xuất | Các quyền báo cáo + data.export |

Có report.finance nhưng thiếu data.export vẫn được xem báo cáo; hai đường xuất tài chính và báo cáo chi phí không gọi file writer khi thiếu quyền xuất. Đường mua bán dùng TradeService được giữ độc lập: người xem thương mại không bị buộc có cash.view để mở chứng từ, nhưng không có nút mở sổ quỹ độc lập khi thiếu quyền quỹ.

## Kho, Nhân sự, Máy

Ba service bắt buộc có callback currentSubject; không có fallback lấy subject cũ. Mỗi quyết định đối chiếu user, membership, farm của màn đã mở với phiên hiện tại; giữ kiểm tra active, hạn phiên, allFarm và permissionScopes cụ thể. Không cấp thêm quyền hoặc mở rộng phạm vi vai trò.

Đọc bất đồng bộ được kiểm tra trước và sau repository. Nếu đang đọc hồ sơ có thông tin riêng mà employee.edit bị thu hồi, hoặc đang đọc giá máy mà finance.view bị thu hồi, kết quả đó bị từ chối thay vì trả thông tin cũ cho UI. Các thao tác ghi bị kiểm tra ở service trước khi gửi vào repository. Việc đổi quyền sau khi một transaction đã chạy không phải yêu cầu tự đảo transaction đó.

Màn root cung cấp callback gắn với phiên hiện tại và trạng thái mounted; các fixture kiểm thử cung cấp phiên riêng rõ ràng. Gate phiên hiện có vẫn hủy toàn bộ navigation stack khi khóa/đăng xuất hoặc membership thay đổi. Không thêm timer theo dõi quyền cho từng màn.

Xuất Nhân sự/Máy/Thương mại tải lại nguồn khi bấm xuất rồi kiểm tra quyền trước khi giao file writer. Xuất kho/kế hoạch kiểm tra quyền đọc, báo cáo và xuất hiện hành. Nút thao tác Kho và Kế hoạch dùng cùng quyết định quyền với service. Các màn Nhân sự/Máy/Kho có trạng thái từ chối truy cập khi không còn quyền xem, và future khởi tạo được xử lý để tránh lỗi không có người nhận.

## Giới hạn của đợt này

Không thay template 18 vai trò, không cấp allFarm cho thủ kho/nhân sự/kế toán, không đổi schema hoặc dữ liệu. Phạm vi kho/máy/bộ phận và tách quyền xem hồ sơ riêng khỏi employee.edit vẫn là công việc kế tiếp. Không triển khai điều chỉnh bảng lương đã duyệt, nhật ký metadata bất biến, chốt kỳ hay đồng bộ chứng từ trong đợt này.

Một số fixture cũ chỉ cấp finance.view/create cho đường quỹ. Các fixture thành công được bổ sung quyền quỹ/xuất rõ ràng theo hợp đồng mới; các ca từ chối và mất quyền được giữ và mở rộng. Không đổi policy thật để làm test qua.

## Kiểm chứng

- 425 kiểm thử native Dart/SQLite PASS, gồm 8 test phiên hiện hành mới và 6 test quyền quỹ/xuất mới.
- Kiểm tra subject null, đổi user/membership/farm, inactive/hết hạn, scope bị thu hẹp và permissionScopes bị giới hạn.
- Đọc đang chờ bị chặn sau thu hồi quyền; thông tin hồ sơ/giá máy không trả ra; ghi kho từ phiên cũ không tới repository.
- Thiếu cash.view/cash.record/data.export bị chặn đúng tầng; quyền đọc báo cáo không phụ thuộc quyền xuất file.
- Phân tích tĩnh các tệp Dart thay đổi không có error/warning; còn lint info. git diff --check đạt.
- Flutter/widget/full suite và APK là cổng kiểm tra Windows; chưa tuyên bố đã chạy các cổng đó ở môi trường này.

## Kiểm tra Windows sau khi lấy nhánh sửa

Giữ analysis_options.yaml và 7 generated files đang sửa. Dùng git fetch/switch, không reset dữ liệu hoặc bỏ các thay đổi cục bộ.

```powershell
Set-Location C:\dev\AGRICO\agrico_production_review
git fetch origin fix/cash-permissions-live-session-20261026
git switch -c fix/cash-permissions-live-session-20261026 --track origin/fix/cash-permissions-live-session-20261026
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Verify-Cash-Session.ps1 -Full -Build
```

Chỉ chạy lệnh fetch/switch trên sau khi nhánh sửa đã được đẩy lên GitHub theo xác nhận người dùng. Hiện việc chuẩn bị không tự push/merge hay bật review tự động.

## Năm mục trên điện thoại

1. Admin vẫn tạo/xem THU/CHI, tổng tiền, xem chi phí và xuất báo cáo bình thường.
2. Tài khoản có finance.view nhưng thiếu cash.view không mở/đọc quỹ; quyền cash.view không tự cho ghi khi thiếu cash.record.
3. Người có quyền xem thương mại nhưng không có quyền quỹ vẫn xem chứng từ mua/bán, không có lối mở thu/chi độc lập.
4. Khóa/đăng xuất/đổi quyền khi đang mở Nhân sự, Máy, Kho: phiên cũ không ghi hoặc xuất được; mở lại bằng phiên mới kiểm tra đúng quyền và phạm vi. Các ca thu hồi trong I/O đã có test ở service.
5. Các luồng kho → lương/máy → thu hoạch/bán/công nợ → báo cáo và sao lưu vẫn giữ số liệu. Dùng dữ liệu test hiện có, không reset app.
