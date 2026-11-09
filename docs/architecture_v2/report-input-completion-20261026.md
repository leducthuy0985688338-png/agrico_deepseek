# Hoàn thiện nguồn nhập báo cáo — 26/10/2026

Nền: 1222964af7d290b119df0c162aa2de0ff6c215bc, đã qua 1.774 Flutter test, build APK và 5 mục kiểm tra điện thoại. Nhánh giao: feature/report-input-completion-20261026.

## Cách nhập

Tài chính → biểu tượng bảng báo cáo → Thông tin báo cáo:

- **Tồn tối thiểu:** chọn mã/tên vật tư, nhập lượng theo đơn vị đang hiển thị. Chấp nhận tối đa 6 số lẻ và số nguyên lưu kho an toàn. Trống là chưa khai báo; nhập 0 là một ngưỡng được xác nhận. Chỉnh ngưỡng không tạo phiếu kho, không thay tồn hoặc giá. Báo cáo Danh mục và Tổng hợp kho dùng ngưỡng này; cảnh báo so với tồn cuối tháng đang xuất. Ngưỡng là giá trị hiện tại lúc xuất, không phải lịch sử ngưỡng theo tháng.
- **Vốn chủ sở hữu:** chọn một phiếu thu/chi độc lập đã ghi. Phiếu THU chỉ được phân loại góp vốn; phiếu CHI chỉ được phân loại hoàn vốn. Phải ghi lý do. Phân loại áp dụng toàn bộ số tiền phiếu; trường hợp hỗn hợp cần lập các phiếu riêng từ đầu. Có thể bỏ phân loại để sửa sai, không sửa số tiền/ngày/nội dung phiếu gốc. Vốn vay không tự coi là vốn góp.
- **Tình trạng / tiêu thụ ca máy:** chọn máy/ngày ca, nhập tình trạng trước/sau, sự cố/bảo dưỡng và số lít tiêu thụ đo thực tế. Trống không phải số 0; 0 có nghĩa đã xác nhận không tiêu thụ. Lít đã cấp từ kho và lít tiêu thụ trong ca là hai dữ liệu khác nhau; không ép bằng nhau vì có nhiên liệu trong bình từ trước.

Các trường dùng chung cơ chế metadata có farm, entity, revision, actor và thời điểm hiện có. Revision không khớp bị chặn, không ghi đè cập nhật của người khác. Đây là thông tin bổ sung hiện tại, không phải lịch sử phân loại vốn hoặc nhật ký sửa ngưỡng bất biến. Không thay schema/hình học thửa và không reset dữ liệu.

## Luồng tiền và chi phí

Phân loại vốn không tạo phiếu tiền thứ hai. Thu/chi vẫn nằm trong sổ tiền như cũ; cột VỐN GỐC thể hiện góp vốn dương, hoàn vốn âm. Dashboard có vốn góp ròng đã phân loại đầu kỳ, biến động trong kỳ và cuối kỳ, tách VND/LAK. Đây chỉ là phần tiền góp/hoàn vốn đã phân loại, không phải tổng vốn chủ sở hữu kế toán (không tính vốn phi tiền, lợi nhuận giữ lại hoặc đánh giá tài sản).

Phiếu do trả lương, thanh toán mua bán hoặc đối ứng các nghiệp vụ này tạo ra không được phân loại thành vốn. Chi vốn cũng không thể đồng thời được nhận làm phiếu trả lương lịch sử; phải sửa/clear phân loại trước. Trạng thái này được kiểm tra cả khi ghi và trong preflight sao lưu.

Phiếu hoàn vốn được loại khỏi báo cáo chi phí sản xuất cũ; không bị coi là chi phí vì là một khoản CHI. Báo cáo mới vẫn lấy vật tư phân bổ + nhân công + giá ca máy trọn gói. Nhập lượng tiêu thụ không tự xuất kho, tạo công nợ, phiếu chi hoặc cộng thêm chi phí.

## Quyền

Ngoài quyền đọc báo cáo đầy đủ hiện có:

- Sửa ngưỡng tồn: inventory.manage.
- Phân loại vốn: finance.correct.
- Bổ sung thông tin ca máy: machine.verify.

Service kiểm tra quyền hiện hành và farm trước khi gọi repository. Không tự cấp quyền hoặc nới phạm vi báo cáo nhân sự nhạy cảm. Giao diện giữ tiếng Việt/Anh/Lào; tên/mã do người dùng nhập không dịch hoặc chuẩn hóa lại.

## Sao lưu và giới hạn

Dùng bảng metadata đã có; không thêm bảng. Nguồn stock/run tra theo farm_id, phiếu tiền tra theo organization_id. Backup preflight kiểm tra kiểu, nguồn, farm, độ chính xác, hướng thu/chi và quan hệ phiếu tiền. Bản sao từ nền 1222964 không có các loại metadata mới vẫn hợp lệ; bản sao có loại mới cần bản app này hoặc mới hơn để khôi phục.

Chưa có cơ chế đo tự động, kế toán khóa kỳ, thay đổi ngưỡng theo thời gian hoặc tự cập nhật tồn khi nhập tiêu thụ. Các giá trị không có nguồn vẫn để trống, không suy đoán.

## Bộ nghiệp vụ xuyên suốt đã kiểm tra

- Góp vốn 1.000 VND, hoàn vốn 50 → vốn góp ròng 950; không nhân đôi số phiếu.
- Tồn dầu 10 lít; xuất vật tư cho kế hoạch 1 lít giá 10, cấp nhiên liệu máy 2,5 lít → còn 6,5 lít. Ngưỡng 8 → cảnh báo thiếu.
- Nhân công đã duyệt 1 VND; đã trả 0,25 → còn trả 0,75.
- Ca máy trọn gói 80 VND; đo tiêu thụ 1,25 lít. Bảo trì 25,5 làm tròn CP 26, đã trả 10 → còn phải trả 16. Không cộng bảo trì/dầu lần nữa vào ca máy.
- Thu hoạch 10 kg; bán 4 kg giá 10, giá vốn Admin 5 → doanh thu 40, giá vốn 20; thu tiền 20 → phải thu 20, còn lô 6 kg.
- Chi phí sản xuất kế hoạch: 10 vật tư + 1 nhân công + 80 máy = 91; thu tiền 1.020, chi tiền 60,25, dòng tiền 959,75. Vốn, doanh thu và dòng tiền được báo cáo riêng.
- Xuất đủ 20 trang, đối soát các sổ và preflight bản sao đều đạt; sửa hướng phân loại vốn trong bản sao bị chặn.

Các kiểm thử SQLite/báo cáo chạy bằng native Dart. Kiểm thử giao diện mới, toàn bộ Flutter suite và build APK chạy trên Windows qua script giao, không tự commit/push/cài app.
