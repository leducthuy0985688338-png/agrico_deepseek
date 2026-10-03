# AGRICO A02 — đăng nhập và phiên offline

## Trạng thái và phạm vi

A02 thay đăng nhập demo bằng Firebase Email/Password. Chưa có chức năng tự đăng ký. Tài khoản và quyền được cấp bởi người quản trị qua Firebase Console trong checkpoint này. Chưa có màn hình Admin cấp tài khoản trong ứng dụng, chưa đồng bộ dữ liệu nghiệp vụ/outbox.

Dữ liệu SQLite hiện có được giữ nguyên, dùng `farmId = local-farm`. Không đổi mã, quan hệ hay hồ sơ lô/thửa/cây. Không tự chạy lại nhập dữ liệu legacy khi đăng nhập. Mỗi thành viên có UID riêng, membershipId bằng UID; tài khoản cùng trang trại dùng chung dữ liệu theo quyền được cấp.

Một số module cũ chưa có scope/guard đầy đủ (tài chính, kho, máy, nhân sự, nhiên liệu, AI, sao lưu toàn bộ) tạm không có đường truy cập trong A02. Chúng sẽ được mở lại khi kiểm tra quyền ở tầng nghiệp vụ hoàn tất. Công việc hiện chỉ mở cho quyền xem có phạm vi toàn trang trại; phân công task cho từng người sẽ được nối ở checkpoint kế tiếp. Xem lô/thửa hỗ trợ `allFarm`, `assignedFields` và `project`; các nghiệp vụ còn thiếu ngữ cảnh phòng/đội bị từ chối. Đây chưa phải rollout đầy đủ 17 vai trò.

## Thiết lập lần đầu, trước khi cài APK A02

1. Mở https://console.firebase.google.com/ và chọn đúng dự án hiện dùng cho Android `com.agrico.erp`.
2. Kiểm tra cấu hình Android: file `android/app/google-services.json` trên máy phải thuộc dự án đó và package đúng. File này không có trong ZIP vì có thể đang bị Git bỏ qua; không tạo dự án mới nếu dự án hiện tại đã đúng.
3. Authentication → Sign-in method → bật Email/Password.
4. Authentication → Users → Add user. Dùng email thật do công ty cấp và mật khẩu riêng. Sao chép UID. Không gửi mật khẩu cho trợ lý, không đưa vào Git.
5. Nếu chưa có Cloud Firestore, tạo database ở chế độ production. Trong tab Rules, dùng nội dung `docs/security/agrico-memberships.rules` cho dự án AGRICO riêng. Template này đóng các collections legacy; nếu dự án còn phục vụ ứng dụng khác, phải hợp nhất rule mà không có rule rộng cho phép ghi vào `agrico_memberships`. Chưa có lệnh nào trong bản vá tự publish rules.
6. Firestore → Data → tạo collection `agrico_memberships`, document ID chính là UID. Thêm các trường trong bảng dưới. Trong Console, nhập `roles` là array chứa map, không phải chuỗi JSON.

| Trường | Kiểu | Giá trị tài khoản đầu tiên |
|---|---|---|
| schemaVersion | number | 1 |
| userId | string | UID vừa sao chép |
| membershipId | string | Cùng UID |
| farmId | string | local-farm |
| active | boolean | true |
| offlineUntil | timestamp | Ngày hết hạn offline do Admin chọn, sau thời điểm hiện tại |
| roles | array of maps | `{role: systemAdmin}` và `{role: director}` |
| extraPermissions | array of strings | Để trống nếu chỉ quản trị và xem; xem bên dưới nếu cần tiếp tục thao tác sản xuất |
| extraPermissionScopes | array of strings | `allFarm` khi cấp quyền bổ sung toàn trang trại |
| deniedPermissions | array of strings | Để trống |

Các trường ID tùy chọn: `projectIds`, `departmentIds`, `teamIds`, `fieldIds`, `taskIds`, `machineIds`, `warehouseIds`, đều là array of strings. Tên role và scope phân biệt chữ hoa/thường, xem `company_roles.dart`. Vai trò mặc định được dùng khi map role không có `scopes`.

Để tài khoản chủ dự án tiếp tục tạo/sửa lô, thửa, cây và làm các bài test sản xuất đã có, Admin có thể cấp riêng `extraPermissions`:

```json
["field.create", "field.edit", "field.measure", "field.boundary.edit",
 "field.boundary.verify", "field.google_earth.import", "field.google_earth.export",
 "task.create", "task.view", "task.complete"]
```

`extraPermissionScopes = ["allFarm"]`. Quyền bổ sung phải được chọn có chủ đích, không cấp danh sách này cho toàn bộ nhân viên. Vai trò `systemAdmin` không tự có quyền sửa sản xuất hoặc duyệt tài chính. Vai trò `director` cho xem báo cáo/duyệt theo A01, nhưng các module chưa có guard vẫn đóng trong A02.

## Dùng offline

- Đăng nhập lần đầu và đổi sang tài khoản khác cần mạng; mật khẩu được Firebase xác thực, không lưu trong cache AGRICO.
- Sau lần xác thực thành công, đóng hẳn/mở lại app khi mất mạng sẽ phục hồi phiên của cùng UID Firebase, cùng dự án, cùng farm và còn hạn `offlineUntil`.
- App chỉ dùng dữ liệu nghiệp vụ đã có trên thiết bị; chưa tự tải dữ liệu ở máy khác xuống.
- `offlineUntil` do Admin cấp trên server. Mất mạng không kéo dài hạn. Không áp đặt số ngày cố định trong A02. Cần Admin cập nhật hạn khi muốn gia hạn; tự động cấp lease theo chính sách sẽ bổ sung sau.
- Đăng xuất xóa cache phiên, không xóa SQLite. Sau đăng xuất cần mạng để đăng nhập lại.
- Có mạng: kiểm tra quyền khi mở app, quay lại app và định kỳ khoảng 5 phút. `active=false`, không tìm thấy membership, tài khoản bị từ chối hoặc quyền bị server từ chối sẽ đóng phiên, không quay về quyền cũ. Chỉ lỗi mạng/unavailable/timeout mới cho dùng cache còn hạn.
- Thu hồi quyền khi thiết bị không có mạng chỉ được biết khi kết nối lại hoặc đến hạn lease. Đồng hồ bị lùi so với lần ghi nhận cục bộ bị từ chối offline; đây không phải đồng hồ chống can thiệp phần cứng.
- Cache quyền riêng trong thư mục private của app, tách khỏi backup SQLite; không chứa mật khẩu/token. APK debug phục vụ kiểm thử; không dùng quyền truy cập debug/root để đánh giá bảo mật bản phát hành. Ký/attestation lease và hardening thiết bị là công việc riêng trước triển khai có yêu cầu chống can thiệp.
- Routes nghiệp vụ nằm trong Navigator của phiên; logout/thu hồi/hết hạn đóng cả stack. AuthorizationService kiểm tra lại deadline mỗi quyết định, không chỉ lúc mở app.
- Thay quyền khi đang mở form có thể làm form bị đóng. Dữ liệu đã lưu được giữ; hãy lưu form trước khi rời ứng dụng.

## Kiểm thử thiết bị

1. Tài khoản chưa có membership hoặc sai mật khẩu: không vào ứng dụng.
2. Tài khoản đầu tiên có membership: đăng nhập, xem lô/thửa đã lưu; thử sửa nếu đã cấp quyền bổ sung.
3. Đóng app, bật chế độ máy bay, mở lại: vào phiên còn hạn; dữ liệu đã lưu còn nguyên.
4. Offline: đăng xuất rồi thử đăng nhập lại phải bị chặn; bật mạng để vào lại.
5. Với tài khoản thử riêng: đặt `active=false` trên Console, để thiết bị có mạng và quay lại app: phiên bị đóng. Không thử thu hồi tài khoản quản trị duy nhất trước khi có tài khoản dự phòng.
6. Tài khoản thử hết hạn `offlineUntil`: không vào offline; Admin cập nhật hạn và kết nối lại mới vào được.

## Tài liệu chính thức

- https://firebase.google.com/docs/auth/flutter/password-auth
- https://firebase.google.com/docs/auth/flutter/start
- https://firebase.google.com/docs/firestore/security/get-started
- https://firebase.google.com/docs/firestore/manage-data/enable-offline
