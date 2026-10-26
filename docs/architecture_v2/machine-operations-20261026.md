# Máy móc, ca máy, nhiên liệu và bảo dưỡng — 26/10/2026

Nền: 550ea18b983a95bda7afc0df5dcedbcf301b2387. Nguồn được dựng từ đúng bản 46c0a43 và 18 tệp nhân sự đã nghiệm thu, có sửa callback reload theo log Windows đạt 1.681 test. Bản máy không sửa main, không tự commit/push/merge, không đặt lại dữ liệu app.

## Danh tính và quyền

Máy/người vận hành dùng cùng ID/mã trong company_catalog_entries_v1 và parcel_work_resources. Tạo danh mục vẫn qua luồng cấp mã tự động hiện có; hồ sơ máy chỉ là phần mở rộng (model, serial, biển số, chủ sở hữu, loại nhiên liệu, đơn vị đồng hồ hour/km, ghi chú). Cấu hình đơn vị đồng hồ trước khi nhập dữ liệu; sau khi có nhật ký/chứng từ còn hiệu lực không cho đổi đơn vị ngầm.

UI → MachineService → MachineRepository → SqliteMachineRepository. SQLite offline-first, phạm vi allFarm; không tự mở quyền cho scope hẹp hoặc đồng bộ Firebase giả định.

- machine.view: xem máy/nhật ký; giá và các sổ chi phí chỉ khi có thêm finance.view.
- machine.maintain: hồ sơ và lập bảo dưỡng (phần tiền cần finance.view).
- machine.assign + finance.approve: khai báo giá ca máy.
- machine.log: lập nhật ký; lập nhiên liệu cần thêm finance.view.
- machine.verify + finance.view: duyệt nhật ký/chi phí; hủy nhật ký có lý do cần machine.verify; hủy sổ thành phần cần thêm finance.view.
- report.operations + data.export + finance.view: xuất bộ báo cáo máy.

Admin hiện tại có quyền phù hợp; không thêm quyền vào vai trò đang có. Danh mục dùng chung còn kiểm tra quyền riêng của luồng danh mục.

## Giá ca và nhật ký

Một giá ca khai báo: máy, ngày hiệu lực, tiền VND/LAK, số phút cho một ca, số lẻ tiền 0–6, cách làm tròn gần nhất/nửa lên hoặc bỏ phần lẻ. Không tự mặc định ca máy bằng 8h. Đơn giá là trọn gói gồm người lái/nhiên liệu/bảo dưỡng và các thành phần đã thống nhất. Khai báo cùng ngày tạo revision bất biến; bản đã duyệt giữ rate_id cũ. Không dùng REAL/double để tính tiền.

Nhật ký có người vận hành, ngày/giờ đầu–cuối UTC+7, phút nghỉ/dừng không tính giá, đồng hồ đầu/cuối, sản lượng/đơn vị tùy chọn. Giờ tính giá = tổng phút − phút dừng. Tiền = giá ca × phút vận hành / phút chuẩn; làm tròn đúng chính sách đã chọn. Đây là tính theo phần ca; không làm tròn thành cả ca và không tính thêm OT máy ngoài giá đã khai báo.

Ca tối đa 24h, ngày nghiệp vụ là ngày bắt đầu. Chống chồng khoảng giờ của cùng máy hoặc cùng người lái, kể cả bản nháp. Đồng hồ không lùi so với các nhật ký còn hiệu lực trước/sau, kể cả nhập lùi ngày. Không giả định km phải bằng giờ hoặc số đồng hồ phải khớp toàn bộ giờ ca.

Một nhật ký có thể chia nhiều kế hoạch theo phút, UI hỗ trợ hai dòng; phần còn lại chưa phân bổ được giữ riêng. Kế hoạch phải đang thực hiện, đúng farm, đúng ngày và cùng tiền tệ khi duyệt. API có taskId tùy chọn thuộc kế hoạch và phù hợp người lái. Phân bổ bằng phần dư lớn nhất, tổng tiền đã phân bổ không vượt tiền nguồn. Không tạo bản ghi công việc thứ hai.

Nháp → đã duyệt hoặc hủy có lý do. Duyệt tiền, phân bổ và audit trong cùng transaction. Không sửa bản đã duyệt; hủy rồi ghi nguồn đúng. Kế hoạch đã đóng không cho hủy nguồn đã phân bổ; kế hoạch còn nhật ký máy nháp không được hoàn tất/hủy. ID yêu cầu cố định chống gửi trùng; cùng ID khác nội dung bị từ chối. ID nội bộ không thay thế mã danh mục.

## Chống tính trùng lương lái máy

Lương lái vẫn có thể theo dõi/chi trả qua nhân sự. Khi có công đã duyệt trùng thời gian ca máy, phải đánh dấu công đã nằm trong đúng giá ca máy (machine_id). Kiểm tra ở cả hai thứ tự duyệt: duyệt công trước hoặc ca máy trước. Công lái này vẫn phải trả lương nhưng chi phí nhân công phân bổ bằng 0; chi phí sản xuất nhận một lần ở giá ca máy. Backup cũng kiểm tra quan hệ này.

## Nhiên liệu và bảo dưỡng

Sổ nhiên liệu ghi số lít đã cấp, ngày, đồng hồ tùy chọn, tổng giá trị thành phần, tiền tệ, tham chiếu chứng từ và mô tả. Tổng tiền do người có quyền điền; không tự suy diễn giá xuất kho. Một tham chiếu/dòng nguồn cùng farm/máy/loại không được ghi lặp khi chưa hủy. Nếu cùng chứng từ có nhiều dòng thì tham chiếu phải phân biệt dòng.

Sổ bảo dưỡng ghi ngày thực hiện, nội dung, số đồng hồ, giá trị thành phần và tham chiếu, tùy chọn ngày/mốc đồng hồ lần tiếp. Ngày/mốc tiếp phải tăng so với lần này. Danh sách máy và báo cáo hiển thị đến hạn khi đạt ngày hoặc mốc đồng hồ. Dùng bản bảo dưỡng đã duyệt gần nhất; chưa quản lý nhiều chu kỳ độc lập theo từng phụ tùng hoặc lệnh sửa chữa nhiều bước.

Cả hai sổ có nháp/duyệt/hủy, giữ audit. Đây là sổ vận hành và đối chiếu thành phần; **không tự tạo phiếu xuất kho, phiếu chi, khoản phải trả hoặc chuyển tiền**. Tham chiếu là chứng từ nguồn đã xử lý ở sổ tương ứng, chưa phải liên kết FK tới chứng từ kho/tài chính. Không tự trừ kho hoặc cộng lại nhiên liệu/bảo dưỡng vào chi phí sản xuất. Liên kết chứng từ tài chính tổng thể thuộc đợt thu/chi/công nợ tiếp theo.

## Báo cáo và backup

Excel máy 9 trang: THONG TIN, DANH SACH MAY, NHAT KY CA MAY, NHIEN LIEU, BAO DUONG, PHAN BO MAY, TONG HOP, NANG SUAT MAY, LICH BAO DUONG. Tháng/máy có bộ lọc; VND/LAK tách riêng. Chi tiết giữ trạng thái; tổng hợp chỉ bản đã duyệt. Có chi phí chưa phân bổ; năng suất dùng sản lượng/giờ, không đếm số dòng. Lít/giờ chỉ là tỷ số cấp nhiên liệu trong kỳ trên giờ vận hành trong kỳ, không khẳng định lượng tiêu hao động cơ đo được. Lịch bảo dưỡng là trạng thái tại lúc xuất, không giả lập cuối tháng quá khứ.

Báo cáo kế hoạch có cột thực tế ca máy và trang CA MAY SD; màn hình kế hoạch hiển thị số tiền thực tế. Ngân sách là toàn kế hoạch, thực tế theo kỳ được chọn. Không cộng khoản chi tiền thêm một lần vào giá thành. Các bộ báo cáo tổng thể 20 trang vẫn thuộc đợt báo cáo cuối.

Thêm 6 bảng machine_profiles_v1, machine_rates_v1, machine_runs_v1, machine_costs_v1, machine_expenses_v1, machine_audit_v1. Không sửa dữ liệu cũ. Backup cũ có thể thiếu toàn bộ tập máy; tập thiếu một phần khi đã có dữ liệu bị từ chối. Preflight trên DB tạm kiểm tra nguồn/mirror/farm, snapshot giá, tính tiền, phân bổ, khoảng giờ, đồng hồ và công lái máy. Sửa kèm lỗi preflight nhân sự đọc nhầm worker_name_snapshot trong bảng hồ sơ; snapshot tên vẫn được kiểm tra ở bảng lương đúng chỗ.

## 5 mục nghiệm thu điện thoại

1. Mở Máy móc, tạo máy qua danh mục dùng chung. Sửa hồ sơ, chọn đồng hồ giờ; mã vẫn giống trong Công việc. Chọn người lái từ danh mục chung.
2. Khai báo 800.000 VND/ca 480 phút, số lẻ 0, cách làm tròn rõ ràng. Ghi 08:00–17:00, dừng 60 phút, đồng hồ 100→108, phân bổ 480 phút cho kế hoạch VND đang thực hiện. Duyệt → 800.000; báo cáo kế hoạch nhận đúng 800.000. Thử trùng giờ/lùi đồng hồ bị chặn.
3. Ghi 25 lít, giá trị 500.000 VND, tham chiếu chứng từ. Duyệt → báo cáo nhiên liệu có 25 lít/500.000 nhưng chi phí kế hoạch vẫn 800.000. Thử LAK vào kế hoạch VND không duyệt được; nhập bản công người lái cùng giờ phải đánh dấu đã trong giá ca máy.
4. Ghi bảo dưỡng 100.000 VND, đồng hồ 108, mốc lần tới 110 hoặc ngày sắp tới. Duyệt; chi phí kế hoạch vẫn 800.000. Khi có nhật ký tiếp đạt 110, máy báo đến hạn. Thử hủy nguồn có lý do, giữ lịch sử và loại khỏi tổng hợp.
5. Xuất Excel máy 9 trang và báo cáo kế hoạch có CA MAY SD, VND/LAK riêng. Khởi động lại vẫn còn dữ liệu; backup/restore có cả hồ sơ nhân sự và máy. Không cần xóa dữ liệu app.
