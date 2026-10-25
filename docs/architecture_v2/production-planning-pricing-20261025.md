# Kế hoạch sản xuất, giá xuất Admin và VND/LAK — 25/10/2026

Nguồn: archive người dùng cung cấp, ZIP comment xác nhận commit d1c3c320653a4cb929b282655a424f2921a2d0bd. Không đổi main, không push/merge. Thay đổi analysis_options.yaml của người dùng không thuộc bản giao.

## Phạm vi đợt này

- Kế hoạch thuộc một thửa V2/mùa vụ, mã KH-YYYYMM-001 tự cấp trong giao dịch SQLite. Có cây trồng, ngày đầu/cuối, dự toán vật tư, nhân công, ca máy, giờ công và số ca dự kiến. Một kế hoạch chọn VND hoặc LAK. Đây là kế hoạch chi tiết; kế hoạch tổng nhiều thửa chưa nằm trong đợt này.
- Trạng thái nháp → thực hiện → tạm dừng/hoàn thành; nháp/tạm dừng có thể hủy. Kiểm tra revision và ghi audit. Chặn hoàn thành khi còn công việc chưa xong.
- Công việc sử dụng **cùng ID và trạng thái tại farm_tasks_v2**. production_plan_tasks_v1 chỉ giữ liên kết kế hoạch, giai đoạn, khối lượng/đơn vị và revision. Công việc tạo từ kế hoạch xuất hiện trong module Công việc cũ; hoàn thành ở một nơi được đọc tại nơi còn lại. Trigger tăng revision và chặn đổi thửa trái kế hoạch hoặc sửa khi kế hoạch/vụ đã đóng. Không tạo một danh sách việc độc lập cần nhập lại.
- Số lượng hỗ trợ tối đa 6 chữ số thập phân, lưu lượng nguyên theo hệ số 1.000.000, giới hạn giá trị scaled trong miền số nguyên chính xác của web/SQLite. stock/quantity cũ chỉ là projection tương thích. Cập nhật tồn dùng stock_units, không cộng double làm nguồn chuẩn.
- Giá xuất do người có quyền inventory.price nhập; mặc định chỉ systemAdmin có quyền này. Quyền được kiểm tra ở Application. Phiếu xuất thiếu giá, tiền tệ hoặc xác nhận giá 0 bị chặn. UI không tự điền giá danh mục. Người kho không có quyền định giá chưa có luồng nháp chờ duyệt trong đợt này; không thể ghi sổ phiếu xuất.
- Giá/tiền nguyên tệ lưu dạng chuỗi thập phân chính xác, đơn giá tối đa 6 số lẻ; nhân lượng × giá giữ đến 12 số lẻ. Không tự chọn quy tắc làm tròn. Trường REAL cũ là projection đọc tương thích, không dùng để tính tiền chuẩn mới.
- Xuất sản xuất bắt buộc kế hoạch đang thực hiện, đúng thửa/vụ/farm, ngày phiếu nằm trong kỳ kế hoạch và tiền tệ trùng kế hoạch. Kho, số phiếu, movement và chi phí cùng một transaction. Khóa movement ID cho phép gửi lại cùng nội dung không ghi hai lần; cùng ID khác nội dung bị từ chối. Giá, người xác nhận và kế hoạch được giữ trên giao dịch.
- Báo cáo Excel gồm THONG TIN, KE HOACH SAN XUAT, VAT TU SD, LICH TAC VU, TONG HOP. Lọc kế hoạch/thửa/kỳ thực tế, dự toán là toàn kế hoạch. VND/LAK tổng riêng; không quy đổi khi chưa có tỷ giá. Cột số được ghi dạng số trong giới hạn 15 chữ số của Excel; giá trị dài hơn giữ dạng text để không mất độ chính xác. Có header, đóng băng hàng đầu, lọc bảng và độ rộng cột.
- Chi phí vật tư thực tế lấy từ phiếu xuất. Thực tế nhân công/ca máy và tổng chi phí sản xuất chưa xác định trong đợt này, không hiển thị 0 giả. Giá ca máy dự toán là giá trọn gói.

## Quyền và truy cập

- Đọc kế hoạch kèm dự toán hiện yêu cầu inventory.view + finance.view và allFarm. Màn kế hoạch chỉ xuất hiện với người xem tài chính.
- Tạo kế hoạch: production.plan + finance.view. Tạo việc: production.plan + task.create. Hoàn thành/mở lại việc: production.plan + task.complete/task.edit.
- Xuất kho: inventory.manage + inventory.price; quyền định giá không mặc nhiên cấp cho thủ kho/director.
- Xuất báo cáo kế hoạch: finance.view + data.export, kiểm tra lại trước khi tạo file.
- Không giả định dữ liệu mới đã đồng bộ Cloud. Đây là nền lưu cục bộ offline-first.

## Schema và dữ liệu

Thêm bảng production_plans_v1, production_plan_tasks_v1, production_plan_sequences_v1, production_plan_audit_v1; thêm các cột precision/price/currency/actor/plan vào inventory. createSchema bổ sung có kiểm tra cột, không reset dữ liệu đang tương thích. Không bump user_version riêng trong module: bootstrap hiện gọi createSchema mỗi lần mở; restore kiểm tra quan hệ và schema thực tế.

Dữ liệu app đã được người dùng xóa trước đợt này. Không thêm lần xóa mới, không phục hồi legacy bridge. Migration dọn test một lần cũ chỉ được bổ sung để reset stock_units cùng stock trong lần chạy vốn đã có; marker complete vẫn ngăn dọn lại dữ liệu mới. Backup có phiếu xuất cũ thiếu giá/tiền tệ/kế hoạch không tương thích sẽ bị từ chối, không gán giá hoặc tiền tệ giả để nhập lại.

Restore kiểm tra số lượng scaled, đối soát tồn, chi phí với movement, farm/thửa/vụ/kế hoạch, mã/counter kế hoạch và quan hệ công việc dùng chung. Không sửa database thật khi kiểm tra.

## Còn các đợt sau

Chấm công 8h/tăng ca/lương khoán; ca máy thực tế trọn gói; công nợ phải thu/phải trả; thu hoạch/bán hàng; kế hoạch tổng nhiều thửa; bộ đầy đủ 20 báo cáo/dashboard và tích hợp sync. Những nội dung này đã được ghi trong đặc tả, không được tuyên bố đã triển khai ở đợt này.

## Nghiệm thu trên điện thoại sau khi kiểm thử Windows đạt

1. Tạo thửa và mùa vụ, mở biểu tượng Kế hoạch từ Mùa vụ và chi phí; tạo kế hoạch VND có dự toán, chuyển sang thực hiện. Kiểm tra mã tự sinh.
2. Thêm công việc có lượng 2,5 ha; kiểm tra cùng việc trong module Công việc; hoàn thành rồi quay lại kế hoạch để tải lại trạng thái. Kế hoạch còn việc chưa xong không được hoàn thành.
3. Nhập 10,5 kg; Admin xuất 2,25 kg cho kế hoạch, đơn giá 20.000 VND. Tồn phải còn 8,25 kg, chi phí là 45.000 VND và gắn đúng kế hoạch.
4. Tạo kế hoạch LAK và một phiếu riêng; kiểm tra báo cáo không cộng VND vào LAK. Chọn kỳ không có phiếu thì thực tế vật tư bằng 0 nhưng dự toán vẫn là toàn kế hoạch.
5. Xuất Excel, mở đủ 5 trang, thử lọc, tiêu đề cố định và cộng số; khởi động lại app kiểm tra kế hoạch/tồn/chi phí còn nguyên. Người không có quyền Admin không ghi sổ giá xuất.

Không cần xóa app hoặc dữ liệu thêm lần nữa để cài bản mới. Chỉ build/cài sau khi các kiểm tra thực tế đạt; không dùng script patch cũ của checkpoint ef233a2.
