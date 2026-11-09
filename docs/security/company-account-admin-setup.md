# AGRICO A03 — Tài khoản nhân viên và quyền truy cập

Baseline: `1af8e0a`, nhánh `feature/parcel-work-resource-reconciliation`.

## Chức năng trong checkpoint này

- Cài đặt → Tài khoản và phân quyền: danh sách tối đa 200 hồ sơ trong trang trại, cấp hồ sơ từ UID đã có, sửa tên, khóa/mở quyền truy cập, chọn tối đa 4 vai trò trong 17 mẫu, phạm vi riêng cho từng vai trò, quyền bổ sung và quyền cấm, hạn offline.
- Quyền cấm thắng quyền được cấp. Nhân viên máy chỉ xem công việc và máy được giao theo mẫu A01; thêm vai trò không gộp phạm vi của quyền khác.
- Sửa hồ sơ cần mạng và quyền máy chủ. Giao dịch Firestore kiểm tra phiên bản hồ sơ, lưu nguyên trạng trước/sau vào nhật ký cùng lần ghi. Không xếp hàng các thay đổi quyền khi mất mạng.
- Hồ sơ của chính Admin và tất cả UID có đăng ký trong `agrico_access_admins` không được sửa bằng ứng dụng. Không xóa hồ sơ/nhật ký. Quản lý các Admin gốc qua Firebase Console; ứng dụng không được ghi registry hay chính sách.
- Nếu chính sách bật gia hạn, khi kiểm tra quyền qua mạng và hạn offline còn dưới một ngày, ứng dụng xin thời hạn mới. Rules chỉ chấp nhận thay đổi thời hạn của tài khoản đang hoạt động, theo số ngày cho phép. Gia hạn không đổi vai trò/phạm vi hoặc mở khóa tài khoản.
- Nhật ký xem 50 thay đổi mới nhất; cần chỉ mục bên dưới.

**Chưa bao gồm:** tạo/xóa/khóa Firebase Authentication trong ứng dụng, đồng bộ dữ liệu nghiệp vụ/outbox, áp dụng các quyền vào toàn bộ phân hệ cũ. Tài khoản Email/Password mới vẫn tạo tại Authentication → Users → Add user. Khóa ở màn hình A03 là khóa quyền vào AGRICO, không phải vô hiệu hóa tài khoản Firebase Auth. Không dùng quyền Admin SDK hoặc khóa dịch vụ trong điện thoại. Các phân hệ chưa có kiểm tra quyền đầy đủ tiếp tục đóng.

## Thiết lập một lần trên Firebase `agrico-erp`

Thực hiện trước khi cài APK A03. Giữ nguyên hồ sơ A02 và dữ liệu SQLite.

### 1. Đăng ký Admin gốc

Firestore → Data → Start collection: `agrico_access_admins`.

Document ID là UID Admin đã đăng nhập A02:
`VWHGtSrPIjMdxwFQvkqh8j7kZ1g1`.

| Field | Type | Value |
| --- | --- | --- |
| farmId | string | local-farm |
| active | boolean | true |

Đây là quyền quản trị máy chủ. Vai trò `systemAdmin` trong hồ sơ nhân viên chỉ là mẫu quyền ứng dụng; tự thêm vai trò đó không làm người dùng trở thành Admin máy chủ. Muốn bổ nhiệm Admin mới, chủ dự án thêm UID vào registry bằng Console và cấp vai trò tương ứng. Không để nhân viên có quyền IAM sửa Firebase Console.

### 2. Chính sách offline

Start collection: `agrico_access_policy`; Document ID: `local-farm`.

Giá trị đề xuất để kiểm thử, có thể điều chỉnh trong Console:

| Field | Type | Value | Ý nghĩa |
| --- | --- | --- | --- |
| autoRenew | boolean | true | Cho phép tài khoản đang hoạt động xin gia hạn khi có mạng |
| offlineDays | int64 | 7 | Số ngày cấp khi tự gia hạn |
| maxOfflineDays | int64 | 30 | Hạn tối đa Admin được nhập từ thời điểm sửa hồ sơ |

Cả hai số ngày phải từ 1 đến 90; `offlineDays` không vượt `maxOfflineDays`. Trước khi đưa vào vận hành, công ty chọn thời hạn phù hợp với thời gian mất mạng thực tế và nhu cầu thu hồi quyền. Mất mạng thì giữ hạn đã nhận, không tự kéo dài bằng đồng hồ điện thoại. Có mạng, hệ thống kiểm tra tài khoản và quyền trước khi chấp nhận gia hạn. Hạn đề nghị có khoảng đệm 5 phút so với đồng hồ thiết bị và được Rules kiểm tra với `request.time` của máy chủ. Đồng hồ sai có thể làm yêu cầu bị từ chối.

Khóa tài khoản không thể cập nhật tức thì cho điện thoại mất mạng: thiết bị bị khóa khi nhận trạng thái mới lúc kiểm tra quyền hoặc khi hạn đã cấp kết thúc. Không xóa dữ liệu nghiệp vụ khi hết hạn/đăng xuất.

### 3. Publish Rules A03

Mở `docs/security/agrico-memberships.rules` trong VS Code, sao chép toàn bộ vào Firestore → Rules → Publish. Đây là thay thế Rules A02 trong dự án AGRICO, không thêm quy tắc `allow read, write: if true`.

### 4. Tạo chỉ mục nhật ký

Firestore → Indexes → Composite → Add index:

| Mục | Giá trị |
| --- | --- |
| Collection ID | agrico_access_audit |
| Field 1 | farmId — Ascending |
| Field 2 | occurredAt — Descending |
| Query scope | Collection |

Chờ trạng thái Enabled. Định nghĩa tương ứng lưu tại `docs/security/firestore-access.indexes.json`.

## Kiểm thử điện thoại sau khi cài đè

1. Admin đăng nhập online, vào Cài đặt → Tài khoản và phân quyền. Phải xem được hồ sơ hiện tại; mở hồ sơ của chính mình chỉ xem, không có nút Lưu.
2. Tạo một tài khoản thử khác ở Firebase Authentication, sao chép UID. Trong AGRICO, cấp tên nhân viên, vai trò Công nhân vận hành máy hoặc Kỹ thuật nông nghiệp, phạm vi phù hợp, hạn 7 ngày và lý do. Nếu cần kiểm tra xem lô/thửa, nhập **ID** một thửa đang tồn tại vào phạm vi lô/thửa được giao; ID không phải mã AGR-NONG-Txxx.
3. Sửa hồ sơ tài khoản thử, đổi vai trò/phạm vi hoặc thêm quyền cấm. Xem Nhật ký: có đúng người sửa, tài khoản nhận và lý do; Firestore nhật ký có toàn bộ trước/sau. Mở cùng hồ sơ ở hai máy, lưu máy thứ nhất rồi lưu máy thứ hai phải báo hồ sơ đã thay đổi.
4. Tắt mạng trên máy Admin rồi thử lưu thay đổi hồ sơ: không thành công offline, không tự nâng quyền trong cache. Kết nối lại, tải danh sách để xác nhận trạng thái trước khi thử lại; mất mạng lúc đang gửi có thể có kết quả chưa xác định.
5. Đăng nhập tài khoản thử, kiểm tra chỉ thấy các thửa được giao; không có màn hình quản trị. Sau đó Admin khóa hồ sơ thử. Thiết bị nhân viên kết nối lại và kiểm tra quyền phải đóng phiên; dữ liệu lô/thửa vẫn còn. Không thử khóa Admin gốc duy nhất.
6. Để thử tự gia hạn: sửa `offlineUntil` của **tài khoản thử** thành thời điểm đã qua bằng Console, giữ `active=true` và chính sách gia hạn bật. Đăng nhập online phải được nhận hạn mới khoảng 7 ngày. Tắt mạng, đóng/mở ứng dụng phải vào được. Với `active=false`, việc gia hạn phải bị từ chối.

Công việc được giao, máy/kho, phòng ban và danh mục sẽ được nối các kiểm tra quyền trong các checkpoint tiếp theo. Không mở lại các route cũ chỉ vì vai trò đã được cấp.

## Kiểm tra tự động

- Dart 3.12.2: 10 test dịch vụ phân quyền và analyze thuần Dart đạt trong môi trường đóng gói.
- Firebase Emulator: 12 test Rules đạt, bao gồm hồ sơ 4 vai trò, chặn tự nâng quyền, registry/policy bất biến, gia hạn có giới hạn, bảo vệ nhật ký.
- Widget tests và toàn bộ Flutter phải chạy trên Windows trước khi build/cài. Lệnh Flutter ở môi trường đóng gói bị kiểm tra phê duyệt tự động chặn vì truy cập metadata máy chủ; không xem đây là kết quả Flutter pass.
- Rules dùng giới hạn 4 vai trò/hồ sơ để tránh vượt ngân sách biểu thức Firestore. Dữ liệu quyền khác vẫn được chọn từ danh sách mã đã biết; dịch vụ kiểm tra tên và ID, phiên bản, lý do.
- Cache A02 vẫn là file riêng của ứng dụng, không lưu mật khẩu/token, chưa phải lease có chữ ký chống sửa trên thiết bị root/debug. Bảo vệ cache và App Check nằm ngoài checkpoint này.

Tham khảo chính thức:
- https://firebase.google.com/docs/firestore/security/rules-conditions
- https://firebase.google.com/docs/firestore/security/rules-fields
- https://firebase.google.com/docs/auth/admin/manage-users
