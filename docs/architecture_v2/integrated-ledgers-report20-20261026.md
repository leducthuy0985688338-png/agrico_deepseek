# Liên kết sổ và báo cáo 20 trang — 26/10/2026

Nền được duyệt: df5f0244bdfd1103b9c39e00c9ba7ca6a9294c7c. Bản này giữ dữ liệu hiện có và không thay đổi hình học thửa. Không tự gửi tiền ngân hàng hoặc đồng bộ sửa bảng Google Sheets.

## Một nguồn cho mỗi giao dịch

- Trả lương mới ghi dòng thanh toán nhân sự và một phiếu CHI trong cùng transaction. Lỗi ở một bên rollback cả hai, kể cả số phiếu. Replay cùng ID không tạo lại phiếu. Số tiền giữ chính xác tối đa 6 chữ số thập phân theo chính sách lương; hệ số lưu SQLite phải nằm trong miền số nguyên an toàn.
- Đảo khoản trả lương cần ngày, lý do và quyền sửa tài chính. Giữ nguyên dòng thanh toán và phiếu CHI gốc; thêm liên kết đảo và phiếu THU hoàn tiền. Công nợ lương tính số đã trả sau đảo. Không sửa tiền công đã duyệt.
- Khoản trả lương lịch sử không tự sinh CHI khi mở app hoặc báo cáo. Admin chọn phiếu CHI trùng số tiền, tiền tệ và ngày; hoặc xác nhận tạo CHI nếu trước đây chưa ghi quỹ. Chứng từ gốc giữ nguyên nội dung. Không được dùng lại phiếu đã thuộc giao dịch mua bán hoặc nguồn khác.
- Chi phí nhiên liệu/bảo trì đã duyệt được phân loại theo nguồn: mua ngoài thì nối một chứng từ CP phải trả; nhiên liệu kho nội bộ thì nối một phiếu xuất kho theo số lít và đơn giá Admin. Không được chọn cả hai cho một nguồn.
- CP máy thuộc loại `includedInProduction`. Giá ca máy đã gồm các thành phần này nên không cộng chúng vào chi phí sản xuất lần nữa. Trả nợ CP qua quy trình thanh toán mua bán hiện có mới tạo CHI. Đơn giá xuất nhiên liệu độc lập với giá trị thành phần máy; chênh lệch không tự quy thành thêm chi phí sản xuất.
- Hoàn nhiên liệu tạo phiếu nhập đối ứng, giữ phiếu xuất cũ. Phải đảo CP hoặc hoàn kho trước khi hủy nguồn chi phí máy đã liên kết. Sửa nghiệp vụ dùng chứng từ đối ứng, không xóa lịch sử.
- VND và LAK luôn tách riêng. CP mua bán làm tròn nguyên đồng/kip theo lựa chọn halfUp/down; số tiền thành phần trước làm tròn vẫn lưu để đối soát.

## Kiến trúc và quyền

UI → IntegrationService → IntegrationStore → SQLite. Báo cáo lấy snapshot trong một transaction, giới hạn theo farm và danh sách bảng nghiệp vụ; không lấy bảng tài khoản/quyền. Quyền phải còn hiệu lực trước và sau đọc; xuất báo cáo đầy đủ yêu cầu quyền xem tài chính, quỹ, danh mục, nhân sự nhạy cảm, lương, máy, thửa, kho và ba nhóm báo cáo, cộng quyền xuất dữ liệu. Không tự cấp thêm quyền.

Thông tin phụ phục vụ báo cáo được lưu riêng với revision, actor và thời điểm. Không ghi đè payload/hình học thửa, danh mục gốc hoặc số tiền chứng từ. Bảo hiểm chỉ thuyết minh trong khoản khấu trừ đã nhập, không tự trừ thêm. Chưa có số đo hoặc chính sách thì để trống; không tự sinh thuế, tỷ giá, đánh giá lao động hay tỷ lệ quy đổi tươi/khô.

## Ánh xạ 20 trang theo bảng mẫu

| Trang | Nguồn và quy tắc |
|---|---|
| DANH MUC | Danh mục dùng chung và vật tư kho; không suy đoán ngưỡng tồn |
| NHAP KHO | Phiếu nhập thực tế trong kỳ, gồm nhập hoàn; giá tại chứng từ |
| XUAT KHO | Phiếu xuất thực tế; phân biệt sản xuất, mua bán và xuất khác |
| THU CHI | Sổ tiền chung, số dư đầu kỳ và số dư chạy riêng VND/LAK |
| TH KHO VA TAI CHINH | Tồn đầu + nhập − xuất; tổng thu/chi ghi một lần cho mỗi tiền tệ |
| LO DAT | Thửa V2 và diện tích hiện có; pH/loại đất/ngày làm đất bổ sung riêng |
| LICH TAC VU | Công phân bổ đã duyệt, công chuẩn theo mức lương của nguồn và OT ghi riêng |
| VAT TU SD | Snapshot vật tư xuất cho kế hoạch; không đọc giá hiện tại để thay giá cũ |
| THU HOACH | Lô thu hoạch, tươi/khô thực đo bổ sung; doanh thu từ bán lô thực tế |
| THONG KE LO DAT | Chi phí vật tư + nhân công + ca máy; thu bán truy về kế hoạch/thửa |
| DANH SACH MAY | Danh mục máy, hồ sơ, giờ vận hành đã duyệt và bảo trì |
| LICH SU BAO TRI | Chứng từ bảo trì; phụ tùng/người thực hiện bổ sung có kiểm tra tổng |
| NHAT KY VAN HANH | Nguồn vận hành, giờ thuần, máy, người, kế hoạch; giờ UTC+7 |
| DANH SACH NV | Danh mục nhân viên, hồ sơ nhạy cảm và các mức lương có hiệu lực |
| PHAN CONG CV | Việc nông trại và phần mở rộng kế hoạch, người, khối lượng/đơn vị |
| CHAM CONG | Giờ đã ghi, giờ nghỉ, OT trong giờ làm, trạng thái và người duyệt |
| BANG LUONG | Bảng lương theo kỳ/tiền tệ, công chuẩn, phụ cấp/thưởng, khấu trừ, net và còn trả |
| NANG SUAT LD | Khối lượng cùng loại việc/cùng đơn vị chia giờ thực tế; không tự xếp loại |
| KE HOACH SAN XUAT | Chỉ tiêu kế hoạch, công/máy thực tế, vật tư thực tế và ngày hoàn tất theo audit |
| DASHBOARD | Doanh thu, giá vốn Admin, lãi gộp, dòng tiền, nợ mua bán/lương và cảnh báo nguồn chưa nối |

Các cột tiền tệ/nguồn được bổ sung để truy vết. Sửa cách diễn đạt những cột mẫu có ý nghĩa sai: thu−chi là dòng tiền; thu bán−chi phí sản xuất phát sinh trong kỳ chưa phải lợi nhuận sau phân bổ giá thành tồn cuối. Ngày công dự kiến đổi sang giờ để khớp dữ liệu kế hoạch, không mặc định mọi mức lương đều dùng cùng số giờ chuẩn.

## Giới hạn kỳ và độ chính xác

- Chọn kỳ YYYY-MM. Các giao dịch kho, tiền, bán hàng và chi phí lấy phát sinh trong kỳ. Bán bị đảo ghi tác động đối ứng tại ngày đảo. Thu hoạch không bán không được coi là doanh thu.
- Công nợ, hồ sơ, danh mục và trạng thái là hiện tại lúc xuất; đây không phải cơ chế đóng sổ lịch sử. Giờ thực hiện của kế hoạch là lũy kế hiện tại, tiền thực tế là trong kỳ và được ghi chú. Hủy công/ca máy không tạo báo cáo tái dựng lịch sử khóa kỳ.
- Năng suất thửa chỉ tính khi các lô thu trong kỳ của thửa cùng sản phẩm và cùng đơn vị kg, có diện tích dương. Không tự đổi tấn sang kg hoặc cộng các sản phẩm khác nhau để tạo năng suất. Các số tươi/khô độc lập, cần nhập số đo.
- Chưa có nguồn cho vốn gốc, tồn tối thiểu, tình trạng máy trước/sau ca hoặc lượng nhiên liệu tiêu thụ đo thực tế thì để trống. Số lít đã cấp cho máy không bị gọi thành số lít đã tiêu thụ. Đây là những trường cần mở rộng nghiệp vụ nhập liệu nếu muốn dùng hàng ngày.
- Excel dùng kết quả tính chính xác của app; các ô tổng kho an toàn còn có SUMIF, tồn đầu và kết quả cache để mở ngay. Không sao chép các công thức lỗi từ mẫu. Không tạo 387 công thức sống nối Google Sheets.
- Số điện thoại, căn cước, mã và tài khoản luôn là ô text; giá trị dài quá 15 chữ số cũng xuất text để tránh Excel đổi số. Tiền và lượng có thể biểu diễn an toàn được xuất ô số. Báo cáo cố định hàng tiêu đề và có bộ lọc.

## Sao lưu và kiểm tra

Năm bảng liên kết/thông tin báo cáo được sao lưu cùng dữ liệu. Bản sao cũ chưa có các bảng này vẫn được chấp nhận như nguồn chưa nối. Bản có dữ liệu liên kết nhưng thiếu một phần nhóm bảng bị từ chối. Preflight kiểm tra khoản lương, phiếu tiền, CP máy, phiếu nhiên liệu, đối ứng và metadata; thay đổi hệ số tiền gây lệch sẽ bị chặn trước khôi phục vào dữ liệu thật.

Cổng kiểm tra trên Windows: analyzer, nhóm kiểm thử liên quan, toàn bộ Flutter test và build APK debug. Không commit/push/cài điện thoại tự động.
