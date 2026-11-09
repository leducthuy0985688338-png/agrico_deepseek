# Nhân sự, chấm công, lương và phân bổ — 25/10/2026

## Mốc và nguồn dữ liệu

Bổ sung trên checkpoint 46c0a43ad57764c8545b8c9d12d813bc6441690d, nhánh đã nghiệm thu feature/production-planning-currency-20261025. Nguồn chuẩn bị được tái dựng từ archive d1c3c32 và đúng 28 tệp người dùng đã commit/nghiệm thu ở 46c0a43; không dùng nhánh GitHub cũ. Không sửa main, không tự commit/push/merge.

Nhân viên sử dụng **cùng ID/mã nhân công CatalogKind.worker** và parcel_work_resources. Hồ sơ là bảng mở rộng; không tạo nhân viên demo hoặc danh mục nhân công độc lập. Nhân viên không bắt buộc có tài khoản app. Mã người lao động, đơn vị và loại việc tiếp tục được cấp bởi danh mục dùng chung.

Các provider nhân sự/đồng bộ chi phí legacy không được dùng cho luồng V2 mới. Luồng này lưu SQLite trong agrico.db; không ghi sang agrico_costs.db và không giả định đã đồng bộ Cloud.

## Quy tắc công và giá

- Công chuẩn mặc định 480 phút (8 giờ); có thể khai báo chuẩn mới theo hiệu lực mức lương. Giờ thường, tăng ca và nghỉ tách riêng; không tự coi mọi giờ vượt 8h đã được duyệt tăng ca.
- Ca bắt đầu/kết thúc có đủ ngày, giờ UTC; ngày nghiệp vụ là ngày bắt đầu theo UTC+7. Ca qua đêm thuộc ngày bắt đầu. Tối đa 24h/ca; nghỉ phải nhỏ hơn tổng ca. Không có khoảng giờ trùng giữa các bản ghi còn hiệu lực của cùng nhân viên.
- Khi duyệt, tổng phút thường đã duyệt của nhân viên/ngày không được vượt công chuẩn áp dụng. Giờ của nhiều ca không được đếm thành nhiều ngày công mặc định.
- Có lương giờ, lương công và khoán theo khối lượng. Có thể kết hợp cho các phần việc khác nhau, không trùng thời gian. Khoán dùng số lượng và đơn vị; công việc trả theo thời gian vẫn có thể ghi khối lượng hoàn thành để tính năng suất, không biến thành lương khoán.
- Giá tăng ca là giá mỗi giờ do người có quyền khai báo, không tự đặt hệ số hoặc tỷ lệ pháp định. Thiếu giá tăng ca thì không duyệt được công có tăng ca.
- Mức lương theo nhân viên, cơ sở trả lương, đơn vị khoán, loại công việc tùy chọn và ngày hiệu lực. Mức riêng theo loại việc ưu tiên mức chung. Khi có nhiều cơ sở/đơn vị phù hợp mà chưa chỉ rõ, phải chọn rõ để duyệt.
- Khai báo lại cùng phạm vi/ngày tạo phiên bản mới; không sửa mức cũ. Công đã duyệt giữ liên kết mức lương bất biến. Thay tên danh mục không tính lại lương cũ; tên trên bảng lương được chụp khi lập.
- Admin chọn tiền tệ VND/LAK, độ chính xác 0–6 chữ số và làm tròn gần nhất/nửa lên hoặc bỏ phần lẻ. Tính chính xác theo số thập phân/phút; làm tròn tiền từng nguồn theo cấu hình đã chọn. Không có lựa chọn làm tròn ngầm trong biểu khai báo. Tỷ lệ tăng ca/thuế/bảo hiểm không được tự suy đoán.

## Duyệt và phân bổ

Chấm công: nháp → đã duyệt hoặc hủy có lý do. Duyệt ghi snapshot tiền công thường/tăng ca/khoán và chi phí phân bổ trong cùng transaction; lỗi bất kỳ phải rollback toàn bộ. Không sửa trực tiếp công đã duyệt; hủy nguồn rồi ghi bản đúng khi chưa bị bảng lương khóa. Bản hủy vẫn còn lịch sử, không còn trong chi phí hiệu lực.

Một nguồn có thể chia cho các kế hoạch theo phút thường và phút tăng ca, tổng không vượt nguồn. UI hỗ trợ hai dòng kế hoạch, API lưu nhiều dòng. Phần chưa phân bổ được giữ và báo rõ. Phân bổ số tiền nguồn bằng phần dư lớn nhất theo đơn vị tiền nhỏ nhất đã cấu hình; tiền không nhân đôi do làm tròn. Các kế hoạch phải cùng farm, đang thực hiện, đúng ngày và cùng tiền tệ mức lương; công việc tùy chọn phải thuộc kế hoạch và phù hợp nhân viên được giao.

Nếu tiền công đã nằm trong ca máy trọn gói, chọn máy trong bản công: tiền công vẫn vào bảng lương, nhưng chi phí nhân công phân bổ cho sản xuất bằng 0 để không cộng trùng giá ca máy. Đây là ghi nhận thành phần trong giá máy, chưa phải sổ chi phí máy thực tế.

Kế hoạch không được đóng/hủy khi còn công nháp hoặc bảng lương nháp có phụ cấp/thưởng gắn vào đó. Không tự hoàn thành công việc kế hoạch chỉ vì ghi công; trạng thái Công việc vẫn do quy trình hiện có quản lý.

## Bảng lương và chi trả

- Bảng lương lấy nguồn công đã duyệt của đúng nhân viên, tháng YYYY-MM và tiền tệ. Có mã LUONG-YYYYMM-001 tự sinh nguyên tử theo farm/tháng. Không cộng lẫn VND/LAK.
- Lương thực lĩnh = thường + tăng ca + khoán + phụ cấp + thưởng − tạm ứng − khấu trừ. Điều chỉnh khác 0 yêu cầu lý do; không tự khấu trừ thuế/bảo hiểm. Không cho net âm.
- Một nguồn chỉ nằm trong một bảng lương còn hiệu lực. Bảng nháp khóa nguồn; hủy nháp có lý do giải phóng liên kết nhưng giữ lịch sử. Bảng đã duyệt không được hủy/sửa qua luồng nháp này.
- Phụ cấp/thưởng có thể phân bổ vào một kế hoạch cùng tiền tệ, hoặc để chưa phân bổ và báo rõ. Chi phí bổ sung này chỉ có hiệu lực khi duyệt bảng lương. Tạm ứng/khấu trừ là điều chỉnh thực lĩnh, không tự giảm chi phí lao động đã phát sinh.
- Chi trả từng phần cho bảng đã duyệt, có ngày và tham chiếu chứng từ. ID thanh toán chống gửi trùng, tổng trả không vượt thực lĩnh, cùng tiền tệ. Chi trả không tạo thêm chi phí sản xuất.
- Đây là sổ theo dõi trả lương đã thực hiện, chưa tự sinh phiếu chi hoặc chuyển tiền ngân hàng. Số đã trả/còn lại trên báo cáo là đến thời điểm xuất; lịch sử từng lần trả được xuất riêng.

## Quyền

Dùng permission hiện có, không tự tăng quyền vai trò:

- employee.view: xem nhân viên và công trong phạm vi allFarm của đợt triển khai; employee.edit: sửa hồ sơ, xem các thuộc tính nhạy cảm tương ứng.
- attendance.record: lập công nháp. attendance.verify + payroll.view: duyệt nguồn tính tiền. attendance.verify: hủy nguồn chưa bị khóa.
- payroll.view: mức lương/bảng lương và giá trị tiền công. Người chỉ chấm công không nhận mức giá/số tiền từ service.
- payroll.manage: khai báo mức lương, lập/hủy bảng nháp. payroll.approve: duyệt bảng lương. payroll.approve + cash.record: ghi trả lương.
- report.personnel + payroll.view + data.export: bộ báo cáo nhân sự tài chính.
- finance.view: đọc chi phí nhân công đã phân bổ trong kế hoạch; không trả hồ sơ cá nhân hoặc mức lương cấu hình ở projection này.

Admin hiện có đầy đủ quyền. Những vai trò chỉ có scope phòng ban/nhóm chưa được tự mở rộng sang allFarm; không giả vờ hỗ trợ scope hẹp khi truy vấn hiện là phạm vi công ty/farm.

## Báo cáo

Bộ nhân sự có 8 trang: THONG TIN, DANH SACH NV, CHAM CONG, BANG LUONG, CHI TRA LUONG, NANG SUAT LD, PHAN BO NHAN CONG, TONG HOP. Lọc theo tháng/nhân viên, giữ trạng thái nháp/hủy ở chi tiết, chỉ tổng hợp nguồn có hiệu lực. Năng suất lấy khối lượng đã duyệt/giờ, không đếm dòng phân công và không suy đoán xếp loại. Không gộp khác đơn vị/loại việc.

Báo cáo kế hoạch bổ sung thực tế nhân công và trang NHAN CONG SD. Chi phí máy thực tế vẫn chưa nối, vì vậy chưa tuyên bố tổng chi phí sản xuất đầy đủ. Tổng tiền theo từng tiền tệ, không tự quy đổi.

Các file Excel có thông tin phạm vi, tiêu đề cố định, bộ lọc, cột số đúng kiểu trong giới hạn 15 chữ số của Excel; số dài hơn giữ text để không mất chính xác. Nền layout xuất được dùng chung thay vì duy trì hai thuật toán tạo file.

## Schema, backup và kiểm chứng

Thêm 9 bảng personnel_profiles_v1, personnel_pay_rates_v1, personnel_entries_v1, production_labor_costs_v1, personnel_payrolls_v1, personnel_payroll_lines_v1, personnel_payments_v1, personnel_audit_v1, personnel_payroll_sequences_v1. Bootstrap tạo sau danh mục. Không xóa dữ liệu kho/thửa/vụ/kế hoạch đã nghiệm thu.

Backup bao gồm bảng mới; preflight kiểm tra danh tính/farm, interval/giờ, mức lương hiệu lực, tính tiền, phân bổ, nguồn bảng lương, thanh toán và số chứng từ. Backup cũ thiếu toàn bộ bảng nhân sự khi chưa có dữ liệu có thể khôi phục theo cơ chế schema hiện tại; payload chỉ bỏ một phần bảng nhân sự có dữ liệu bị từ chối. Kiểm tra diễn ra trên database tạm, không sửa DB thật.

Chạy kiểm thử nghiệp vụ/repository bằng Dart/SQLite và phân tích tĩnh trong môi trường chuẩn bị; widget/full Flutter/Android và kiểm tra điện thoại chạy tại Windows trước checkpoint. Không coi kết quả native thay cho full Flutter.

## Nghiệm thu thiết bị

1. Mở Nhân công/Nhân sự. Tạo nhân viên qua Danh mục dùng chung, mã tự sinh; sửa hồ sơ và kiểm tra vẫn cùng mã trong Công việc.
2. Khai báo công 8h: 80.000 VND/công, OT 15.000 VND/h, chuẩn 480 phút, chọn làm tròn và số lẻ. Ghi 08:00–19:00, nghỉ 60 phút, OT 120 phút, gắn kế hoạch VND đang thực hiện. Sau duyệt: 80.000 + 30.000 = 110.000 VND; kế hoạch nhận đúng 110.000.
3. Với nhân viên/ngày khác, khai báo khoán 50.000 VND/ha, ghi 2,5 ha → 125.000 VND. Thử loại việc có đơn giá riêng và bản công được đánh dấu đã trong ca máy để kiểm tra không tính trùng.
4. Lập bảng cho nguồn 110.000, phụ cấp 5.000 gắn kế hoạch, tạm ứng 10.000 → thực lĩnh 105.000. Duyệt rồi ghi trả 40.000 → còn 65.000. Chi phí kế hoạch là 115.000, không tăng khi trả tiền. Kiểm tra LAK báo riêng.
5. Xuất bộ Excel 8 trang, báo cáo kế hoạch có nhân công; khởi động lại kiểm tra còn hồ sơ/công/lương. Thử backup/restore, nguồn chưa đủ giá hoặc sai quyền không được duyệt.
