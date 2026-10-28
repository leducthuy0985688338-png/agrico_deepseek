# Bàn giao khôi phục tối ưu đồng bộ — 2026-10-28

- Worktree: C:/dev/AGRICO/agrico_sync_cost_review
- Nhánh: feature/workspace-sync-cost-controls-20261028
- Điểm gốc GitHub đã fetch và đối chiếu: 1b1f0c5db7c36a2e8800f9a4bc03ce96fa4e99c9
- Nguồn: feature/company-workspace-cloud-assistant-20261027.
- Không sử dụng ZIP hoặc kết quả kiểm thử từ bản tối ưu cũ.
- Mã để nguyên chưa commit; không push, merge, triển khai Firebase hoặc bật Blaze. Thư mục agrico_production_review và main không bị sửa.

## Hành vi đã khôi phục

1. Inbox và message.list dùng token SHA-256 có xét quyền hiện hành. Dữ liệu không đổi trả unchanged; client giữ cache, không thay lại toàn bộ inbox hoặc ghi lại cache chat.
2. Inbox vẫn đọc hồ sơ gốc để xác minh quyền, kể cả nguồn của phòng chat. Không dùng riêng generation làm bằng chứng quyền còn hiệu lực. Chat kiểm tra lại quyền phòng/nguồn trước khi bỏ truy vấn tin nhắn.
3. Các lời gọi sync đồng thời chờ cùng một Future. Đọc chat đồng thời cùng phòng cũng dùng chung lượt đọc. Token inbox đầy đủ tách khỏi generation của xác nhận lệnh.
4. Hai màn hình dùng một timer sau mỗi lượt tải hoàn tất. Chu kỳ khi có thay đổi là 10 giây; khi không đổi giãn 20, 40, tối đa 60 giây. Không tạo lượt polling mới khi app không resumed hoặc route bị che; quay lại sẽ kiểm tra ngay. Lượt mạng đã bắt đầu không bị hủy cưỡng bức.
5. Mất phiên/quyền hoặc server từ chối quyền sẽ xóa cache riêng tư; kiểm tra lại quyền sau await để không đưa dữ liệu của phiên cũ trở lại cache. UI xóa danh sách riêng tư khi bị từ chối quyền. snapshot_baseline được giữ theo hợp đồng lưu trữ hiện có.
6. Chỉ WorkspaceRejected (máy chủ xác nhận từ chối) đánh dấu lệnh bị từ chối. Lỗi vận chuyển/mạng/timeout giữ outbox và ID cũ để gửi lại. Lỗi permission-denied/unauthenticated từ Firebase làm cache mất hiệu lực nhưng không coi lệnh chưa rõ kết quả là đã bị máy chủ từ chối.
7. Backend cũ chưa hiểu token vẫn trả dữ liệu đầy đủ và client tiếp tục hoạt động. Muốn giảm payload bằng token cần triển khai riêng backend mới sau khi được duyệt; đợt này chưa triển khai.

## Kiểm chứng mới trên máy

Các lệnh chạy tại worktree mới, dùng Flutter/Dart/Node có sẵn:

~~~powershell
flutter pub get --offline
flutter test --no-pub test/features/company_workspace
flutter test --no-pub test/features/company_workspace test/core/permissions test/core/backup test/app_v2/v2_resource_module_routes_test.dart
node --test backend/company-workspace/test/domain.test.js backend/company-workspace/test/assistant-context.test.js
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
dart analyze lib/features/company_workspace test/features/company_workspace
git diff --check
~~~

- Workspace bản cuối: 26/26 đạt.
- Hồi quy mở rộng: 154/154 đạt. Sau tinh chỉnh cuối cho purge khi sync mất quyền, chạy lại workspace 26/26 đạt.
- Backend nghiệp vụ + ngữ cảnh AI: 27/27 đạt.
- Flutter analyzer toàn kho: exit 0, 349 warnings/infos, không có lỗi. Sau các chỉnh sửa cuối, Dart analyzer toàn bộ workspace và test workspace: No issues found.
- git diff --check: đạt.
- Kiểm thử bao gồm sync đồng thời phải đợi đúng kết quả; đọc chat đồng thời; cache unchanged; quyền đổi dù notice không đổi; server từ chối quyền; đăng xuất giữa lượt đọc; retry giữ ID; lỗi vận chuyển không đánh dấu reject; polling nền/route che/dispose; backoff chặn ở 60 giây.

## Đo lại

Fixture backend gồm 100 phòng với nội dung Unicode:

| Chỉ số | Kết quả |
|---|---:|
| JSON phản hồi đầy đủ | 78.293 byte |
| JSON phản hồi unchanged | 108 byte |
| Giảm payload kết quả | khoảng 99,86% |
| Số lần đọc inbox qua hai lượt kiểm tra | 2 (giữ kiểm tra quyền trên nguồn gốc) |

Đây là JSON kết quả nghiệp vụ, không gồm envelope lệnh/Firestore/network. Chat unchanged bỏ được truy vấn danh sách tin nhắn sau khi kiểm tra phòng/nguồn. Khi ổn định ở 60 giây, số lượt polling lý thuyết là tối đa khoảng 60/giờ thay vì 240/giờ ở inbox 15 giây hoặc 360/giờ ở chat 10 giây; không tính lượt thủ công, quay lại app, thời gian mạng và các bước giãn ban đầu. Kiểm thử fake clock xác nhận timer dừng hoàn toàn trong khoảng app ở nền hoặc route bị che.

Tại lần khôi phục ban đầu, chưa chạy Firebase Emulator, đo hóa đơn/traffic Firebase thật, full suite toàn dự án, hoặc build APK/Android release gate. Không suy diễn số byte thành mức giảm tiền thực tế. Không thay đổi schema, rules, nghiệp vụ hình học, cấu hình Firebase hoặc dữ liệu sản xuất.


## Nghiệm thu bổ sung 28/10/2026

Emulator hiện có chạy đạt 55/55; hai ca nghiệm thu sync/đo và offline/replay đạt, nhưng một ca mới phát hiện receipt message.list đã accepted vẫn đọc được từ server sau khi worker bị loại khỏi room mà adminRevision không đổi. Chưa sửa rules; giữ regression đỏ và đề xuất chưa commit. Không dùng kết quả cũ để che lỗi này.

Đã sửa UI để ẩn cả tiêu đề/điều khiển chat khi denied; test cache và hiển thị mới đạt. Workspace sau sửa đạt 27/27; analyzer UI/test sửa không có issue. Build debug đã thử, dừng ở processDebugGoogleServices do thiếu google-services.json; không tạo/copy cấu hình production, không có APK.

Báo cáo nghiệm thu, 14 dòng số đo SDK, JSON/CSV và log được lưu tại Windows Downloads/AGRICO-Sync-Cost-Acceptance-20261028/REPORT.md. Inbox unchanged vẫn kiểm tra hồ sơ gốc và ghi receipt/audit; số đo không phải billing. Chưa commit/push/merge/deploy hoặc bật Blaze.


## Khắc phục điểm chặn receipt — cập nhật cuối 28/10/2026

Điểm chặn receipt ở mục nghiệm thu trước đã được khắc phục bằng accepted receipt server-only và callable kiểm tra lại subject/read-set hiện hành. Giữ assertion từ chối receipt cũ; rules/processor đạt 62/62, HTTP Auth/Functions Emulator đạt 1/1, Flutter workspace/transport đạt 35/35. Các số đo process/delivery được tách và có thêm đọc để kiểm tra quyền.

Xem [phân tích và hợp đồng receipt](../security/workspace-receipt-access-20261028.md). Báo cáo Downloads/AGRICO-Sync-Cost-Acceptance-20261028/REPORT.md được cập nhật; báo cáo trước được giữ riêng. Android tiếp tục blocked, chưa có cấu hình demo/debug hợp lệ. Không commit/push/merge/deploy hoặc bật Blaze.
