# Điều chỉnh bảng lương đã duyệt — 26/10/2026

Nền đã chốt: `0a8e1fb88cda64b3eb2a985a45d3c3edbb2a18eb` (1.826 Flutter test và 5 mục điện thoại đã đạt). Nhánh sửa: `feature/approved-payroll-adjustments-20261026`.

## Hành vi

Bảng lương, dòng công, mức giá và phân bổ gốc giữ nguyên sau duyệt. Điều chỉnh là chứng từ riêng, mã tự sinh `DCL-YYYYMM-001…`, gắn bảng lương gốc, tiền tệ, ngày hạch toán, tăng/giảm, lý do, người lập và người duyệt. Bản nháp không đổi công nợ hoặc chi phí. Khi đã duyệt, không sửa/hủy chứng từ đó; muốn đảo tác động thì lập một điều chỉnh ngược có lý do và được duyệt lại.

| Loại | Tác động |
|---|---|
| Thu nhập | Số tăng/giảm thay đổi thu nhập và thực lĩnh. Chọn riêng khoản chi phí vào các kế hoạch nguồn; phần chưa phân bổ được chỉ rõ. |
| Tạm ứng/khấu trừ | Số tăng/giảm thay đổi thực lĩnh, không thay đổi chi phí sản xuất. Số dương hoàn lại phần khấu trừ, số âm khấu trừ thêm. |
| Chi bổ sung | Chỉ tạo khi người dùng ghi thanh toán. Không tự chi tiền khi duyệt điều chỉnh. |
| Nhân viên phải hoàn | Phát sinh khi thực lĩnh hiệu lực thấp hơn số đã chi ròng. Hiển thị riêng với lương phải trả, không bù trừ giữa nhân viên hoặc VND/LAK. |
| Thu hoàn | Ghi một phần hoặc toàn bộ khoản phải hoàn, tạo THU và nguồn thu hoàn trong cùng transaction. |
| Đảo thu hoàn | Tạo CHI đối ứng và nguồn đảo riêng, giữ nguyên phiếu THU ban đầu. Không đảo hai lần cùng nguồn. |

Thực lĩnh hiệu lực = thực lĩnh gốc + tổng điều chỉnh đã duyệt. Đã chi ròng = các khoản chi lương còn hiệu lực − thu hoàn ròng. Phải trả = phần dương của (thực lĩnh hiệu lực − đã chi ròng); nhân viên phải hoàn = phần âm đổi dấu.

Các khoản điều chỉnh dùng số thập phân chính xác tối đa sáu chữ số lẻ, không tự đổi tiền, không tự làm tròn hay thay đổi chính sách ngày công 8h/tăng ca/lương khoán. Đây là sửa số tiền, không sửa giờ công hay mức giá gốc.

## Phân bổ chi phí

Mỗi khoản thu nhập được phân bổ rõ ràng theo số tiền có dấu vào một hoặc nhiều kế hoạch đã có trong nguồn bảng lương. Tổng phân bổ không vượt số điều chỉnh, cùng dấu với số điều chỉnh; không được giảm chi phí đã gắn với một kế hoạch xuống dưới 0. Tổng chi phí phân bổ không được vượt thu nhập hiệu lực. Thực lĩnh không âm và không thể vượt thu nhập do khấu trừ bị âm.

Lao động đã nằm trong giá ca máy không tự trở thành chi phí nhân công mới. Kế hoạch chỉ có lao động thuộc giá ca máy không được dùng để cộng thêm chi phí nhân công từ khoản tăng lương đó. Phụ cấp/thưởng đã được gắn kế hoạch trong bảng gốc vẫn giữ nguồn riêng như trước.

Nếu toàn bộ thu nhập gốc đã phân bổ, giảm thu nhập phải kèm giảm chi phí phù hợp; không để lại chi phí lớn hơn thu nhập thực tế. Nếu tăng thu nhập nhưng chưa phân bổ, app không tự gán vào một kế hoạch khác.

Điều chỉnh tài chính có thể tham chiếu kế hoạch nguồn đã hoàn tất hoặc hủy, nhưng không mở lại kế hoạch hoặc thay đổi công việc. Phân bổ gốc không bị ghi lại. Các dòng chi phí điều chỉnh có ID nguồn riêng `payroll-adjustment:<id>:<plan>` và ngày hạch toán riêng.

## Quyền và tính nguyên tử

- Xem: payroll.view; phạm vi worker/bộ phận lấy từ dữ liệu đã lưu.
- Lập/hủy nháp: payroll.manage + payroll.view.
- Duyệt: payroll.approve + payroll.view.
- Thu hoàn/đảo thu hoàn: payroll.approve + payroll.view + cash.record.
- Giữ cơ chế giao phạm vi hiện hành và live session; không cấp thêm quyền hoặc allFarm cho vai trò.

Mỗi đề nghị lưu phiên bản điều chỉnh và thực lĩnh trước điều chỉnh. Approval kiểm tra lại phiên bản, số tiền, nguồn kế hoạch và quyền trong transaction, kể cả hết hạn phiên ngay trước bước ghi cuối. Hai đề nghị cùng phiên bản không thể cùng ghi đè một số dư; đề nghị cũ cần được đối chiếu rồi lập lại. Người lập và người duyệt được lưu riêng; không bắt buộc hai người khác nhau vì Admin vẫn cần thao tác toàn bộ theo quyền được giao.

Tạo đề nghị, mã tự sinh, phân bổ và audit là một giao dịch. Approval, trạng thái và audit là một giao dịch. Thu/đảo thu hoàn, số dư nguồn, số chứng từ tiền và audit cũng là một giao dịch. Lặp lại cùng ID và cùng nội dung không ghi trùng; dùng lại ID với nội dung khác bị chặn.

Ngày hạch toán không được trong tương lai hoặc trước giao dịch nguồn đã có. Khi đã có điều chỉnh, không chèn thanh toán lương lùi trước sổ điều chỉnh hiện hành. Nếu đã dùng một khoản thu hoàn để thanh toán tiếp, phải xử lý khoản chi phụ thuộc trước khi đảo khoản thu hoàn. Tương tự không đảo phiếu chi gốc khi làm số thu hoàn ròng vượt tiền chi còn hiệu lực.

Các khoản chi gốc phải đã được nối và khớp với sổ tiền; lịch sử cũ chưa nối cần đối soát/nối nguồn trước khi thu hoàn. Thu hoàn lưu ảnh chụp số lương hiệu lực, phiên bản điều chỉnh và ID các khoản chi làm căn cứ. Kiểm tra toàn vẹn đối chiếu ảnh chụp, số tiền, thứ tự nguồn, tiền tệ và phiếu THU/CHI. Phiếu thu hoàn không được đồng thời dùng làm thanh toán khác hoặc vốn chủ sở hữu.

## Dữ liệu và tương thích

Bổ sung bốn bảng, không sửa bảng lương gốc:

- personnel_payroll_adjustments_v1
- personnel_payroll_adjustment_costs_v1
- personnel_payroll_adjustment_sequences_v1
- personnel_payroll_refunds_v1

Schema được tạo cùng module Nhân sự lúc khởi động. Bảng lương cũ có tổng điều chỉnh 0, thực lĩnh không đổi. Không reset hoặc xóa dữ liệu test trong đợt này. Không sửa main, GIS, danh tính thửa, kho hay giá ca máy.

Backup mới có đầy đủ bốn bảng. Preflight kiểm tra nguồn, chuỗi duyệt, mã chứng từ, số tiền/phân bổ và nguồn tiền của khoản hoàn; thiếu một phần dữ liệu mới bị chặn. Backup trước đợt này vẫn nhận được khi cả bốn bảng mới đều vắng mặt và dữ liệu gốc hợp lệ. Khi khôi phục bản cũ như vậy, các bảng điều chỉnh/thu hoàn hiện tại được làm rỗng cùng giao dịch thay database, không giữ lại khoản điều chỉnh từ trạng thái trước khôi phục.

## Báo cáo

Báo cáo Nhân sự thêm hai sheet `DIEU CHINH LUONG`, `THU HOAN LUONG`. Bảng lương vẫn có thực lĩnh gốc, đồng thời có tổng điều chỉnh, thực lĩnh hiệu lực, thu hoàn ròng và khoản nhân viên phải hoàn. Tổng hợp giữ riêng khoản phải trả và khoản phải thu.

Báo cáo tích hợp vẫn đúng 20 sheet. Trong BANG LUONG, dòng gốc nằm ở kỳ gốc, dòng điều chỉnh nằm ở tháng hạch toán; không ghi lại dòng gốc hoặc cộng hai lần toàn bộ thực lĩnh hiệu lực. Chi phí sản xuất lấy thêm các nguồn điều chỉnh trong kỳ. Dòng tiền chỉ lấy THU/CHI thực tế. Dashboard có khoản nhân viên phải hoàn riêng. VND và LAK giữ riêng, không quy đổi.

Xuất báo cáo dùng cùng phạm vi xem/báo cáo/data.export đã có, tải dữ liệu mới và kiểm tra dấu phiên trước file writer. Người chỉ xem không có nút lập, duyệt hoặc thu hoàn.

## Kiểm chứng

- 288 test hồi quy Dart/SQLite trên 17 file, gồm 32 test nghiệp vụ điều chỉnh mới, đã qua.
- 5 test IO khôi phục database/media đã qua. Test dùng thư mục được truyền vào, shim path_provider chỉ chặn đường gọi nền tảng không được dùng; không đưa shim vào app.
- Tổng 293 test native qua. Gồm tính bất biến nguồn gốc, số tiền lẻ, đồng thời, cấp quyền/bộ phận, rollback mã/audit/tiền, ca máy trọn gói, kế hoạch đã đóng, khác kỳ/khác tiền tệ, báo cáo và tamper backup.
- Ba widget test mới kiểm tra lập/duyệt có xác nhận, thu hoàn/đảo thu hoàn và tài khoản chỉ xem. Chưa chạy widget/Flutter engine tại đây.
- Phân tích tĩnh các tệp Dart sửa/thêm không có error/warning; còn lint info. git diff --check đạt.
- Full Flutter, Android APK và thử điện thoại là các cổng kiểm tra Windows tiếp theo, chưa tuyên bố đã qua.

## Lấy nhánh sau khi đã xuất bản lên GitHub

```powershell
Set-Location C:\dev\AGRICO\agrico_production_review
git fetch origin feature/approved-payroll-adjustments-20261026
if ($LASTEXITCODE -ne 0) { throw 'Fetch failed.' }
git switch -c feature/approved-payroll-adjustments-20261026 --track origin/feature/approved-payroll-adjustments-20261026
if ($LASTEXITCODE -ne 0) { throw 'Switch failed.' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Verify-Payroll-Adjustments.ps1 -Full -Build
```

Chỉ dùng các lệnh lấy nhánh sau khi việc đưa nhánh lên GitHub đã được xác nhận. Runner giữ analysis_options.yaml và bảy generated files; không stage/commit/push/merge, không cài điện thoại hoặc reset dữ liệu. APK được lưu Downloads.

## Năm mục trên điện thoại

1. Lập bảng lương, duyệt và ghi lại số gốc. Tạo đề nghị tăng/giảm có lý do: bản nháp chưa đổi lương/chi phí/tiền; duyệt xong chỉ thay số hiệu lực, vẫn còn bản gốc và người lập/duyệt. Đề nghị cũ không duyệt lại trên số dư mới.
2. Điều chỉnh thu nhập và khấu trừ riêng. Kiểm tra chi phí vào kế hoạch nguồn, phần chưa phân bổ, ca máy trọn gói, số lẻ và VND/LAK; không tính trùng chi phí. Không cho thực lĩnh âm, khấu trừ âm hoặc chi phí vượt thu nhập.
3. Chi lương rồi giảm xuống dưới số đã chi: app hiện nhân viên cần hoàn. Ghi thu hoàn một phần tạo THU đúng số tiền, không đổi chi phí; đảo thu hoàn tạo CHI đối ứng, không xóa phiếu cũ. Không thu quá số phải hoàn.
4. Tài khoản chỉ xem không có thao tác ghi. Tài khoản theo bộ phận không lập/duyệt/thu hoàn nguồn của bộ phận khác. Thử đăng xuất/đổi tài khoản khi đang mở biểu mẫu: phiên cũ không ghi được.
5. Xuất báo cáo Nhân sự và báo cáo 20 sheet: số gốc, điều chỉnh, phải trả/phải hoàn, chi phí và dòng tiền khớp. Backup mới/khôi phục giữ nguyên chuỗi điều chỉnh và khoản thu hoàn; dữ liệu lệch bị từ chối.
