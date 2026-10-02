# AGRICO — Bàn giao kiến trúc và triển khai Lô–Thửa

Ngày chốt: 30/09/2026, Asia/Bangkok. Chủ dự án đã duyệt kiến trúc và kế hoạch triển khai trong cuộc trao đổi này.
Tài liệu là đặc tả đích và hướng dẫn bàn giao; không khẳng định các chức năng đề xuất đã có trong app.

## 1. Bắt đầu sử dụng

1. Đặt bản sao tài liệu tại `docs/architecture/land-parcel-v2.md` trong repository.
2. Mở repository trong VS Code. Giao prompt ở mục 8 cho công cụ lập trình có quyền đọc workspace.
3. Lượt đầu chỉ làm P00: kiểm tra trạng thái, bảo toàn bản thay đổi đang dở và báo cáo nguồn thực tế. Không triển khai tất cả các gói cùng lúc.
4. Sau P00, lần lượt thực hiện một gói; chạy kiểm thử tại máy. Chỉ cần quay lại trao đổi khi có xung đột kiến trúc, thất bại chưa giải quyết được hoặc đến mốc rà soát quan trọng.
5. Không áp dụng lại các bản vá cũ dựa vào tài liệu này.

Việc dùng công cụ AI khác có thể tiêu tốn hạn mức của chính công cụ đó. Tài liệu không cam kết VS Code hoặc một trợ lý khác có hạn mức riêng hay miễn phí. Git, Dart format và Flutter test/analyze chạy local giúp giảm các lượt trao đổi với trợ lý.

## 2. Repository, checkpoint và bảo toàn công việc

- Repository: `leducthuy0985688338-png/agrico_deepseek`.
- Máy Windows: `C:\dev\AGRICO\agrico_deepseek`.
- Nhánh đang làm: `feature/parcel-work-resource-reconciliation`, tách từ nền tảng `architecture/v2-foundation`.
- Không sửa `main`. Không tự push, merge, rebase, reset, stash, clean hoặc chạy GitHub Actions.
- Đọc `AGENTS.md`; chỉ dẫn mới của chủ dự án trong tài liệu này thay thế những hợp đồng cũ mâu thuẫn về nghiệp vụ Lô–Thửa.
- `analysis_options.yaml` có thay đổi cục bộ của chủ dự án: không sửa, restore hoặc stage tệp này.
- Không dùng checkout cũ ở môi trường khác làm nguồn thay thế workspace Windows.
- Checkpoint ổn định gần nhất do người dùng xác nhận: `b209244` — `feat: create project-numbered production blocks from v2 UI`; toàn bộ **870/870** kiểm thử đạt.
- `f275f69` trước đó khởi tạo và kiểm tra sao lưu bộ đếm mã production; toàn bộ 866 kiểm thử đạt.
- Các hash ngắn là mốc tham chiếu; P00 phải lấy hash đầy đủ và kiểm tra ancestry thực tế.

### Trạng thái chưa commit cần đối chiếu

Bản vá `AGRICO-production-field-plots-ui.patch` đã được áp dụng và format trên Windows nhưng chưa commit. Lần kiểm thử được báo có hai lỗi:

1. Thiếu import `parcel_subdivision_plan.dart` trong `land_parcel_spatial_sync_workflow_test.dart`. Người dùng đã được hướng dẫn thêm import; phải kiểm tra tệp hiện tại để xác nhận.
2. Test `production drawing keeps undo helpers and fixes the parent without village` không hoàn tất preview. Rà soát đã phát hiện `_ParcelRepository` trong test chưa triển khai `listByFarm`, trong khi preview production gọi nó để kiểm tra Thửa hiện có. Đây là nguyên nhân cần sửa và kiểm chứng bằng chạy test, không bỏ assertion hoặc nới kiểm tra hình học.

Snapshot nguồn gần nhất đã cung cấp: `AGRICO-land-block-cleanup-current.zip`. ZIP chứa composition và thư mục farm nguồn/test; không phải toàn bộ repository. Sau thời điểm snapshot, người dùng tiếp tục duyệt nhiều thay đổi kiến trúc nên nguồn đó vẫn chưa đạt đặc tả đích.

Một bản nháp sửa bỏ cây/trạng thái ở Lô đã được tạo trong scratch của trợ lý, **chưa giao để áp dụng, chưa kiểm thử Flutter và chưa commit**. Không coi bản nháp đó là thay đổi hiện có trên Windows.

Không có kết quả full suite thành công cho working tree đang dở. Không diễn giải 870 test của checkpoint thành kết quả hiện tại.

### Những gì đã có và những gì chưa có

| Nội dung | Nguồn đã kiểm tra |
|---|---|
| Tạo Lô theo mã dự án, cấp số giao dịch | Đã commit ở b209244 |
| Guard vị trí Thửa trong một Polygon cha | Đã có nền tảng; chưa đáp ứng MultiPolygon và Thửa độc lập |
| Lưu nhiều Thửa atomically | Bản vá đang dở, cần đối chiếu và kiểm thử |
| Lô nhiều vùng rời nhau | Chưa hoàn thành |
| Thửa độc lập, mã cấp theo dự án | Kiến trúc mới; mẫu mã cũ phụ thuộc Lô phải thay |
| Bỏ cây và trạng thái đất ở Lô | Kiến trúc mới; chưa áp dụng đầy đủ |
| Quan hệ nhiều Bản, lịch sử liên kết Lô–Thửa | Chưa có lưu trữ chính thức |
| Đối soát khi thay đổi Lô và xuất lịch sử | Chưa hoàn thành |

## 3. Kiến trúc nghiệp vụ đã được duyệt

### 3.1. Dự án, Lô và Thửa

- Dự án AGRICO Nong quản lý nhiều Lô và nhiều Thửa.
- Lô là đơn vị không gian quản lý, có thể gồm **nhiều vùng đất rời nhau**.
- Mỗi Lô có một ID nghiệp vụ và một mã ổn định, dù có nhiều vùng.
- Thửa là đơn vị sản xuất độc lập: được tạo trước Lô, không thuộc Lô hoặc thuộc một Lô đang sử dụng.
- Liên kết Lô cha là tùy chọn, được xác lập/chỉnh sửa bằng nghiệp vụ có lịch sử. Không dùng việc chưa có Lô để ngăn tạo Thửa.
- Không tự chuyển Thửa sang Lô khác chỉ vì giao cắt hình học.
- Hạ tầng có thể phục vụ nhiều Lô/Thửa. Không ép đường, giếng, kênh thành Thửa canh tác hoặc thêm một cấp đất thừa.

### 3.2. Trách nhiệm dữ liệu

| Đối tượng | Nguồn dữ liệu thuộc về đối tượng |
|---|---|
| Lô | Mã/tên, dự án, các vùng ranh giới, diện tích, chu vi, tọa độ, các Bản liên quan, ghi chú/tài liệu và vòng đời sử dụng |
| Thửa | Mã/tên, dự án, Lô cha tùy chọn, ranh giới, hiện trạng đất, mùa vụ, cây trồng, công việc, nhật ký, sản lượng và chi phí |
| Mùa vụ | Chu kỳ sản xuất của Thửa, nhiều dòng cây trồng, giống, ngày trồng, hình thức trồng và thu hoạch |
| Công việc | Kế hoạch cần thực hiện |
| Nhật ký | Việc thực tế đã làm; có thể liên kết công việc |
| Hồ sơ GPMB/khảo sát | Nguồn gốc đất, hộ và cây có sẵn khi khảo sát; tách khỏi cây sản xuất |

Lô không nhập/lưu trạng thái đất, mức khai hoang, sẵn sàng hoặc cây trồng chung. Nếu cần xem, tính tổng hợp từ Thửa và nhật ký. Hoạt động khai hoang trên Lô trước khi chia Thửa vẫn có thể ghi nhật ký; không biến nhật ký đó thành cây/trạng thái nhập tay ở Lô.

### 3.3. Mã chính thức mới

- Dự án: `AGR-NONG`.
- Lô: `AGR-NONG-L001`.
- Thửa: **`AGR-NONG-T001`**, cấp theo dự án, không chứa mã Lô cha.
- Số có tối thiểu ba chữ số và có thể tăng vượt 999; không giới hạn nghiệp vụ bằng độ dài hiển thị.
- Không phụ thuộc Bản, Hộ, cây trồng hoặc mùa vụ.
- Business ID, mã hiển thị, SpatialFeature ID và Revision ID là các danh tính khác nhau.
- Liên kết/chuyển Lô không đổi ID hoặc mã Thửa.
- Mã cũ `AGR-NONG-L001-T001` là nền tảng đã triển khai trước khi duyệt Thửa độc lập; phải có chính sách xử lý bản ghi thử hiện có, không silently đổi rồi mất tham chiếu.
- Cấp mã và lưu dữ liệu trong giao dịch; không commit bộ đếm riêng trước khi lưu đối tượng.
- Bộ đếm phải được sao lưu/khôi phục cùng dữ liệu. Chính sách cấp số khi nhiều thiết bị offline là phần cần thiết kế riêng trước khi hỗ trợ đồng bộ đa thiết bị.

### 3.4. Hình học và nguồn nhập

- Chuẩn lưu WGS84 / EPSG:4326. Polygon có thể có lỗ; Lô dùng hình học nhiều Polygon.
- Kết hợp được các vùng từ vẽ trên map, GPS, Google Earth, KML/KMZ và nguồn khác có bộ chuyển đổi xác định.
- Giữ nguồn/provenance của từng vùng, file nguồn khi có và thông tin độ tin cậy/độ chính xác phù hợp.
- Khi nguồn có hệ tọa độ khác, cần thông tin CRS và bước chuyển đổi được kiểm chứng; không đoán CRS.
- Diện tích và chu vi tính từ ranh giới. Không thêm diện tích pháp lý riêng.
- Diện tích Lô là tổng diện tích các vùng hợp lệ, trừ lỗ. Quy tắc chu vi nhiều vùng phải được định nghĩa và kiểm thử (đường biên ngoài cùng các biên lỗ), không cộng đường biên nội bộ bị trùng một cách tùy tiện.
- Tọa độ tâm chỉ là điểm đại diện tính toán; với nhiều vùng rời nhau nó có thể nằm ngoài các vùng. Không dùng tâm để quyết định Thửa thuộc Lô hoặc Lô thuộc Bản.
- Các vùng của cùng Lô không chồng nội thất; các Lô đang sử dụng trong cùng dự án không chồng nội thất. Cho phép chung biên/điểm.
- Thửa đã được xác nhận thuộc Lô phải nằm trong hợp vùng của Lô, không chồng nội thất Thửa khác theo phạm vi kiểm tra đã chốt bên dưới.
- Không yêu cầu tổng diện tích Thửa bằng diện tích Lô. Phần còn lại có thể là hạ tầng, đất chưa sản xuất hoặc chưa phân loại; không tự gắn nhãn toàn bộ là hạ tầng.
- Giữ các công cụ vẽ, khép vùng, undo, vẽ lại, chia/trace hiện có. Preview và save phải dùng cùng quy tắc; save kiểm tra lại dữ liệu trong transaction.

### 3.5. Các Bản

Một Lô có nhiều Bản liên quan, một Bản có nhiều Lô. Lưu liên kết bằng ID danh mục; tên có Unicode Việt–Lào–Anh. Không dùng một chuỗi tên làm quan hệ chuẩn lâu dài.

Khi chưa có ranh giới Bản, cho chọn nhiều Bản và ghi nguồn xác nhận thủ công. Khi có bản đồ Bản, có thể đề xuất quan hệ/diện tích bằng giao cắt để người dùng đối soát. Không suy ra toàn bộ quan hệ từ centroid.

### 3.6. Thay đổi Lô và đối soát Thửa

Thêm vùng, mở rộng hoặc sửa Lô là thao tác tạo phiên bản mới. Kiểm tra xung đột với Lô khác trước khi cho lưu. So sánh ranh giới trước/sau với các Thửa liên quan hoặc bị vùng thay đổi tác động.

| Tình huống | Xử lý |
|---|---|
| Thửa độc lập nằm trọn trong Lô mới | Đề nghị xác nhận liên kết, không coi là lỗi hình học |
| Thửa giao một phần với Lô | Cảnh báo và yêu cầu đối soát ranh giới/quan hệ |
| Thửa chỉ chung biên | Không coi là chồng diện tích |
| Thửa đã thuộc Lô nay nằm ngoài một phần/toàn bộ | Đánh dấu cần chỉnh sửa |
| Thửa thuộc Lô khác bị tác động | Cảnh báo xung đột, không tự chuyển |
| Không bị tác động | Giữ nguyên |

Trước khi lưu, hiển thị tác động. Khi xác nhận, lưu phiên bản Lô mới và các vấn đề đối soát trong cùng giao dịch; giữ nguyên hình học Thửa. Cho phép trạng thái hiện tại tạm thời cần đối soát, thay vì âm thầm sửa Thửa hoặc mất thông tin.

Thửa cần đối soát vẫn xem được dữ liệu/lịch sử; không đưa vào tổng diện tích Thửa hợp lệ mà không báo rõ. Quy tắc khóa thao tác sản xuất trong trạng thái này chưa được chủ dự án quyết định; không tự khóa mọi công việc hoặc tự xóa mùa vụ.

Chỉnh sửa Thửa tạo phiên bản mới và liên kết việc sửa với vấn đề/phiên bản Lô gây ra nó. Không tự cắt, gộp, đổi mã hoặc xóa Thửa. Lịch sử công việc, mùa vụ, chi phí đã ghi không bị chuyển/mất theo ranh giới mới.

### 3.7. Nhiều cây đồng thời

Một Thửa có nhiều loại cây đồng thời. Dùng nhiều dòng cây trong mùa vụ, giữ lịch sử; không overwrite loại cây duy nhất trên Thửa và không dùng cả CropRecord khảo sát lẫn mùa vụ làm hai nguồn sản xuất.

Diện tích trồng xen không cộng cơ học theo từng cây. Diện tích canh tác duy nhất và diện tích áp dụng cho từng dòng cây là hai chỉ tiêu khác nhau. Cách biểu diễn hình thức trồng/diện tích chi tiết phải chốt trong P06.

### 3.8. Báo cáo và xuất lưu trữ

- Diện tích quản lý lấy từ Lô; diện tích canh tác lấy từ Thửa/mùa vụ phù hợp. Không cộng cha và con.
- Hiển thị riêng Thửa độc lập, đã liên kết, cần đối soát và phần đất chưa bố trí sản xuất.
- Chi phí ghi nhận một lần; chi phí chung phân bổ có tiêu thức và lịch sử, không cộng lặp ở Lô và từng Thửa.
- Cho xuất phiên bản được chọn sang KML/KMZ hoặc GeoJSON, kèm metadata lịch sử trong hồ sơ lưu trữ.
- File bản đồ phục vụ xem/trao đổi, không thay thế bản sao lưu đủ để khôi phục database.
- Hồ sơ lịch sử có ID/mã, hình học trước/sau, người sửa, thời gian, lý do, liên kết Lô–Thửa và các vấn đề đối soát.

## 4. Kiến trúc kỹ thuật và lưu trữ

Luồng đích: UI → Application → Domain → Repository interface → SQLite adapter → SQLite. Offline-first; giao dịch atomically cho mã, đất, không gian, liên kết, revision và dữ liệu phụ trong phạm vi thao tác.

Hiện có một bảng đất chung `land_parcels`; loại Lô/Thửa và parent đang nằm trong `legacyMetadata`, nhiều dữ liệu nằm trong `payload_json`. Đề xuất đích vẫn một hệ lưu trữ đất, nhưng project, loại và parent là quan hệ/cột có kiểu rõ ràng. Không xây thêm hai kho đất độc lập rồi sao chép qua lại.

Các nhóm đang có: `land_parcel_boundary_versions`, `land_parcel_spatial_links`, Spatial features/revisions; `land_use_profiles`, `land_parcel_crops`, surveys/attachments; `parcel_stage_snapshots`, `parcel_derivations`; `parcel_work_events`/assignments; `farm_tasks_v2`; bộ đếm production v4.

Phải bổ sung quan hệ nhiều Bản, lịch sử liên kết Thửa–Lô và vấn đề đối soát có phiên bản. Thửa không có Lô là trạng thái hợp lệ, không là FK bị thiếu. Kiểm tra cùng dự án và phạm vi quản lý tại Application/Repository và ràng buộc SQLite phù hợp.

Hình học đang có các bản chiếu ở LandParcel và Spatial Core. Chưa tự quyết xóa một phía; trước khi refactor phải xác định đường ghi chuẩn và cập nhật tất cả bản chiếu trong transaction. Spatial ID ổn định, revisions append-only; metadata-only không tạo revision hình học. Không hạ các guard identity và đồng nhất ranh giới đã có.

`farm_id` phạm vi quyền dữ liệu khác với project identity và organization identity dùng tài chính. Composition local hiện có membership với toàn bộ quyền; không tuyên bố đã có phân quyền tài khoản hoàn chỉnh.

Các nền tảng CultivationArea/PreCompensationParcel/ParcelLineage phục vụ phạm vi đất và GPMB cần được phân định; không thêm cấp đất thừa vào cây Dự án–Lô. Công việc là kế hoạch, nhật ký là thực hiện; kho và tài chính liên kết bằng ID, không sao chép tên/mã làm khóa.

## 5. Những chi tiết chưa được quyết định — không tự suy diễn

1. Thửa có cần nhiều vùng rời nhau không? Chỉ Lô đã được duyệt rõ MultiPolygon. Giữ API hình học có thể mở rộng nhưng không tự ép Thửa sang MultiPolygon.
2. Phạm vi cấm chồng giữa các Thửa độc lập/khác Lô trong cùng dự án: đã chốt không chồng Thửa trong cùng Lô; cần xác nhận quy tắc toàn dự án trước khi mở rộng thành điều kiện chặn.
3. Khi Thửa chỉ một phần nằm trong Lô: ưu tiên chỉnh ranh giới, tách Thửa hay duy trì trạng thái đối soát? Không tự tách hoặc tự chuyển.
4. Khi cần đối soát: cho phép/khóa những thao tác sản xuất nào? Chưa chốt.
5. Chuyển/tách/gộp Thửa và thời điểm hiệu lực; xử lý mùa vụ/chi phí đang chạy.
6. Mô hình diện tích trồng xen và cách xác định diện tích canh tác duy nhất khi chưa vẽ các vùng cây.
7. CRS và danh sách định dạng ngoài GPS/KML/KMZ cần hỗ trợ thực tế; xuất history bundle định dạng cụ thể.
8. Nguồn danh mục và bản đồ 13 Bản; độ chính xác và ngưỡng topology.
9. Chính sách thay mã Thửa cũ trên bản ghi thử và lưu alias/lịch sử mã; tuyệt đối không đổi ID liên kết.

Chỉ hỏi khi một chi tiết thực sự chặn gói đang làm. Có thể hoàn thành nền tảng và các test không phụ thuộc quyết định đó trước.

## 6. Gói triển khai và điểm nghiệm thu

| Gói | Phạm vi | Bằng chứng hoàn thành |
|---|---|---|
| P00 | Kiểm tra HEAD/branch/remote, diff, AGENTS; bảo toàn thay đổi đang dở; phân loại giữ/thay/dọn | Danh sách tệp và xung đột với hợp đồng mới; snapshot ngoài repo; không reset/stash/restore hàng loạt |
| P01 | Domain hình học Lô nhiều vùng, topology, metrics và phân loại tác động Thửa trước/sau | Test rời vùng, lỗ, chung cạnh/điểm, overlap, trạng thái giao cắt; không UI/schema |
| P02 | Identity Thửa theo dự án; project/kind/parent tùy chọn, nguồn vùng và quan hệ nhiều Bản; migration riêng | Nâng cấp idempotent, giữ IDs/Unicode/quan hệ; thử lỗi rollback và dữ liệu cũ một Polygon |
| P03 | Transaction spatial nhiều vùng, revisions, đối soát và backup/restore | Không partial write; old/new geometry khớp; khôi phục rồi cấp mã tiếp |
| P04 | UI tạo/xem/sửa Lô nhiều vùng; bỏ cây/soil ở Lô; xem tác động trước lưu | Widget tests + thử thiết bị vẽ/GPS/KML/KMZ; nguồn từng vùng và Bản hiển thị đúng |
| P05 | UI Thửa độc lập/thuộc Lô; vẽ helpers, liên kết, sửa và xử lý vấn đề | Test không cần parent, liên kết không đổi mã, preview/save đồng nhất, ghi lịch sử |
| P06 | Hiện trạng chỉ ở Thửa; mùa vụ nhiều cây, tách khảo sát và sản xuất | Không nguồn cây trùng; lịch sử mùa vụ, trồng xen và sửa dữ liệu đúng |
| P07 | Danh sách và dashboard; kiểm tra liên kết tasks/work/inventory/finance; xuất lịch sử | Không double count; phân biệt independent/review; hồ sơ xuất đủ và mở/đọc lại được |
| P08 | Dọn UI/provider/demo/luồng đã thay, test lỗi thời; nghiệm thu | Full suite, analyzer, backup/restore và smoke test thiết bị; không drop bảng trước đối soát/backup |

Không gộp tất cả các gói thành một thay đổi lớn. Domain, migration và UI là các thay đổi riêng. Một gói có thể chia thành các commit có ý nghĩa khi đã kiểm thử; không tạo hàng loạt micro-patch chỉ để tăng số checkpoint. Không đặt số test dự kiến làm mục tiêu; test phải chứng minh hợp đồng.

**Gói đầu tiên được giao:** P00, rồi P01. Các thay đổi UI đang dở không được coi là cơ sở chuẩn cho kiến trúc mới.

## 7. Kiểm thử và báo cáo tiết kiệm lượt trao đổi

### Ma trận kiểm thử tối thiểu

- Domain: hai vùng rời nhau, lỗ, trùng biên/điểm, overlap, invalid/self-intersection, metrics và precision; parent union và before/after impact.
- SQLite: một Polygon cũ đọc được; migrate hai lần; giữ IDs, quan hệ và chữ Lào; unique code/scope; rollback khi thành viên cuối batch lỗi.
- Spatial: land parcel/link/feature/revision khớp; immutable feature ID; revision mới khi đổi hình học; metadata-only không thêm revision; không bypass shared transaction.
- Đối soát: independent contained, partial, boundary-only, linked becomes outside, other-block affected; issue gắn old/new version; retry/idempotency và xử lý lỗi atomically.
- Block/plot data: block không tạo soil/crop; plot vẫn tạo được; đổi parent không đổi mã; cây khảo sát không được cộng như cây sản xuất.
- Backup: trước schema mới, schema mới, thiếu parent/village/issue reference, bộ đếm bị hạ, lịch sử geometry lỗi; restore thực rồi đọc dữ liệu và cấp số tiếp.
- UI/device: undo/redraw/close/trace, hủy không ghi, batch thất bại không partial; nhiều nguồn, many regions; nhiều Bản; xem và xuất phiên bản cũ.
- Tổng hợp: không cộng Lô+Thửa; không cộng trùng cây xen; independent và cần đối soát hiển thị riêng.

### PowerShell kiểm tra ban đầu (chỉ đọc)

```powershell
cd C:\dev\AGRICO\agrico_deepseek
$branchName = git branch --show-current
if ($branchName -ne 'feature/parcel-work-resource-reconciliation') {
    throw "Nhánh hiện tại khác nhánh bàn giao: $branchName; kiểm tra trước khi sửa"
}
git status --short --branch
git rev-parse HEAD
git remote -v
git log -5 --oneline
git diff --stat
git diff --cached --stat
```

Muốn kiểm tra remote cập nhật: P00 dùng `git ls-remote` cho ref liên quan, không tự pull/merge. Nếu offline, báo remote chưa xác minh; không giả vờ local ref là trạng thái server. Có thay đổi ngoài phạm vi thì bảo toàn và báo, không tự xóa.

### Lưu bản thay đổi đang dở ngoài repository

```powershell
cd C:\dev\AGRICO\agrico_deepseek
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snapshotPath = Join-Path $HOME "Downloads\AGRICO-working-$stamp.zip"
$paths = @('lib', 'test', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'AGENTS.md')
$existingPaths = $paths | Where-Object { Test-Path $_ }
Compress-Archive -Path $existingPaths -DestinationPath $snapshotPath
if (-not (Test-Path $snapshotPath)) { throw 'Chưa tạo được snapshot' }
Write-Host "Đã lưu bản nguồn hiện tại: $snapshotPath"
```

Đây là snapshot nguồn để bảo toàn local changes, **không phải backup database ứng dụng**. Không tự gửi lên dịch vụ ngoài; kiểm tra tệp nhạy cảm trước khi chia sẻ. `analysis_options.yaml` được chép để bảo toàn, không bị sửa hoặc stage.

### Kiểm thử mỗi gói

Công cụ triển khai cung cấp danh sách tệp Dart sửa và test phù hợp. Format đúng các tệp đó, rồi:

```powershell
# Thay bằng các test thực sự có trong gói; dừng ngay khi thất bại.
flutter test test/features/farm/domain
if ($LASTEXITCODE -ne 0) { throw 'Kiểm thử mục tiêu chưa đạt' }
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'Diff chưa sạch' }
```

Không chạy broad test lặp lại nếu chưa có thay đổi hay lỗi mới. Khi chuẩn bị checkpoint có thay đổi code:

```powershell
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Full suite chưa đạt; chưa checkpoint' }
flutter analyze --no-fatal-infos --no-fatal-warnings
if ($LASTEXITCODE -ne 0) { throw 'Analyzer chưa đạt' }
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'Diff chưa sạch' }
git status --short --branch
```

Không dùng `git add .`. Stage chỉ các tệp đã rà soát; loại `analysis_options.yaml` và tệp platform tự sinh ngoài phạm vi. Chỉ restore `macos/Flutter/GeneratedPluginRegistrant.swift` sau khi xác nhận thay đổi chỉ do công cụ sinh và không có sửa chủ động của người dùng. Commit/push theo quyền đã được người dùng cấp trong phiên làm việc, không suy diễn từ prompt này.

Analyzer có infos/warnings tồn tại trước; số lượng từng log có thể khác và có log lặp đôi. So sánh diagnostic/path thực tế, không chỉ tổng số. Không thêm error hoặc warning ngoài phạm vi.

### Báo cáo ngắn khi đạt

```text
AGRICO | Gói Pxx
Branch / HEAD trước và sau:
Thay đổi nghiệp vụ:
Tệp sửa:
Targeted: ... đạt / ... lỗi
Full suite: ... (hoặc chưa chạy)
Analyzer: ... error / ... warning / ... info; diagnostic mới:
Diff check:
Đã commit hay chưa:
Rủi ro / việc còn lại:
```

Khi lỗi, gửi test name, exception đầu tiên, expected/actual và nguồn liên quan. Không gửi toàn bộ analyzer nếu vấn đề chỉ là một import/test. Một lần báo cáo gom các kết quả của gói. Các mốc nên nhờ rà soát: P01 Domain, P02 migration, P03 spatial/backup, rồi P08 nghiệm thu.

## 8. Prompt dùng trong VS Code / công cụ lập trình

Sao chép đoạn dưới, đính kèm hoặc chỉ rõ tài liệu này:

```text
Tiếp tục AGRICO theo docs/architecture/land-parcel-v2.md (bản bàn giao 30/09/2026).
Repo leducthuy0985688338-png/agrico_deepseek, local C:\dev\AGRICO\agrico_deepseek.
Nhánh dự kiến feature/parcel-work-resource-reconciliation; nền architecture/v2-foundation.
Không sửa main; giữ nguyên local analysis_options.yaml. Không reset/rebase/stash/clean,
không tự push/merge/chạy Actions. Đọc AGENTS.md và nguồn thực tế.

Checkpoint ổn định b209244 có 870 test đạt. Working tree có bản vá Thửa chưa commit
và test từng thất bại; không giả định nó sạch hoặc đáp ứng kiến trúc mới.
Bước đầu chỉ thực hiện P00: kiểm tra HEAD/branch/remote, diff staged/unstaged,
đối chiếu snapshot và bảo toàn các thay đổi trước khi sửa. Báo rõ lệch checkpoint.
Không tự bỏ diff của người dùng. Sau P00, triển khai P01 Domain trong một phạm vi
có test; không đồng thời sửa schema/UI.

Hợp đồng mới:
- Lô MultiPolygon, tích hợp nhiều nguồn WGS84, không chồng nội thất Lô khác cùng
  dự án; chung biên được phép. Lô không lưu cây/trạng thái đất.
- Thửa có thể độc lập và tạo trước Lô; parent tùy chọn. Mã AGR-NONG-T001 theo dự án,
  mã Lô AGR-NONG-L001; ID/mã Thửa không đổi khi liên kết Lô.
- Thửa nằm trong Lô khi quan hệ đã xác nhận hợp lệ; phần đất hạ tầng/unallocated
  không cần phủ bởi Thửa. Không ép tổng diện tích Thửa bằng Lô.
- Khi sửa Lô, preview tác động; xác nhận lưu tạo phiên bản Lô và vấn đề đối soát
  atomically, không tự sửa/cắt/chuyển/xóa Thửa. Giữ và xuất lịch sử của cả hai.
- Một Thửa nhiều cây đồng thời; mùa vụ là nguồn sản xuất, không double count cây xen.
- UI→Application→Domain→Repository→SQLite, offline-first, Việt–Lào–Anh.
- Business/spatial/revision identity riêng; feature ID ổn định, revisions append-only.
  Không nới các spatial identity/transaction guards để làm test qua.

Phân biệt phần đã duyệt và chi tiết chưa quyết định ở mục 5. Chỉ hỏi nếu chi tiết
đó chặn gói hiện tại; tiếp tục phần độc lập. Các test mâu thuẫn hợp đồng cũ phải
được thay bằng test hợp đồng mới, không xóa coverage có ý nghĩa để qua test.
Kiểm tra cả tạo và sửa, boundary-only/partial/inside/outside, history và rollback.
Nếu không có Flutter, không tuyên bố tests đạt: cung cấp lệnh PowerShell cụ thể.
Kết thúc gói báo nghiệp vụ thay đổi, tệp sửa, test/analyzer/diff, giới hạn và gói kế.
```

## 9. Nguồn và giới hạn của bộ bàn giao

Đặc tả được chốt từ các quyết định của chủ dự án trong phiên 30/09/2026. Hiện trạng dựa trên log commit/test người dùng gửi và snapshot nguồn `AGRICO-production-parcel-ui-current.zip`, `AGRICO-field-plot-ui-current.zip`, `AGRICO-land-block-cleanup-current.zip`, cùng các snapshot backup trước đó.

Các liên kết kho/tài chính/mùa vụ được mô tả theo những nguồn đã kiểm tra trước; không phải xác nhận chúng đã được tích hợp đầy đủ vào hợp đồng mới. Tài liệu không thay thế kiểm tra repository/remote hiện tại và không phải kết quả chạy Flutter trong môi trường tạo tài liệu.


## Checkpoint P02B — 2026-10-01

- Production form supports land blocks and standalone field plots.
- Standalone plots use project-scoped codes such as AGR-NONG-T001.
- Parented plots currently retain codes such as AGR-NONG-L001-T001.
  Unifying all plot codes remains pending.
- Production plot batch creation persists numbering and spatial data atomically.
- All 1013 tests passed; the debug APK built successfully.
- Device checks confirmed automatic numbering and record persistence after restart.
- Old test data was cleared from the test device.
- Full analyzer still reports 5 warnings and 162 infos; these remain unresolved.
- This checkpoint is an intermediate implementation of the target architecture.

## P02C — unified field plot numbering

New standalone and parented plots share one farm/project T sequence.
Parent relations remain in parentLandBlockId; they are absent from the code.
The existing standalone counter table name is retained for database continuity.
Existing codes are not rewritten. Legacy nested-code backup validation remains
for reading older snapshots. P02C validation: all 1016 tests passed; debug APK build passed. Device drawing and saving passed. Production drawing uses a zoomable Flutter schematic of the stored boundary; satellite imagery is unavailable in this mode.

## P02D — editable plot–block relations

The plot detail provides an editor for attaching, transferring and detaching
field plots. Blocks offered belong to the same identified project and farm.
The application requires farm-wide view/edit access and validates active state,
plot and target snapshots, containment and destination sibling overlap inside
one repository transaction. Null target means explicit detachment.
The operation preserves business code/ID, project, geometry, immutable boundary
history, spatial feature/revisions/links, crops and numbering counters.
Lists and details show the current block or independent status. Existing
updateKind and repository transactions are reused; no new parcel store or
schema migration is introduced. Relationship audit currently uses updatedBy
and updatedAt; a separate relation-event history is not introduced here.
P02D validation is pending local execution.


## P02E — production boundary editing (2026-10-02)

- Reuses ReplaceBoundary and the atomic parcel/spatial update workflow; no schema or parallel store.
- Offline schematic editor displays the original outline, parent, siblings and active children. Choose a corner then tap its new position, or redraw; pan/pinch and explicit zoom controls only change the camera. Holes are displayed and preserved; hole editing is outside this checkpoint.
- Before boundary writes, the transaction rereads the parcel, checks the editor snapshot and sequential boundary version, then validates current parent containment and sibling overlap or active child containment and same-project block overlap. Shared edges are permitted; independent field plots retain their existing placement policy.
- Stable parcel ID, production code, project, parent and SpatialFeature ID are preserved. Boundary history and spatial revision are appended atomically; the latest spatial temporal state is preserved for boundary changes.
- Verified replacements retain explicit confirmation and boundary verification permission. Existing GPS/import replacements also pass the transaction placement checks.
- Validation: pending Windows targeted analyze, backend/widget tests, full regression and device restart test.
