import '../../personnel/domain/personnel.dart' show LaborMoney;
import 'package:sqflite/sqflite.dart';
import 'integration_cash.dart';
import 'integration_repository.dart';
import '../../trade/data/sqlite_trade_repository.dart';
import '../../trade/domain/trade.dart';

abstract final class IntegrationIntegrity {
  static Future<void> validate(DatabaseExecutor db) async {
    void require(bool value) {
      if (!value) throw StateError('Integrated ledger does not reconcile.');
    }

    final links = await db.query('integration_cash_links_v1');
    final reversals = await db.query('integration_salary_reversals_v1');
    for (final link in links) {
      final farm = link['farm_id'] as String;
      final p = await SqliteTradeRepository.one(
        db,
        'personnel_payments_v1',
        farm,
        link['source_id'] as String,
      );
      final f = (await db.query(
        'finance_documents_v2',
        where: 'id=? AND organization_id=?',
        whereArgs: [link['finance_id'], farm],
      )).single;
      require(
        f['kind'] == 'CHI' &&
            f['currency'] == p['currency'] &&
            IntegrationCash.amount(f) ==
                ExactDecimal.parse(p['amount'] as String).toString() &&
            (f['occurred_at'] as String).substring(0, 10) == p['business_day'],
      );
      require(
        (await db.query(
              'trade_settlements_v1',
              where: 'finance_id=?',
              whereArgs: [f['id']],
            )).isEmpty &&
            (await db.query(
              'trade_reversals_v1',
              where: 'finance_id=?',
              whereArgs: [f['id']],
            )).isEmpty,
      );
    }
    for (final r in reversals) {
      final p = await SqliteTradeRepository.one(
        db,
        'personnel_payments_v1',
        r['farm_id'] as String,
        r['payment_id'] as String,
      );
      require(
        links.any(
          (l) => l['source_id'] == p['id'] && l['farm_id'] == r['farm_id'],
        ),
      );
      final f = (await db.query(
        'finance_documents_v2',
        where: 'id=? AND organization_id=?',
        whereArgs: [r['finance_id'], r['farm_id']],
      )).single;
      require(
        f['kind'] == 'THU' &&
            f['currency'] == p['currency'] &&
            IntegrationCash.amount(f) ==
                ExactDecimal.parse(p['amount'] as String).toString() &&
            (f['occurred_at'] as String).substring(0, 10) == r['day'] &&
            (r['day'] as String).compareTo(p['business_day'] as String) >= 0 &&
            (r['reason'] as String).trim().isNotEmpty,
      );
    }
    final machineLinks = await db.query('integration_machine_links_v1');
    final fuels = await db.query('integration_fuel_issues_v1');
    for (final l in machineLinks) {
      final farm = l['farm_id'] as String;
      final e = await SqliteTradeRepository.one(
        db,
        'machine_expenses_v1',
        farm,
        l['expense_id'] as String,
      );
      final source = IntegrationRepository.body(e['body']);
      final d = await SqliteTradeRepository.one(
        db,
        'trade_documents_v1',
        farm,
        l['document_id'] as String,
      );
      final draft = TradeDraft.fromJson(IntegrationRepository.body(d['body']));
      require(e['status'] == 'approved' || d['status'] == 'void');
      require(
        source['day'] == draft.day &&
            l['actor_id'].toString().trim().isNotEmpty,
      );
      require(
        draft.kind == TradeKind.expense &&
            draft.expenseTreatment == 'includedInProduction' &&
            source['currency'] == draft.currency &&
            source['amount'] == l['source_amount'] &&
            draft.billed ==
                TradeMath.bill(
                  source['amount'] as String,
                  MoneyRounding.values.byName(l['rounding'] as String),
                ),
      );
      require(!fuels.any((f) => f['expense_id'] == l['expense_id']));
    }
    for (final link in fuels) {
      final farm = link['farm_id'] as String;
      final e = await SqliteTradeRepository.one(
        db,
        'machine_expenses_v1',
        farm,
        link['expense_id'] as String,
      );
      final source = IntegrationRepository.body(e['body']);
      final m = await SqliteTradeRepository.one(
        db,
        'inventory_movements_v2',
        farm,
        link['movement_id'] as String,
      );
      final item = await SqliteTradeRepository.one(
        db,
        'inventory_items_v2',
        farm,
        m['item_id'] as String,
      );
      await SqliteTradeRepository.catalog(db, farm, m['item_id'] as String, {
        'material',
      });
      require(
        {
          'l',
          'lít',
          'liter',
          'litre',
          'litres',
          'liters',
          'ລິດ',
        }.contains((item['unit'] as String).trim().toLowerCase()),
      );
      require(
        LaborMoney.day(DateTime.parse(m['occurred_at'] as String)) ==
            source['day'],
      );
      require(
        e['kind'] == 'fuel' &&
            (e['status'] == 'approved' ||
                link['reversal_movement_id'] != null) &&
            m['kind'] == 'issue' &&
            m['quantity_units'] ==
                TradeMath.units(source['litres'] as String) &&
            m['currency'] == source['currency'] &&
            m['plan_id'] == null,
      );
      require(
        (await db.query(
          'trade_stock_links_v1',
          where: 'movement_id=?',
          whereArgs: [m['id']],
        )).isEmpty,
      );
      if (link['reversal_movement_id'] != null) {
        final reverse = await SqliteTradeRepository.one(
          db,
          'inventory_movements_v2',
          farm,
          link['reversal_movement_id'] as String,
        );
        require(
          reverse['kind'] == 'receipt' &&
              reverse['quantity_units'] == m['quantity_units'] &&
              reverse['item_id'] == m['item_id'] &&
              reverse['currency'] == m['currency'] &&
              reverse['amount_text'] == m['amount_text'] &&
              reverse['unit_price_text'] == m['unit_price_text'] &&
              reverse['plan_id'] == null &&
              LaborMoney.day(
                    DateTime.parse(reverse['occurred_at'] as String),
                  ).compareTo(
                    LaborMoney.day(DateTime.parse(m['occurred_at'] as String)),
                  ) >=
                  0 &&
              (link['reason'] as String).trim().isNotEmpty,
        );
      }
    }
    for (final m in await db.query('integration_report_metadata_v1')) {
      final kind = m['kind'] as String;
      final table = {
        'parcel': 'land_parcels',
        'harvest': 'trade_documents_v1',
        'machine': 'company_catalog_entries_v1',
        'maintenance': 'machine_expenses_v1',
        'worker': 'company_catalog_entries_v1',
        'payroll': 'personnel_payrolls_v1',
      }[kind];
      require(table != null);
      final entity = await SqliteTradeRepository.one(
        db,
        table!,
        m['farm_id'] as String,
        m['entity_id'] as String,
      );
      require(
        (m['revision'] as int) > 0 &&
            (m['actor_id'] as String).trim().isNotEmpty,
      );
      if ({'worker', 'machine', 'harvest', 'maintenance'}.contains(kind))
        require(entity['kind'] == kind);
      IntegrationRepository.validateMetadata(
        kind,
        Map<String, String>.from(IntegrationRepository.body(m['body'])),
        entity,
      );
    }
    final linkedCash = {
      ...links.map((l) => l['finance_id']),
      ...reversals.map((r) => r['finance_id']),
    };
    for (final f in await db.query('finance_documents_v2')) {
      final scale = (f['amount_scale'] as int?) ?? 0;
      require(scale >= 0 && scale <= 6);
      if ((f['id'] as String).startsWith('integrated:'))
        require(linkedCash.contains(f['id']));
    }
    final linkedStock = {
      ...fuels.map((l) => l['movement_id']),
      ...fuels.map((l) => l['reversal_movement_id']),
    };
    for (final m in await db.query('inventory_movements_v2')) {
      if ((m['id'] as String).startsWith('integrated:'))
        require(linkedStock.contains(m['id']));
    }
  }
}
