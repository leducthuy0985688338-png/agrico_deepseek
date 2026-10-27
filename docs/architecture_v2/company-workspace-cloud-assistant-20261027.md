# Không gian công ty, Cloud và trợ lý AGRICO

Điểm gốc: `598911c66f173e67385930754e3a0f0b2d2f4c59`.
Nhánh: `feature/company-workspace-cloud-assistant-20261027`.

Bản này được dựng lại sau khi thư mục làm việc của lượt trước bị dọn. Kết quả kiểm thử phải lấy từ lần dựng lại; không dùng lại số 1.913/55 đã báo ở lượt cũ. Không tự commit/push, sửa main, triển khai Firebase, cài APK hay xóa dữ liệu app.

## Những phần được thực hiện

| Hạng mục | Hành vi |
|---|---|
| Thu hoạch | Mở phân hệ lô thu hoạch V2 hiện có theo quyền tài chính toàn công ty |
| Nhiên liệu | Mở tab nhiên liệu của phân hệ máy, kiểm tra quyền máy và tài chính |
| Giao việc | Tài khoản thật; giao, nhận, bắt đầu, tiến độ, nộp, nghiệm thu/làm lại, hủy; mã tự động theo tháng và lịch sử |
| Công việc sản xuất | Giữ đường vào phần công việc sản xuất cũ, không trộn với việc giao cho nhân viên |
| Chat | Cá nhân/nhóm tối đa 20 người gồm người tạo; gửi chữ và tệp; theo thứ tự máy chủ; phòng chat theo hồ sơ/công việc |
| Hành chính | 22 mẫu có sẵn, Admin thêm/phiên bản hóa mẫu riêng; tuyến duyệt 1–4 người; nháp/sửa/gửi/nhận/duyệt/bổ sung/từ chối/rút/lưu hồ sơ; xuất Word |
| Cloud | Hàng chờ riêng cho việc/phiếu/chat; bản chụp số liệu kinh doanh đầy đủ cho Admin, checksum, preflight phục hồi, phiên bản và lựa chọn xung đột rõ ràng |
| AI | Chỉ đọc hồ sơ được phép; có thể dùng tổng thu/chi từ bản chụp đã công bố khi Admin chủ động bật; không có công cụ ghi hoặc gửi thay người dùng |

Các tính năng trực tuyến cần backend Firebase được triển khai riêng. Chưa triển khai backend hoặc gọi nhà cung cấp AI trả phí trong đợt này.

## Hồ sơ hành chính

22 mẫu: tạm ứng; hoàn ứng; đề nghị thanh toán; đề nghị chi; nghỉ phép; nghỉ ốm; nghỉ không lương; tăng ca; điều chỉnh chấm công; đề nghị công tác; kế hoạch công tác; báo cáo công tác; mua hàng; cấp vật tư; cấp công cụ; cấp bảo hộ; bàn giao tài sản; sửa chữa; đề xuất; báo cáo công việc; biên bản; hỗ trợ phòng ban.

Mỗi mẫu có tên/nhãn Việt, Anh, Lào; trường văn bản, nội dung dài, ngày, tiền, tiền tệ hoặc số. Mẫu riêng tối đa 20 trường, không chạy công thức hoặc mã do người dùng nhập. Hồ sơ giữ mẫu gốc theo phiên bản; đổi mẫu không làm thay đổi văn bản cũ.

Tuyến duyệt chọn mẫu và phòng ban người gửi, 1–4 tài khoản có quyền nghiệp vụ tương ứng và phạm vi phù hợp. Người gửi không được tự duyệt; máy chủ kiểm tra lại quyền hiện hành ở mỗi thao tác. Hệ thống cấp mã tuần tự riêng từng loại theo tháng; thao tác bị từ chối không tiêu số. Phiếu có lịch sử ai/ngày/trạng thái/lý do; bản Word giữ Unicode, trạng thái và chỗ ký, không giả chữ ký pháp lý.

**Duyệt phiếu chỉ ghi nhận đề nghị. Không tự ghi công, lương, tiền thực nhận, công nợ, xuất kho hoặc chi tiền.** Số liệu thực vẫn ghi trong phân hệ nghiệp vụ tương ứng. Hoàn ứng tham chiếu tạm ứng đã được duyệt của đúng người/cùng tiền tệ. Tổng phần nhận đề nghị đối chiếu không vượt số tạm ứng được duyệt; bộ đếm được khóa trong giao dịch để hai lần duyệt đồng thời không vượt hạn mức. Số hoàn trả/chi thêm là số đề nghị; VND và LAK luôn tách biệt.

## Kiến trúc và bảo vệ dữ liệu

UI → WorkspaceService → WorkspaceTransport/WorkspaceStore → Firebase hoặc SQLite.

Client không được ghi trực tiếp hồ sơ, inbox, audit hoặc bảng điều khiển. Lệnh có ID ổn định; máy chủ xử lý đúng một lần trong giao dịch, kiểm tra UID, farm, trạng thái/thời hạn quyền, quyền nghiệp vụ, phạm vi và revision. Tất cả ghi được đệm sau khi hoàn tất đọc để tuân thủ giao dịch Firestore. Mã số, bản ghi, lịch sử, inbox và xác nhận lệnh cùng giao dịch.

Đọc inbox phải đọc lại hồ sơ gốc, không tin bản sao inbox cũ. Chat theo hồ sơ kiểm tra lại nguồn gốc hiện tại; thay người duyệt hoặc thu hồi quyền không để lộ hồ sơ qua phòng chat cũ. Kết quả lệnh chấp nhận gắn adminRevision. Tệp người nhận dùng giấy phép tải 60 giây gắn đúng đường dẫn/revision; chủ tệp có thể đọc tệp của mình. Storage không cho sửa/xóa đè nội dung theo SHA.

SQLite phân vùng farm + UID, lưu hàng chờ và cache riêng. Gửi lại giữ ID; lệnh chưa rõ kết quả không được xóa như thể chưa gửi. Lệnh bị từ chối giữ nội dung và có thể bỏ sau khi xem lại. Một thực thể không nhận hai lệnh chưa rõ kết quả. Xác nhận và cập nhật cache cùng giao dịch; generation chặn inbox cũ ghi đè xác nhận mới. Đăng xuất/đổi quyền làm cache mất hiệu lực; không chuyển lệnh sang tài khoản khác.

Các bảng `company_workspace_*` không được đưa vào bản sao lưu và bị xóa cache/hàng chờ sau phục hồi. Không phát lại thẩm quyền gửi từ máy khác. Không xóa dữ liệu nghiệp vụ để áp dụng đợt này.

## Giới hạn hiện tại

- Chat cập nhật khi app đang mở bằng kiểm tra định kỳ (10 giây), inbox 15 giây. Chưa có FCM/thông báo nền. Danh sách thành viên nhóm chốt lúc tạo, chưa có giao diện thêm/bớt thành viên.
- Inbox tối đa 200 mục gần nhất và 600KB mỗi phản hồi; chat/lịch sử tối đa 50 mục/lượt. Máy chủ giữ hồ sơ và audit gốc; chưa có giao diện phân trang/tra cứu toàn bộ hồ sơ cũ.
- Tệp tối đa 5MB, 5 tệp mỗi hồ sơ/tin nhắn. Bản chụp tối đa 25MB, gồm hai cơ sở SQLite và media nội bộ theo cơ chế backup hiện có.
- **Cloud kinh doanh là bản chụp Admin, chưa phải đồng bộ từng giao dịch kho/kế toán nhiều máy đồng thời.** Không tự gộp sổ. Tài khoản thường không tải bản chụp chứa tài chính/lương. Khi Cloud có phiên bản mới hơn baseline của máy, phải xem xét và lựa chọn nguồn với lý do; giữ lịch sử bản cũ.
- Các tuyến duyệt/tài khoản cần được Admin cấu hình trước; khi máy chủ chưa chạy, ứng dụng giữ lệnh chờ và không báo đã duyệt thành công.
- Công việc giao cho nhân viên chưa tự tạo công hoặc ca máy. Hồ sơ hành chính chưa tự chuyển thành bút toán tiền thực tế.

## AI chỉ đọc

Backend dùng `AGRICO_AI_MODEL` mặc định `deepseek-chat`; khóa `AGRICO_AI_API_KEY` nằm trong Secret Manager, không nằm trong APK. Giới hạn 20 yêu cầu/tài khoản/ngày. Yêu cầu chưa rõ kết quả giữ nguyên ID để kiểm tra lại; không tự gọi mới vì mất mạng.

Ngữ cảnh mặc định chỉ gồm mã, tiêu đề, trạng thái và thời điểm hồ sơ được quyền xem; không gửi tệp nghỉ ốm hoặc chi tiết lương. Admin có toàn bộ quyền nhạy cảm có thể chọn kỳ và bật tổng thu/chi từ bản chụp đã công bố gần nhất. Tính tiền dùng BigInt/scale, tách VND/LAK, nêu rõ phiên bản/thời điểm nguồn. Đây không phải số dư tiền hiện tại. Trợ lý không có công cụ sửa dữ liệu, duyệt phiếu, thanh toán hoặc gửi chat. Kiểm thử dùng provider giả lập; chưa kiểm thử bằng khóa trả phí thật.

## Kiểm tra trên Windows

Yêu cầu Flutter/Dart theo dự án. Backend Node 22; Firebase CLI 14 và Java 17 cho emulator.

```powershell
npm ci --prefix backend/company-workspace
npm test --prefix backend/company-workspace
npm run test:emulator --prefix backend/company-workspace
.\tools\Verify-Company-Workspace.ps1 -Full -Build
```

Emulator luôn dùng `demo-agrico-workspace` (Firestore 8088, Storage 9199), không dùng project thật. Runner chạy cả các kiểm thử account/catalog trước đó với rules hợp nhất. `npm test` chỉ chạy nghiệp vụ thuần và ngữ cảnh tài chính AI, không cần emulator.

Generator hợp đồng (Dart trên PATH):

```powershell
node backend/company-workspace/tools/generate-contracts.mjs
dart format lib/features/company_workspace/domain/administrative_templates.dart
```

Generator xuất role-policy và mẫu Dart; khi đổi quyền phải rà cả Firestore/Storage rules, không tự thay luật bảo mật.

## Triển khai riêng sau khi duyệt

Chưa deploy. Project dự kiến `agrico-erp`, region Functions `asia-southeast1`, codebase `company-workspace`. Kiểm tra tài khoản Firebase, project/bucket trong `android/app/google-services.json`, Firestore/Storage và điều kiện thanh toán Functions trước vận hành.

1. So sánh/xuất bản rules và indexes đang chạy. Rules mới giữ account/catalog hiện có; indexes giữ index audit cũ và bổ sung workspace. Nếu project có quy tắc hoặc index khác, hợp nhất trước. Không đồng ý xóa index không thuộc đợt này. Storage mặc định đóng ngoài các đường dẫn mới; cần giữ các đường dẫn đang vận hành hợp lệ khi hợp nhất.
2. Chạy `tools/Deploy-Company-Workspace.ps1` để xem mục tiêu. Chỉ sau khi duyệt dùng `-Deploy`. Script không dùng `--force`, chỉ chỉ định hai Functions thuộc codebase mới; không xóa Functions thuộc codebase khác.
3. Để bật AI, nhập khóa tương tác qua Firebase CLI, không gửi khóa qua chat:

```powershell
node backend/company-workspace/node_modules/firebase-tools/lib/bin/firebase.js functions:secrets:set AGRICO_AI_API_KEY --project agrico-erp
.\tools\Deploy-Company-Workspace.ps1 -Deploy -IncludeAI
```

CLI cấu hình `AGRICO_AI_MODEL` khi triển khai. Không commit `.env`. Việc dùng Functions, Storage, AI có thể tính phí; Admin chọn provider và việc gửi ngữ cảnh được phép trước vận hành.

4. Chờ indexes tạo xong. Dùng Admin cấu hình tài khoản/phòng ban/quyền, mẫu và tuyến duyệt. Bản chụp Storage hiện giới hạn tài khoản Admin gốc có vai trò systemAdmin toàn công ty và đủ quyền nhạy cảm.

## Năm kiểm tra điện thoại sau triển khai

1. Thu hoạch/Nhiên liệu mở đúng nơi; thiếu quyền không vào; tên tab đang chọn vẫn đọc được.
2. Hai tài khoản: giao–nhận–tiến độ–nộp–làm lại–nghiệm thu; gửi lại offline không tạo trùng, không tự tăng lương.
3. Tạm ứng/nghỉ phép đúng tuyến; không tự duyệt; yêu cầu bổ sung và xuất Word/tải tệp. Hoàn ứng đúng người/cùng tiền tệ, không vượt phân bổ. Thay người duyệt/thu hồi quyền rồi kiểm tra đọc lại.
4. Chat hai người/nhóm và theo hồ sơ; gửi tệp, ngắt mạng/nối lại; kiểm tra hai người gửi đồng thời vẫn đủ tin theo thứ tự máy chủ và gửi lại không trùng. Người ngoài nhóm không đọc được.
5. Admin công bố/tải xem trước bản chụp ở máy thứ hai; sửa cả hai phía phải báo xung đột; người thường không tải được. AI nêu thiếu dữ liệu/nguồn cũ, không tự làm nghiệp vụ.

Build APK và kiểm tra hai thiết bị là bước xác nhận tại Windows/điện thoại, chưa thực hiện trong môi trường này. Không tự cài hoặc xóa dữ liệu app.
