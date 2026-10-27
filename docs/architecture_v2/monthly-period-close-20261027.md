# Khóa kỳ và chốt số liệu tháng — 2026-10-27

## Điểm xuất phát và phạm vi

- Base đã được người dùng kiểm tra trên Windows/điện thoại: `5eace7a98162bc74d426bd7b08f0dcc493e7bec7` (1.862 full tests, 5 mục điện thoại đạt).
- Nhánh: `feature/monthly-period-close-20261027`. Không sửa main, không reset dữ liệu. Chỉ commit/push nhánh này sau khi người dùng xác nhận.
- Khóa theo farm và tháng `YYYY-MM`, áp dụng xuyên các kho/bộ phận/máy thuộc farm; không phải khóa riêng một kho. Chốt báo cáo tổng hợp 20 sheet; các báo cáo nghiệp vụ từng module tiếp tục thể hiện nguồn nghiệp vụ theo quy tắc riêng của module.

## Quy tắc nghiệp vụ

1. Chỉ được khóa sau khi hết tháng theo UTC+7. Không khóa tháng hiện tại hoặc tương lai.
2. Đối soát thực hiện trong cùng transaction với chốt: kiểm tra kho/sản xuất, nhân sự, máy, mua bán, sổ liên kết và chuỗi lịch sử khóa kỳ. Các kiểm tra toàn vẹn hiện có kiểm tra toàn database; lỗi ở farm khác cũng có thể làm chốt tạm dừng, không công bố dữ liệu của farm đó.
3. Chặn nếu còn nháp chấm công, bảng lương, điều chỉnh lương, ca máy, chi phí máy hoặc mua bán từ tháng cần chốt trở về trước; chi lương chưa nối sổ tiền; chi phí máy đã duyệt chưa phân loại nguồn; hoặc tồn cuối kỳ âm. Không tự duyệt, nối sổ, xóa nháp hay sửa số.
4. Công nợ hợp lệ được chuyển tiếp. Không bắt buộc thu/chi hết mới được khóa. VND và LAK giữ riêng; không bù trừ nợ khác nhân viên hoặc khác tiền tệ.
5. Khóa có hiệu lực đến hết tháng đã chốt, bao gồm ngày trước tháng đó. Không cho luồn ngày bằng cách chuyển ngày hoặc chuyển farm của chứng từ cũ. Nghiệp vụ trả nợ, trả lương, thu hoàn hay điều chỉnh có ngày thuộc kỳ đang mở vẫn được ghi bằng nguồn độc lập. Muốn sửa/void chính chứng từ cũ phải mở lại kỳ.
6. Chỉ mở lại từ kỳ đóng mới nhất; mở lại kỳ sau trước khi mở kỳ trước. Mở lại không xóa bản chốt trước. Khóa lại tạo phiên bản mới.
7. Bắt buộc lý do, người thực hiện, thời điểm. Tài khoản phải có đầy đủ quyền đọc báo cáo tổng hợp và phạm vi toàn farm, cộng `finance.approve` + `audit.review` để khóa; mở lại cần thêm `finance.correct`. Không tự cấp quyền mới. Kiểm lại phiên/quyền ngay trước commit; thay đổi phiên/quyền làm rollback cả trạng thái và lịch sử.
8. Bản xem đối soát có token từ dữ liệu và phiên bản. Dữ liệu thay đổi sau lúc xem thì phải làm mới; không chốt từ màn hình cũ. Transaction/unique revision ngăn duyệt kép.

## Dữ liệu và khóa xuyên module

- `accounting_periods_v1`: trạng thái và phiên bản hiện tại theo farm/tháng.
- `accounting_period_events_v1`: lịch sử close/reopen, lý do, actor, UTC timestamp, bản nguồn JSON, SHA-256 nguồn, checksum sự kiện và liên kết checksum sự kiện trước. Checksum phục vụ kiểm tra toàn vẹn, không phải chữ ký số.
- SQLite triggers bảo vệ thu/chi, nhập/xuất/chuyển kho, chi phí sản xuất, chấm công, đơn giá, bảng lương, chi lương, điều chỉnh/thu hoàn, ca máy, chi phí máy, mua bán/thanh toán và các liên kết sổ.
- Các dòng con dùng ngày/farm nguồn đã lưu trong database. Bảo vệ cả OLD và NEW khi update. Không có cờ bỏ qua khóa trong UI hay request thông thường.
- Lô thu hoạch cũ vẫn được bán ở kỳ mới: chỉ số tồn cache được cập nhật cùng movement giao dịch; giá, nhận diện và nguồn lô cũ không được sửa khi khóa.
- Chi tiết báo cáo gắn nguồn có ngày khóa theo ngày nguồn (vốn, ca máy, bảo dưỡng, thu hoạch, lương). Thông tin nền không có ngày (thửa, máy, nhân viên, ngưỡng tồn) bị khóa khi farm còn kỳ đóng; cần mở các kỳ đang đóng để sửa các thông tin nền đó. Tên/danh mục chính vẫn có thể cập nhật; bản chốt giữ bản tên tại lúc phê duyệt.
- Ngày kho/chi phí lưu UTC được quy sang UTC+7 khi khóa và tính cutoff. Thu/chi giữ ngày chứng từ đã nhập theo quy ước hiện có; không tự dịch ngày chứng từ sang tháng khác.

## Báo cáo chốt

- Chụp các nguồn phát sinh đến cuối kỳ; loại các khoản thanh toán/điều chỉnh/thu hoàn tháng sau khỏi số dư chốt. Phiếu mua bán bị void ở tháng sau được chiếu về trạng thái còn hiệu lực tại cutoff.
- Tính lại tồn cache kho/vật tư/lô từ các movement/chứng từ trong cutoff; không lấy tồn hiện tại làm tồn quá khứ.
- Dữ liệu nền/tên/đơn vị và trạng thái nghiệp vụ không có lịch sử thời điểm đầy đủ được ghi nhận theo thông tin tại lúc chốt. Không suy đoán phiên bản tên hoặc hồ sơ tại một ngày quá khứ.
- Đọc/xuất báo cáo 20 sheet của kỳ đóng dùng nguồn JSON đã chốt, có kỳ/phiên bản/người/thời điểm chốt trên DASHBOARD. Kỳ đang mở giữ báo cáo động hiện có. Thời điểm xuất file có thể thay đổi; nguồn tài chính của bản chốt không thay đổi.
- Các nguồn đầu vào và công thức Excel hiện có giữ nguyên; không tạo sheet thứ 21.

## Sao lưu và khôi phục

- Preflight kiểm tra đủ cặp trạng thái/lịch sử, phiên bản liên tục, action luân phiên, checksum sự kiện/nguồn và farm. Với kỳ còn đóng, đối chiếu nguồn khóa trong backup với bản chốt, phát hiện sửa nguồn dù đã tính lại checksum ngoài của file backup.
- Bản sao lưu trước tính năng khóa kỳ được chấp nhận nếu các kiểm tra khác đạt. Khôi phục bản cũ đưa trạng thái về thời điểm bản sao lưu: xóa trạng thái/lịch sử khóa mới hơn, không giữ khóa mồ côi.
- Activation chỉ gỡ triggers khóa kỳ trong transaction khôi phục hiện có, kiểm tra lại nguồn và lắp lại trước commit. Rollback giữ cả dữ liệu và triggers cũ. Không có thao tác bỏ khóa ngoài transaction này.

## Kiểm chứng

- 22 kiểm thử SQLite/IO mới: khóa/mở lại/lịch sử, nguồn cũ và kỳ mới, cutoff lương, UTC+7, lô thu hoạch, replay/concurrency, đổi quyền khi commit, backup bị sửa, activation giữ khóa và khôi phục bản cũ.
- Bộ native hồi quy gồm 288 kiểm thử đã có + 22 kiểm thử mới + 5 kiểm thử activation trước đó = 315 kiểm thử. Chạy SQLite FFI thật; môi trường kiểm tra dùng shim đường dẫn thư mục chỉ phục vụ harness, không đưa vào mã app.
- 4 kiểm thử Flutter mới trong `period_close_panel_test.dart`: yêu cầu lý do/xác nhận, quyền/chặn đối soát, hủy không ghi và thông báo khóa kỳ Việt/Anh/Lào. Đã thêm vào suite; cần chạy trên Windows cùng toàn bộ Flutter suite.
- Chưa xác nhận APK/full Flutter trên môi trường này. Runner Windows kiểm tra nhánh/base, giữ 8 file cấu hình/tự sinh đã thống nhất, chạy analyzer/focused/full rồi mới build; lưu APK Downloads. Không tự cài máy, commit/push/merge hay xóa dữ liệu.

## Windows sau khi nhánh đã được đưa lên GitHub

```powershell
Set-Location C:\dev\AGRICO\agrico_production_review
git fetch origin feature/monthly-period-close-20261027
if ($LASTEXITCODE -ne 0) { throw 'Fetch failed.' }
git switch --track origin/feature/monthly-period-close-20261027
if ($LASTEXITCODE -ne 0) { throw 'Switch failed.' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Verify-Monthly-Period-Close.ps1 -Full -Build
```

## Năm mục điện thoại

1. Trong Báo cáo và đối soát, chọn một tháng đã kết thúc (ví dụ `2026-09`); nháp/chi lương chưa nối nguồn phải hiện yêu cầu xử lý. Tháng hiện tại không được khóa. Với kỳ đủ điều kiện, nhập lý do và xác nhận khóa.
2. Thử nhập/xuất kho, chấm công, thu/chi hoặc sửa chứng từ trong kỳ đã khóa: bị từ chối và có thông báo kỳ đã khóa; không phát sinh số dư hay phiếu dở dang. Nghiệp vụ tháng đang mở vẫn ghi được.
3. Trả nợ/trả lương hoặc ghi điều chỉnh nguồn độc lập ở tháng mới cho nguồn tháng cũ; báo cáo tháng đã khóa giữ số liệu cũ, tháng mới nhận đúng phát sinh. Lô thu hoạch cũ vẫn bán được trong tháng mới.
4. Tài khoản chỉ xem không có nút khóa/mở lại. Người đủ quyền mở kỳ mới nhất, nhập lý do; sửa và khóa lại có phiên bản mới, lịch sử cũ còn nguyên. Có kỳ sau đóng thì phải mở kỳ sau trước.
5. Xuất 20 sheet của kỳ đã khóa và kiểm tra nhãn phiên bản; thay đổi dữ liệu tháng sau không đổi nguồn chốt. Backup/khôi phục bản mới giữ khóa và lịch sử; không xóa dữ liệu test để thực hiện bài kiểm tra này.
