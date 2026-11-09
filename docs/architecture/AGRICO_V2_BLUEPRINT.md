# AGRICO Architecture v2 — Blueprint

Status: APPROVED BASELINE

## 1. Mục tiêu
AGRICO v2 chuyển dần từ cấu trúc kỹ thuật phẳng sang feature-first, giữ tương thích dữ liệu hiện tại và tránh viết chắp vá. Không xóa hệ thống cũ cho tới khi module thay thế đã migrate, test và xác nhận tương đương.

## 2. Quy tắc bắt buộc
1. Feature-first: mỗi nghiệp vụ tự chứa data/domain/application/presentation.
2. UI không gọi SQLite hoặc Firestore trực tiếp.
3. Luồng chuẩn: Presentation -> Application -> Domain -> Repository -> Local/Remote.
4. Offline-first: local là nguồn thao tác tức thời; cloud dùng sync/backup/restore/collaboration.
5. Mọi entity đồng bộ phải có id, farmId, createdAt, updatedAt, createdBy và sync metadata phù hợp.
6. Mọi liên kết dữ liệu phải được validate trước khi restore.
7. RBAC và data scope được kiểm tra ở application/domain, không chỉ ẩn nút UI.
8. Không hard-code chuỗi UI. Toàn bộ giao diện hệ thống hỗ trợ vi/lo/en.
9. Mọi module phải có contract hoàn chỉnh trước khi implementation.
10. Migration additive trước, cleanup sau; main luôn phải có đường quay lại an toàn.

## 3. Nhóm nghiệp vụ
- core platform
- farm
- production
- workforce
- work management
- chat
- machinery
- inventory
- fuel
- finance
- reports
- AI assistant
- cloud & backup
- settings

## 4. Cấu trúc feature chuẩn
```text
lib/
  app/
    bootstrap/
    navigation/
    shell/
  core/
    auth/
    database/
    errors/
    localization/
    permissions/
    sync/
    theme/
    utils/
    widgets/
  features/
    <feature>/
      data/
        local/
        models/
        remote/
        repositories/
      domain/
        entities/
        repositories/
        usecases/
      application/
        controllers/
        state/
      presentation/
        screens/
        widgets/
        dialogs/
```

## 5. Dependency direction
`presentation -> application -> domain <- data`

Domain không import Flutter UI, SQLite hay Firebase.

## 6. Chuỗi nghiệp vụ lõi
Farm -> Field -> Season -> Production Log / Task / Harvest -> Resource usage -> Production Cost -> Finance/Report.

Workforce, machinery, inventory và fuel là resource dùng xuyên chuỗi. Chat có thể gắn Farm/Team/Task/Field hoặc Direct conversation.

## 7. Navigation baseline
Bottom navigation:
- Home
- Modules
- Quick Create (+)
- Reports
- Profile

Home chỉ hiển thị dashboard, việc cần xử lý, cảnh báo, thao tác nhanh và hoạt động gần đây. Modules hiển thị chức năng theo nhóm và theo quyền người dùng.

## 8. RBAC
Permission naming: `<resource>.<action>`.

Data scope chuẩn:
- allFarm
- team
- assignedFields
- assignedTasks
- own

Role mặc định dự kiến:
- owner
- admin
- manager
- supervisor
- accountant
- warehouseKeeper
- machineOperator
- worker
- viewer

Custom role được hỗ trợ ở tầng dữ liệu.

## 9. Task contract tối thiểu
Task phải hỗ trợ farm, field, season, team, assignee(s), assigner, machine, material/resource links, priority, status, start/due/completed timestamps, checklist, attachments, notes và linked conversation.

## 10. Chat contract tối thiểu
Conversation types: direct, team, task, field, farm.
Message hỗ trợ sender, text, attachment, reply, timestamps, delivery/read metadata và system events. Quyền truy cập conversation được suy ra từ membership + scope + linked entity.

## 11. Localization
Locale bắt buộc: Vietnamese (`vi`), Lao (`lo`), English (`en`).
Không lưu text dịch trực tiếp trong business entity. Code dùng localization key; dữ liệu do người dùng nhập giữ nguyên.

## 12. Cloud / restore
Giữ nguyên nguyên tắc full restore hiện có: tải snapshot trước khi thay local, validate dependency, deduplicate, giữ local khi cloud group rỗng/không hợp lệ và báo cáo skipped/repaired/kept-local.

## 13. Definition of Ready cho một module
Trước khi code module phải khóa:
- entities và field dictionary
- relationships
- permissions + data scope
- local schema + migrations
- cloud schema
- repository contract
- sync/restore policy
- business rules
- UI flow
- localization keys vi/lo/en
- tests/acceptance criteria

## 14. Definition of Done
Module chỉ Done khi analyze/test pass, CRUD/business flow chạy offline, sync/restore được kiểm thử nếu áp dụng, RBAC được test, ba ngôn ngữ không thiếu key, không hard-code UI text, và không làm hỏng dữ liệu cũ.

## 15. Migration strategy
Phase A: foundation/contracts.
Phase B: app shell + localization + permissions.
Phase C: migrate Farm/Field/Season.
Phase D: Workforce + Tasks + Chat.
Phase E: Machinery + Inventory + Fuel.
Phase F: Production + Harvest + Cost + Finance.
Phase G: Reports + AI + Cloud hardening.
Phase H: remove legacy code only after parity tests.
