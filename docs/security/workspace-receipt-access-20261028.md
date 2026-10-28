# Bảo vệ receipt và giao kết quả — 28/10/2026

## Nguyên nhân và phạm vi

Command schemaVersion=1 gồm action, entityId, expectedRevision, payload, trạng thái và dữ liệu do server bổ sung. Receipt accepted trước đây chứa trực tiếp result (inbox, tin nhắn, hồ sơ, tên thành viên, lịch sử, đường dẫn tệp/snapshot hoặc câu trả lời AI). Firestore trả nguyên document, không che từng trường.

Rules cũ chỉ buộc UID/farm/active/lease/cloud.sync và resultPolicyRevision == membership.adminRevision đối với accepted. Workflow đổi assignee/reviewer, participants, quyền ở task/form nguồn, thay tuyến duyệt và thay authority registry không nhất thiết cập nhật membership/adminRevision. Bản sao nguồn trong room/inbox cũng không phải nguồn thẩm quyền hiện hành.

Không thay mô hình role/scope, nghiệp vụ hay SQLite. Chỉ thay metadata receipt, rules đọc và giao kết quả. Permission/visibility vẫn do Domain quyết định lúc xử lý, sau đó thẩm quyền/data đã dùng phải còn nguyên khi giao kết quả.

## Hợp đồng mới

- Mọi command accepted, gồm legacy, chỉ server đọc được. Pending/processing/rejected không được đọc trực tiếp nếu chứa result hoặc metadata guard riêng tư. Payload pending là nội dung chính caller đã gửi, không phải kết quả riêng tư do server trả.
- companyWorkspaceResult là callable có Firebase Auth. UID lấy từ auth đã xác minh, không tin UID trong body. Farm, operation và 4 trường command gốc phải khớp. Không cho truy cập receipt người khác hoặc thay nội dung dưới cùng operation ID.
- processCommand ghi resultDelivery=2, resultSubjectHash và resultGuards trong chính update accepted. Subject hash bao gồm toàn membership, không chỉ adminRevision. Guard là đường dẫn + SHA-256 của nguồn gốc được đọc và trạng thái cuối của hồ sơ vừa ghi; không sao chép thêm nội dung riêng tư.
- Các nguồn được theo dõi gồm record và nguồn task/form của room, membership liên quan, authority registry, template, route, snapshot control. Projections/inbox/notices/counters không thay thế nguồn gốc. Read-set và kết quả được tạo trong transaction hiện có.
- Khi giao accepted result, transaction mới kiểm tra membership active/lease/cloud.sync/chat.view, subject hash và đọc lại toàn bộ guard. Thay đổi nguồn hoặc quyền làm kết quả cũ không còn được giao. Đây là kiểm tra bảo thủ: đổi dữ liệu không liên quan đến quyền cũng có thể làm receipt cũ bị từ chối; client đọc lại bằng operation mới.
- Legacy thiếu guard: không giao private result. Lệnh outbox đã ghi thành công (task/form/room.create/message.create) có thể nhận duy nhất accepted + result rỗng + resultUnavailable=true để hoàn tất retry, không chạy lại nghiệp vụ, không trả dữ liệu cũ. Membership mất cloud/chat/active vẫn bị từ chối hoàn toàn.
- AI áp dụng cùng guard cho context/nguồn/snapshot/authority; kiểm tra lại trước khi publish answer và lúc đọc answer. Không gọi provider thật trong nghiệm thu.
- FirebaseWorkspaceTransport giữ Firestore transaction tạo lệnh và operation ID. Khi command accepted không còn đọc trực tiếp được, channel chuyển sang callable để xác minh replay. Chỉ status=rejected từ command mới thành WorkspaceRejected. Lỗi HTTP/network/denied không bị diễn giải thành nghiệp vụ đã bị từ chối. Kiểm tra session cả trước và sau await, bảo vệ đổi tài khoản/đăng xuất.
- Callable chỉ trả status/error kỹ thuật hoặc result đã được phép giao; không trả payload, subject hash hay manifest guard. Kết quả không còn đi vào Firestore SDK cache thông qua đọc accepted command.

Không có API nào thu hồi được byte người dùng đã tải trước đó. App mới không đọc lại accepted receipt từ cache SDK; cache SQLite và dữ liệu đang hiển thị được bảo vệ bởi kiểm tra session/purge hiện có. Chưa kiểm thử migration native cache từ APK cũ.

## Kiểm thử và số đo

- Rules/processor/Storage + hợp đồng quyền liên quan: 62/62 đạt, không skip/todo.
- Auth + Functions + Firestore Emulator, HTTP thật: 1/1 đạt. Kiểm tra token hợp lệ, thiếu/không hợp lệ, đổi tài khoản, quyền phòng bị thu hồi và retry cùng operation.
- Flutter workspace, transport và giao thức HTTP: 35/35 đạt; sau tinh chỉnh lint chạy riêng transport 8/8 đạt. Analyzer phần transport/test không có issue.
- Giữ nguyên assertion permission-denied đọc receipt cũ sau loại thành viên. Positive phase dùng callable do accepted Firestore đã bị khóa; thêm assertion từ chối ngay cả trước thu hồi và từ chối qua callable sau thu hồi.
- Nguồn bị thu hồi được thử bằng workflow thật đổi reviewer của form mà membership/adminRevision không đổi; receipt message.list, inbox và AI cũ đều bị từ chối.
- 14 kịch bản trước đây được đo lại: 28 dòng SDK tách process/delivery. Ghi business/receipt không thêm mutation, nhưng delivery đọc thêm membership, command và guard. Ví dụ inbox unchanged: process 4 get + 1 query + 2 mutation như cũ, delivery thêm 3 get + 0 write. Message unchanged: process 4 get + 0 query + 2 mutation, delivery thêm 3 get + 0 write.
- Payload ví dụ inbox unchanged: dạng legacy tái dựng 412 byte, document server có guard 665 byte, JSON kết quả được giao 159 byte. Legacy tái dựng là cùng snapshot hiện tại bỏ 3 trường guard mới, không phải packet capture lịch sử. Không bao gồm callable envelope, HTTP/TLS, Auth, polling hoặc nội bộ rules/index. Không quy đổi thành tiền.

Chi tiết và raw log nằm trong Downloads/AGRICO-Sync-Cost-Acceptance-20261028/REPORT.md và receipt-fix-*.json/csv/log. Bộ domain unit 27/27 và hồi quy mở rộng 154/154 trước đó giữ làm bằng chứng cho phần không thay đổi; không coi đó là native build mới.

## Chạy lại trên máy nghiệm thu

Firestore/Storage, process và rules:

~~~powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
node backend/company-workspace/tools/test-emulator.mjs
~~~

HTTP thật dùng firebase.receipt-test.json, chỉ project demo-agrico-workspace. Cần tham số local chỉ dành Emulator để CLI không dừng hỏi model hoặc lấy secret thật: .env.local có AGRICO_AI_MODEL=emulator-test-no-provider; .secret.local có giá trị AGRICO_AI_API_KEY giả, không dùng được với provider. Các file này đang bị ignore, không đưa vào commit hoặc gói source Functions. Không ghi đè local override đã có.

~~~powershell
$env:CI = 'true'
$env:GCLOUD_PROJECT = 'demo-agrico-workspace'
$env:GOOGLE_CLOUD_PROJECT = 'demo-agrico-workspace'
node backend/company-workspace/node_modules/firebase-tools/lib/bin/firebase.js --config firebase.receipt-test.json emulators:exec --project demo-agrico-workspace --only auth,firestore,functions 'node --test backend/company-workspace/test/receipt-http.test.js'
flutter test --no-pub test/features/company_workspace
~~~

Emulator hiện chạy Node 24 của máy, dù backend khai báo Node 22; phải xác nhận Node 22 trước release. SDK Functions cục bộ có cảnh báo outdated; không nâng dependency trong đợt này.

## Triển khai và Android

Chưa triển khai. Rules, backend và client giao kết quả mới phải được phối hợp nâng cấp; client cũ sẽ không đọc accepted receipt nữa. Script triển khai chỉ được chỉnh target bắt buộc companyWorkspaceResult; chưa chạy script với -Deploy. Nếu dùng AI cần cả Assistant bản có guard. Khi thay logic quyền/role-policy trong một release tương lai, phải tăng phiên bản/invalidate receipt guard của release cũ để tránh dùng quyết định quyền theo code cũ.

Source-upload ignore được bổ sung .secret.local và kiểm tra bằng bộ liệt kê file của CLI: env/secret local bị loại; receipt_access.js có trong source. Không upload/deploy để kiểm tra.

Android vẫn blocked. Worktree không có google-services.json hoặc cấu hình src/debug tương ứng; chỉ có google-services (1).json trỏ agrico-erp/com.agrico.erp, không phải demo. Không dùng/đổi tên file đó, không tìm/copy từ checkout cũ, không tạo file giả hay tắt plugin. Không lặp build đã biết sẽ lỗi; chưa có APK.

Các bước tiếp theo cần điều phối: review diff/quy trình phối hợp phiên bản; duyệt cấu hình Firebase demo/debug hợp lệ nếu muốn build. Không commit/push/merge/deploy/Blaze trong lượt khắc phục.
