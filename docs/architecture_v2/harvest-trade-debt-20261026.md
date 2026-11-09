# Thu hoạch, thành phẩm, mua bán và công nợ — 26/10/2026

Nền: d4c877c688ba183d9be0e872a4f575936cc6621d, đã nghiệm thu máy móc. Source chuẩn bị tiếp nối đúng 20 tệp máy đã giao trên nền 550ea18. Không sửa main, không tự commit/push/merge, không đặt lại dữ liệu app.

## Luồng và danh tính

Mở Tài chính V2 → không gian Thu hoạch, mua bán và công nợ. Phiếu thu/chi độc lập hiện có vẫn mở được bằng nút riêng; thanh toán một chứng từ mua/bán phải từ chính chứng từ để liên kết công nợ, không nhập lại vào phiếu độc lập.

Bổ sung CatalogKind.product và CatalogKind.customer vào danh mục dùng chung: mã TP-000001, KH-000001 do hệ thống cấp, tuần tự riêng từng farm/loại. Vật tư và nhà cung cấp tiếp tục mã VT/NCC, không đổi danh tính. Thành phẩm bắt buộc có đơn vị, được chiếu sang cùng inventory_items_v2, không tạo SKU hoặc kho thứ hai. Luồng đồng bộ danh mục hỗ trợ hai loại mới, giữ các chốt xung đột/offline, đơn vị không được đổi ID sau tạo. Đổi tên đơn vị cục bộ cập nhật nhãn kho; snapshot lô/chứng từ cũ giữ nguyên. Quy tắc remote unit-rename đang có không bị mở rộng.

Tồn thành phẩm theo lô là phần chi tiết của tồn vật lý cùng SKU. Chứng từ thu hoạch/bán và bút toán đảo dùng inventory_movements_v2 và bộ số NHAP/XUAT hiện có, đồng thời cập nhật số dư lô trong một transaction. Giao diện kho chung vẫn hiển thị thành phẩm; nút nhập/xuất thường được thay bằng chỉ dẫn theo luồng lô. Repository cũng chặn đường thường để không làm lệch tồn lô.

## Thu hoạch và giá vốn

Thu hoạch chọn kế hoạch sản xuất đang thực hiện, cùng farm, đúng thửa/vụ đang mở, trong khoảng ngày và cùng tiền tệ. Phiếu có số lượng thực nhận và giá nhập do Admin khai báo, đơn vị là đơn vị SKU, tối đa 6 chữ số lẻ. Không suy diễn khối lượng khô từ độ ẩm, không cộng diện tích mỗi đợt thành diện tích mới, không tự chuyển tấn/kg hay quy đổi tiền.

Một phiếu TH-YYYYMM-001 có thể có nhiều dòng; mỗi dòng tạo lô ...-L001 cùng item_id và plan_id. UI hai dòng, API tối đa 100. Giá trị nhập được giữ chính xác. Giá nhập này là giá do Admin khai báo, chưa tự hấp thụ/khóa toàn bộ vật tư, nhân công, ca máy vào thành phẩm.

Bán hàng chọn khách hàng dùng chung và lô cụ thể, không tự chọn FIFO ngầm. Phiếu BH-YYYYMM-001 có ngày, hạn thu, đơn giá bán và **giá vốn xuất kho riêng do Admin nhập**. Giá vốn không tự lấy giá nhập lô. Duyệt tạo XUAT đúng số lượng, snapshot giá bán/giá vốn/tên/đơn vị, phải thu và phân bổ doanh thu về kế hoạch nguồn. Không cho bán trước ngày thu hoạch, sai tiền tệ lô, vượt tồn hoặc SKU đã ngừng. Nhiều dòng cùng lô được kiểm tra lại khi trừ tồn, lỗi một dòng rollback tất cả.

## Mua vật tư và phải trả

Phiếu MH-YYYYMM-001 chọn nhà cung cấp và vật tư dùng chung. Duyệt ghi NHAP và phải trả trong cùng transaction, chưa tạo CHI. Giá mua không tự trở thành chi phí sản xuất lần thứ hai; chi phí vật tư vào sản xuất vẫn theo phiếu xuất giá Admin đã nghiệm thu.

Phiếu CP-YYYYMM-001 dành khoản phải trả không nhập kho. Người lập phải chọn rõ:

- periodExpense: chi phí kỳ, chưa nằm trong giá thành;
- includedInProduction: thành phần đã nằm trong giá thành/giá ca máy, không trừ thêm vào kết quả kỳ.

Cùng nhà cung cấp/tham chiếu nguồn còn hiệu lực không được lập trùng giữa MH và CP. Nếu chứng từ nguồn có nhiều dòng phân tách, tham chiếu phải phân biệt dòng. Các chứng từ này là chứng từ quản trị nội bộ; chưa có cơ chế hóa đơn thuế, chiết khấu, trả hàng một phần hoặc khóa sổ.

## Tiền tệ và làm tròn

Mỗi chứng từ VND hoặc LAK; lô bán, chứng từ và thanh toán phải cùng tiền tệ. Không có tỷ giá ngầm. Số lượng và đơn giá giữ thập phân chính xác, tối đa 6 chữ số lẻ đầu vào. Giá trị từng dòng tính bằng ExactDecimal.

Tổng chứng từ mua/bán/phải trả được làm tròn **về đồng/kip nguyên**, người dùng phải chọn gần nhất/nửa lên hoặc bỏ phần lẻ. Đây là chính sách của đợt thương mại, không thay chính sách lương 0–6 số lẻ đã khai báo. Sổ THU/CHI V2 hiện có dùng số nguyên, được dùng chung thay vì tạo sổ tiền thứ hai. Tổng làm tròn phân bổ về dòng bằng phần dư lớn nhất với BigInt; tổng dòng đúng tổng chứng từ, không làm tròn từng dòng rồi cộng. Báo cáo xuất cả tiền dòng chính xác và tiền dòng đã phân bổ, thể hiện chênh lệch làm tròn. Giá 0 cần xác nhận, kể cả giá vốn xuất 0. Chứng từ tổng 0 không sinh tiền thu/chi.

## Thanh toán và sửa sai

Bán ghi phải thu, mua/CP ghi phải trả, đều chỉ có hiệu lực khi đã duyệt. Thanh toán từng phần tạo đúng một finance_documents_v2 cùng bộ mã THU/CHI theo tháng đã có. Công nợ còn lại = tổng chứng từ − tổng thanh toán chưa bị đảo; không dựa vào tên đối tác hoặc cộng tất cả phiếu tiền không liên kết. Không cho quá số còn lại, khác tiền tệ, ngày trước nguồn hay ngày tương lai. ID yêu cầu cố định chống gửi trùng; tham chiếu giao dịch đang hiệu lực không được nhập hai lần vào cùng chứng từ bằng hai ID khác nhau.

Đảo thanh toán tạo phiếu ngược chiều, số mới, cùng số tiền/tiền tệ và lý do; giữ nguyên phiếu cũ và liên kết đảo. Công nợ trở lại đúng số phải thu/trả. Không xóa chứng từ tiền.

Phiếu nháp có thể hủy. Phiếu đã ghi sổ phải hết thanh toán còn hiệu lực trước khi hủy; phiếu kho đảo được thêm cùng lịch sử, không xóa phiếu cũ. Thu hoạch chỉ đảo khi toàn bộ số lượng lô còn lại; bán đảo trả đúng lô. Mua vật tư chỉ đảo khi chưa có xuất cùng vật tư từ ngày mua trở đi; quy tắc bảo thủ để không rút nguồn đã dùng. Chỉnh sửa mua sau khi đã tiêu dùng/đối trừ hoặc trả hàng từng phần cần quy trình điều chỉnh riêng ở đợt sau.

Kế hoạch còn thu hoạch nháp chưa được đóng; kế hoạch đã có thu hoạch ghi sổ không được hủy. Hoàn thành kế hoạch sau khi giải quyết nháp vẫn được. Không thay đổi hình học hay danh tính thửa.

## Quyền và phạm vi

TradeService kiểm tra tài khoản hiện tại cùng user/membership/farm với phiên mở màn hình, quyền và allFarm. Không tự cấp thêm quyền hoặc mở scope hẹp. Đọc lại quyền sau các truy vấn.

- finance.view: chứng từ, tồn lô, công nợ và lựa chọn danh mục.
- finance.create: lập nháp; duyệt cần finance.post + finance.approve.
- Duyệt thu hoạch/mua cần inventory.receive + inventory.price; bán cần inventory.issue + inventory.price. Admin là người xác nhận giá xuất.
- finance.correct: hủy/đảo; nếu đã có phiếu kho cần inventory.adjust + inventory.price.
- finance.create + cash.record + finance.view: ghi thanh toán.
- finance.correct + cash.record + finance.view: đảo thanh toán.
- cash.view: xem sổ thu/chi đầy đủ; report.finance + data.export cùng các quyền đọc tiền: xuất bộ báo cáo.

## Báo cáo và giới hạn liên kết

Excel 12 trang: THONG TIN, THU HOACH, BAN HANG, MUA HANG, CHI PHI, TON THANH PHAM, THU CHI, CONG NO, TUOI NO, THANH TOAN, KET QUA KY, THEO KE HOACH. Dòng chi tiết giữ trạng thái; tổng kinh doanh chỉ lấy phiếu đã ghi sổ, mỗi tiền tệ riêng. Doanh thu lấy bán hàng; tiền thu không bị coi là doanh thu lần nữa. Giá vốn lấy giá xuất Admin, mua hàng chưa bị coi là chi phí kỳ; chi tiền không tạo lại chi phí. Thành phần đã trong sản xuất không bị trừ thêm. Kết quả là chỉ tiêu quản trị theo phần đã khai báo, chưa phải lợi nhuận toàn bộ công ty hoặc chi phí hấp thụ tự động.

Tháng lọc phát sinh chứng từ và sổ tiền. Tồn kho và công nợ/tuổi nợ là tại thời điểm xuất; giữ trạng thái hủy hiện tại, chưa cung cấp ảnh chốt cuối tháng quá khứ. THEO KE HOACH phân bổ đúng tổng doanh thu/giá vốn về nguồn lô, không chia lại diện tích theo số lần thu hoạch. Các báo cáo 20 trang/tổng hợp toàn công ty tiếp tục ở đợt cuối.

Sổ nhân sự đã có trả lương riêng và sổ máy có ghi nhận thành phần/tham chiếu. Đợt này không tự nhập lại các ghi nhận đó thành công nợ/phiếu chi, tránh nhân đôi. Nối tự động thanh toán lương, chứng từ nhiên liệu và ngân hàng/đối trừ là phần tích hợp tiếp theo; công nợ đợt này phát sinh từ MH/BH/CP. Chỉ ghi khoản phải trả thực tế một lần, đúng cách phân loại chi phí.

## SQLite và backup

Thêm 7 bảng trade_documents_v1, trade_lots_v1, trade_stock_links_v1, trade_settlements_v1, trade_reversals_v1, trade_sequences_v1, trade_audit_v1. Không xóa dữ liệu, không sao chép lịch sử kho hoặc tạo sổ tiền riêng. SqliteInventoryRepository có entry trong transaction để giao dịch thương mại dùng cùng transaction, giữ nguyên quy tắc giá/số/kho cũ.

Backup cũ có thể thiếu tập bảng trade rỗng. Thiếu một phần khi đã có dữ liệu bị từ chối. TradeIntegrity trên DB tạm kiểm tra danh tính/farm, mã và bộ số, lô/tồn chung, nguồn phiếu kho/phiếu đảo, giá và tiền chính xác, snapshot, công nợ, tiền THU/CHI/đảo. Bỏ toàn bộ bảng trade mà còn phiếu kho/tiền mang ID nguồn trade cũng bị phát hiện. Không sửa DB thật khi preflight.

## 5 mục nghiệm thu điện thoại

1. Tài chính → Danh mục chung: tạo đơn vị kg, thành phẩm và khách hàng, mã tự sinh TP/KH; tạo nhà cung cấp và vật tư nếu chưa có. Thành phẩm hiện cùng SKU trong Kho nhưng nhập/xuất qua lô. Chọn kế hoạch VND đang thực hiện, đúng ngày thu hoạch.
2. Thu hoạch 100 kg, giá nhập 20.000 VND/kg → duyệt: một lô 100 kg, một NHAP, chưa sinh THU/CHI. Bán 40 kg, giá bán 30.000, giá vốn xuất Admin nhập 20.000 → duyệt: còn 60 kg, phải thu 1.200.000, giá vốn 800.000. Thử quá tồn/sai tiền tệ bị chặn.
3. Ghi thu 500.000 tại phiếu bán → một THU, còn phải thu 700.000; thử quá nợ hoặc trùng tham chiếu bị chặn. Đảo lần thu với lý do → thêm CHI 500.000, phải thu trở lại 1.200.000. Không xóa THU cũ.
4. Mua vật tư 10 đơn vị × 20.000 → NHAP + phải trả 200.000; chi 50.000 → còn 150.000. CP 100.000 chọn đã nằm trong giá ca máy không cộng thêm chi phí kỳ. Kiểm tra LAK riêng; tổng tiền dòng lẻ làm tròn một lần theo lựa chọn rõ ràng.
5. Xuất Excel 12 trang: doanh thu 1.200.000, giá vốn 800.000, lãi gộp 400.000 nếu chưa hủy bán; công nợ và sổ tiền khớp lịch sử đảo. Mở lại app còn dữ liệu; backup/restore có lô và công nợ. Kiểm thử hủy/đảo trên bản ghi test riêng và không cần xóa dữ liệu app.
