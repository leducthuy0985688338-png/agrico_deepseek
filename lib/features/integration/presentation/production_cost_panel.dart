import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../application/production_cost_projection.dart';
import '../domain/integration_snapshot.dart';
import '../domain/production_cost_entry.dart';

class ProductionCostPanel extends StatelessWidget {
  const ProductionCostPanel({
    super.key,
    required this.snapshot,
    required this.canView,
  });
  final IntegrationSnapshot snapshot;
  final bool Function() canView;
  @override
  Widget build(BuildContext context) {
    String tr(String vi, String en, String lo) =>
        switch (AppLocalizations.of(context).locale.languageCode) {
          'vi' => vi,
          'lo' => lo,
          _ => en,
        };
    if (!canView()) {
      return Text(tr('Không có quyền xem', 'Access denied', 'ບໍ່ມີສິດເບິ່ງ'));
    }
    final projection = ProductionCostProjection(snapshot);
    final groups = projection.groups();
    final planGroups = projection.groups(byPlan: true);
    final parcelIds = groups.map((g) => g.parcelId).toSet();
    final missing = tr(
      'CHƯA ĐỦ DỮ LIỆU',
      'INSUFFICIENT DATA',
      'ຂໍ້ມູນບໍ່ພຽງພໍ',
    );
    String state(String status) => switch (status) {
      'INCOMPLETE' => missing,
      'NO_ACTIVITY' => tr('Không phát sinh', 'No activity', 'ບໍ່ມີລາຍການ'),
      _ => tr('Đã duyệt', 'Approved', 'ອະນຸມັດແລ້ວ'),
    };
    Widget table(List<ProductionCostGroup> rows) {
      final amounts = <String, List<String?>>{
        tr('Nhân công', 'Labor', 'ແຮງງານ'): [
          for (final g in rows) g.amount(ProductionCostCategory.labor),
        ],
        tr('Vật tư', 'Materials', 'ວັດສະດຸ'): [
          for (final g in rows) g.amount(ProductionCostCategory.material),
        ],
        tr('Ca máy', 'Machines', 'ເຄື່ອງຈັກ'): [
          for (final g in rows) g.amount(ProductionCostCategory.machine),
        ],
        tr('Chi phí khác', 'Other costs', 'ຄ່າອື່ນໆ'): [
          for (final g in rows) g.amount(ProductionCostCategory.other),
        ],
        tr('Tổng giá thành', 'Total incurred cost', 'ຕົ້ນທຶນລວມ'): [
          for (final g in rows) g.totalCost,
        ],
        tr('Doanh thu đã ghi nhận', 'Posted sales', 'ຍອດຂາຍບັນທຶກ'): [
          for (final g in rows) g.revenue,
        ],
        tr(
          'Doanh thu trừ chi phí phát sinh',
          'Sales minus incurred cost',
          'ຍອດຂາຍລົບຕົ້ນທຶນ',
        ): [
          for (final g in rows) g.profit,
        ],
      };
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(tr('Chỉ tiêu', 'Metric', 'ລາຍການ'))),
            for (final g in rows) DataColumn(label: Text(g.currency)),
          ],
          rows: [
            for (final e in amounts.entries)
              DataRow(
                cells: [
                  DataCell(Text(e.key)),
                  for (final v in e.value) DataCell(Text(v ?? missing)),
                ],
              ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Giá thành sản xuất theo lô và tiền tệ',
                'Production cost by parcel and currency',
                'ຕົ້ນທຶນຕາມຕອນດິນ ແລະ ສະກຸນເງິນ',
              ),
            ),
            Text(
              '${snapshot.period} · ${snapshot.closingRevision == null ? tr('Kỳ mở', 'Open period', 'ເດືອນເປີດ') : tr('Đã khóa kỳ', 'Period locked', 'ປິດເດືອນແລ້ວ')}',
            ),
            Text(
              tr(
                'Nguồn V2 đã truy vết; khoản thiếu approval/audit và nguồn legacy chưa được chuyển đổi không được tự cộng.',
                'Traceable V2 sources; missing approval/audit and unconverted legacy sources are not silently included.',
                'ແຫຼ່ງ V2; ບໍ່ລວມຂໍ້ມູນເກົ່າ ຫຼື ລາຍການທີ່ຂາດການອະນຸມັດ.',
              ),
            ),
            for (final parcel in parcelIds)
              ExpansionTile(
                key: ValueKey('production-cost-parcel-$parcel'),
                title: Text(snapshot.parcelCode(parcel)),
                subtitle: Text(
                  groups
                      .where((g) => g.parcelId == parcel)
                      .map((g) => '${g.currency}: ${state(g.status)}')
                      .join(' · '),
                ),
                children: [
                  table(groups.where((g) => g.parcelId == parcel).toList()),
                  for (final plan
                      in planGroups
                          .where((g) => g.parcelId == parcel)
                          .map((g) => g.planId)
                          .toSet())
                    ExpansionTile(
                      title: Text(snapshot.planCode(plan)),
                      children: [
                        table(
                          planGroups.where((g) => g.planId == plan).toList(),
                        ),
                        for (final e in projection.entries.where(
                          (e) => e.planId == plan,
                        ))
                          ListTile(
                            title: Text(
                              '${e.category.name} · ${e.amountExact ?? missing} ${e.currency ?? "?"}',
                            ),
                            subtitle: Text(
                              '${e.sourceType}:${e.sourceId} · ${e.eligibility.name} · ${e.effectiveDate ?? "?"}\n${e.issues.join(", ")}',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ExpansionTile(
              title: Text(
                tr(
                  'Đối chiếu nguồn và dữ liệu thiếu',
                  'Source reconciliation and missing data',
                  'ກວດແຫຼ່ງຂໍ້ມູນ',
                ),
              ),
              children: [
                for (final issue in projection.coverageIssues)
                  ListTile(title: Text(issue)),
                for (final e in projection.entries.where(
                  (e) => e.eligibility != CostEligibility.eligible,
                ))
                  ListTile(
                    title: Text(
                      '${e.sourceType}:${e.sourceId} · ${e.eligibility.name}',
                    ),
                    subtitle: Text(e.issues.join(', ')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
