import '../../personnel/data/sqlite_payroll_adjustments.dart';
import 'dart:convert';
import '../domain/integration_store.dart';
import '../domain/integration_snapshot.dart';
import 'integration_integrity.dart';
import '../../trade/data/trade_integrity.dart';
import '../../personnel/data/personnel_integrity.dart';
import '../../machines/data/machine_integrity.dart';
import '../../inventory/data/local/production_inventory_integrity.dart';
import 'package:sqflite/sqflite.dart';
import 'integration_cash.dart';
import '../../trade/data/sqlite_trade_repository.dart';
import '../../trade/domain/trade.dart';
import '../../inventory/data/local/sqlite_inventory_repository.dart';
import '../../inventory/domain/entities/inventory_item.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

class IntegrationRepository implements IntegrationStore {
  const IntegrationRepository(this.database);
  final Database database;
  static const tables = {
    ...IntegrationCash.tables,
    'integration_fuel_issues_v1',
  };
  static Future<void> createSchema(DatabaseExecutor db) async {
    await IntegrationCash.createSchema(db);
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS integration_fuel_issues_v1(farm_id TEXT NOT NULL,expense_id TEXT PRIMARY KEY REFERENCES machine_expenses_v1(id),movement_id TEXT NOT NULL UNIQUE REFERENCES inventory_movements_v2(id),reversal_movement_id TEXT UNIQUE REFERENCES inventory_movements_v2(id),reason TEXT,actor_id TEXT NOT NULL)''',
    );
  }

  static const reportTables = {
    'company_catalog_entries_v1',
    'inventory_warehouses_v1',
    'inventory_warehouse_stock_v1',
    'inventory_transfers_v1',
    'inventory_items_v2',
    'inventory_movements_v2',
    'land_parcels',
    'production_seasons_v2',
    'production_plans_v1',
    'production_plan_audit_v1',
    'production_plan_tasks_v1',
    'production_material_costs_v2',
    'farm_tasks_v2',
    ...SqlitePayrollAdjustments.tables,
    'personnel_profiles_v1',
    'personnel_pay_rates_v1',
    'personnel_entries_v1',
    'production_labor_costs_v1',
    'personnel_payrolls_v1',
    'personnel_payments_v1',
    'personnel_payroll_lines_v1',
    'machine_profiles_v1',
    'machine_rates_v1',
    'machine_runs_v1',
    'machine_costs_v1',
    'machine_expenses_v1',
    'finance_documents_v2',
    'trade_documents_v1',
    'trade_lots_v1',
    'trade_settlements_v1',
    'trade_reversals_v1',
    'trade_stock_links_v1',
    ...tables,
  };
  Future<IntegrationSnapshot> snapshot(String farm, String period) async {
    final snapshot = IntegrationSnapshot(
      farm: farm,
      period: period,
      tables: {},
    );
    snapshot.to;
    final data = await database.transaction((tx) async {
      final tables = <String, List<Map<String, Object?>>>{};
      final available = (await tx.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name']).toSet();
      for (final name in reportTables) {
        if (!available.contains(name)) {
          tables[name] = [];
          continue;
        }
        if (name == 'personnel_payroll_lines_v1') {
          tables[name] = await tx.rawQuery(
            'SELECT l.* FROM personnel_payroll_lines_v1 l JOIN personnel_payrolls_v1 p ON p.id=l.payroll_id WHERE p.farm_id=?',
            [farm],
          );
        } else {
          tables[name] = await tx.query(
            name,
            where: name == 'finance_documents_v2'
                ? 'organization_id=?'
                : 'farm_id=?',
            whereArgs: [farm],
          );
        }
      }
      return tables;
    });
    return IntegrationSnapshot(farm: farm, period: period, tables: data);
  }

  Future<List<String>> reconcile(String farm) async {
    final result = await database.transaction((tx) async {
      final errors = <String>[];
      for (final check in <String, Future<void> Function(DatabaseExecutor)>{
        'Kho/sản xuất': ProductionInventoryIntegrity.validate,
        'Nhân sự': PersonnelIntegrity.validate,
        'Máy': MachineIntegrity.validate,
        'Mua bán': TradeIntegrity.validate,
        'Sổ liên kết': IntegrationIntegrity.validate,
      }.entries) {
        try {
          await check.value(tx);
        } catch (_) {
          errors.add('Không khớp: ${check.key}');
        }
      }
      return errors;
    });
    return result;
  }

  static Map<String, dynamic> body(Object? value) =>
      Map<String, dynamic>.from(jsonDecode(value as String) as Map);
  static Future<void> actor(String id) async {
    if (id.trim().isEmpty) throw const FormatException('Actor required.');
  }

  Future<void> linkSalary(
    String farm,
    String id,
    String actorId, {
    String? existingFinanceId,
  }) => database.transaction((tx) async {
    await actor(actorId);
    final p = await SqliteTradeRepository.one(
      tx,
      'personnel_payments_v1',
      farm,
      id,
    );
    await IntegrationCash.salary(
      tx,
      p,
      actorId,
      existingFinanceId: existingFinanceId,
    );
  });
  Future<void> reverseSalary(
    String farm,
    String payment,
    String id,
    String day,
    String reason,
    String actorId,
  ) => database.transaction((tx) async {
    await actor(actorId);
    TradeMath.requiredText(reason);
    TradeMath.requiredText(id);
    TradeMath.date(day);
    final p = await SqliteTradeRepository.one(
      tx,
      'personnel_payments_v1',
      farm,
      payment,
    );
    final prior = await tx.query(
      'integration_salary_reversals_v1',
      where: 'payment_id=? OR id=?',
      whereArgs: [payment, id],
    );
    if (prior.isNotEmpty) {
      final r = prior.single;
      if (r['farm_id'] == farm &&
          r['payment_id'] == payment &&
          r['id'] == id &&
          r['day'] == day &&
          r['reason'] == reason)
        return;
      throw StateError('Already reversed or identity conflict.');
    }
    if (day.compareTo(p['business_day'] as String) < 0)
      throw StateError('Reversal precedes payment.');
    final link = await tx.query(
      'integration_cash_links_v1',
      where: 'source_id=? AND farm_id=?',
      whereArgs: [payment, farm],
    );
    if (link.length != 1)
      throw StateError('Link the original payment to cash first.');
    final sourcePayroll = (await tx.query(
      'personnel_payrolls_v1',
      where: 'id=? AND farm_id=?',
      whereArgs: [p['payroll_id'], farm],
    )).single;
    final refunded = SqlitePayrollAdjustments.refundTotal(
      await SqlitePayrollAdjustments.refundRows(tx, p['payroll_id']! as String),
    );
    if (ExactDecimal.parse(
      LaborMoney.minus(
        await SqlitePayrollAdjustments.paid(
          tx,
          farm,
          p['payroll_id']! as String,
        ),
        p['amount']! as String,
      ),
    ).isNegative)
      throw StateError('Reverse dependent payroll refunds first.');
    if ((ExactDecimal.parse(refunded).coefficient != BigInt.zero ||
            (await SqlitePayrollAdjustments.approved(
              tx,
              p['payroll_id']! as String,
            )).isNotEmpty ||
            (await SqlitePayrollAdjustments.refundRows(
              tx,
              p['payroll_id']! as String,
            )).isNotEmpty) &&
        day.compareTo(
              await SqlitePayrollAdjustments.latestDay(tx, sourcePayroll),
            ) <
            0)
      throw StateError('Reversal precedes the corrected payroll ledger.');
    final finance = 'integrated:salary-reversal:$id';
    await IntegrationCash.write(
      tx,
      id: finance,
      farm: farm,
      day: day,
      amountText: p['amount'] as String,
      currency: p['currency'] as String,
      category: 'INTEGRATED_PAYROLL_REVERSAL',
      note: '${p['payroll_id']} · $reason',
      receipt: true,
    );
    await tx.insert('integration_salary_reversals_v1', {
      'id': id,
      'farm_id': farm,
      'payment_id': payment,
      'finance_id': finance,
      'day': day,
      'reason': reason,
      'actor_id': actorId,
    });
  });
  Future<void> machinePayable(
    String farm,
    String expenseId,
    String supplier,
    String reference,
    MoneyRounding rounding,
    String actorId, {
    String? existingDocumentId,
  }) => database.transaction((tx) async {
    await actor(actorId);
    final source = await SqliteTradeRepository.one(
      tx,
      'machine_expenses_v1',
      farm,
      expenseId,
    );
    if (source['status'] != 'approved')
      throw StateError('Approve machine expense first.');
    final prior = await tx.query(
      'integration_machine_links_v1',
      where: 'expense_id=?',
      whereArgs: [expenseId],
    );
    if (prior.isNotEmpty) {
      final p = prior.single;
      if (p['farm_id'] != farm || p['rounding'] != rounding.name)
        throw StateError('Source already linked differently.');
      final d = await SqliteTradeRepository.one(
        tx,
        'trade_documents_v1',
        farm,
        p['document_id'] as String,
      );
      if (d['party_id'] != supplier ||
          d['reference'] != reference.trim() ||
          (existingDocumentId != null && existingDocumentId != d['id']))
        throw StateError('Source already linked differently.');
      return;
    }
    if ((await tx.query(
      'integration_fuel_issues_v1',
      where: 'expense_id=?',
      whereArgs: [expenseId],
    )).isNotEmpty)
      throw StateError('Internal fuel cannot become an external payable.');
    final s = body(source['body']);
    final doc = existingDocumentId ?? 'machine-payable:$expenseId';
    final repo = SqliteTradeRepository(database);
    if (existingDocumentId == null) {
      final draft = TradeDraft(
        id: doc,
        kind: TradeKind.expense,
        day: s['day'] as String,
        currency: s['currency'] as String,
        rounding: rounding,
        lines: [
          TradeLine(
            ref: '',
            quantity: '1',
            price: s['amount'] as String,
            label: '${s['kind']} · ${s['machineId']} · ${s['note']}',
            zeroConfirmed:
                ExactDecimal.parse(s['amount'] as String).coefficient ==
                BigInt.zero,
          ),
        ],
        partyId: supplier,
        dueOn: s['day'] as String,
        reference: reference,
        note: 'Machine expense $expenseId',
        expenseTreatment: 'includedInProduction',
      );
      await repo.createInTransaction(tx, farm, draft, actorId);
      await repo.postInTransaction(tx, farm, doc, 0, actorId);
    } else {
      final existing = await SqliteTradeRepository.one(
        tx,
        'trade_documents_v1',
        farm,
        doc,
      );
      final d = TradeDraft.fromJson(body(existing['body']));
      if (existing['status'] != 'posted' ||
          d.kind != TradeKind.expense ||
          d.expenseTreatment != 'includedInProduction' ||
          d.partyId != supplier ||
          d.day != s['day'] ||
          d.reference.trim() != reference.trim() ||
          d.currency != s['currency'] ||
          d.billed != TradeMath.bill(s['amount'] as String, rounding))
        throw StateError(
          'Existing payable does not match this complete source.',
        );
    }
    await tx.insert('integration_machine_links_v1', {
      'farm_id': farm,
      'expense_id': expenseId,
      'document_id': doc,
      'source_amount': s['amount'],
      'rounding': rounding.name,
      'actor_id': actorId,
    });
  });
  Future<void> fuelIssue(
    String farm,
    String expenseId,
    String itemId,
    String price,
    bool confirmZero,
    String actorId, {
    String? existingMovementId,
  }) => database.transaction((tx) async {
    await actor(actorId);
    final source = await SqliteTradeRepository.one(
      tx,
      'machine_expenses_v1',
      farm,
      expenseId,
    );
    if (source['status'] != 'approved' || source['kind'] != 'fuel')
      throw StateError('Approved fuel source required.');
    if ((await tx.query(
      'integration_machine_links_v1',
      where: 'expense_id=?',
      whereArgs: [expenseId],
    )).isNotEmpty)
      throw StateError('Source already linked as external payable.');
    final s = body(source['body']);
    final currency = s['currency'] as String;
    ExactDecimal.validatePrice(price, currency);
    final litres = s['litres'] as String;
    final units = TradeMath.units(litres);
    await SqliteTradeRepository.catalog(tx, farm, itemId, {'material'});
    final item = await SqliteTradeRepository.one(
      tx,
      'inventory_items_v2',
      farm,
      itemId,
    );
    if (!{
      'l',
      'liter',
      'litre',
      'litres',
      'liters',
      'lít',
      'ລິດ',
    }.contains((item['unit'] as String).trim().toLowerCase()))
      throw StateError(
        'Select a material with litre units; no implicit conversion.',
      );
    final id = existingMovementId ?? 'integrated:fuel:$expenseId';
    final prior = await tx.query(
      'integration_fuel_issues_v1',
      where: 'expense_id=?',
      whereArgs: [expenseId],
    );
    if (prior.isNotEmpty) {
      final previous = await SqliteTradeRepository.one(
        tx,
        'inventory_movements_v2',
        farm,
        prior.single['movement_id'] as String,
      );
      if (previous['item_id'] != itemId ||
          ExactDecimal.parse(
                previous['unit_price_text'] as String,
              ).compareTo(ExactDecimal.parse(price)) !=
              0)
        throw StateError('Source already linked differently.');
      if (prior.single['farm_id'] != farm || prior.single['movement_id'] != id)
        throw StateError('Source already linked differently.');
      return;
    }
    if (existingMovementId == null) {
      await SqliteInventoryRepository(database).recordInTransaction(
        tx,
        InventoryMovement(
          id: id,
          farmId: farm,
          itemId: itemId,
          kind: InventoryMovementKind.issue,
          quantity: ExactDecimal.quantityFromUnits(units),
          occurredAt: TradeMath.instant(s['day'] as String),
          unitPriceText: price,
          currency: currency,
          pricedBy: actorId,
          zeroPriceConfirmed: confirmZero,
        ),
      );
    }
    final movement = await SqliteTradeRepository.one(
      tx,
      'inventory_movements_v2',
      farm,
      id,
    );
    if (movement['kind'] != 'issue' ||
        movement['item_id'] != itemId ||
        movement['quantity_units'] != units ||
        movement['currency'] != currency ||
        ExactDecimal.parse(
              movement['unit_price_text'] as String,
            ).compareTo(ExactDecimal.parse(price)) !=
            0 ||
        movement['plan_id'] != null ||
        LaborMoney.day(DateTime.parse(movement['occurred_at'] as String)) !=
            s['day'])
      throw StateError('Stock issue does not match source exactly.');
    if ((await tx.query(
      'trade_stock_links_v1',
      where: 'movement_id=?',
      whereArgs: [id],
    )).isNotEmpty)
      throw StateError('Movement belongs to trade.');
    await tx.insert('integration_fuel_issues_v1', {
      'farm_id': farm,
      'expense_id': expenseId,
      'movement_id': id,
      'actor_id': actorId,
    });
  });
  Future<void> reverseFuel(
    String farm,
    String expense,
    String day,
    String reason,
    String actorId,
  ) => database.transaction((tx) async {
    await actor(actorId);
    TradeMath.requiredText(reason);
    SqliteTradeRepository.postingDay(day);
    final rows = await tx.query(
      'integration_fuel_issues_v1',
      where: 'expense_id=? AND farm_id=?',
      whereArgs: [expense, farm],
    );
    if (rows.length != 1) throw StateError('Link unavailable.');
    final link = rows.single;
    if (link['reversal_movement_id'] != null)
      throw StateError('Already reversed.');
    final m = await SqliteTradeRepository.one(
      tx,
      'inventory_movements_v2',
      farm,
      link['movement_id'] as String,
    );
    if (day.compareTo(
          LaborMoney.day(DateTime.parse(m['occurred_at'] as String)),
        ) <
        0)
      throw StateError('Reversal precedes issue.');
    final id = 'integrated:fuel-reversal:$expense';
    await SqliteInventoryRepository(database).recordInTransaction(
      tx,
      InventoryMovement(
        id: id,
        farmId: farm,
        itemId: m['item_id'] as String,
        warehouseId: m['warehouse_id'] as String?,
        kind: InventoryMovementKind.receipt,
        quantity: ExactDecimal.quantityFromUnits(m['quantity_units'] as int),
        occurredAt: TradeMath.instant(day),
        unitPriceText: m['unit_price_text'] as String,
        currency: m['currency'] as String,
        pricedBy: actorId,
        zeroPriceConfirmed: m['zero_price_confirmed'] == 1,
      ),
    );
    await tx.update(
      'integration_fuel_issues_v1',
      {'reversal_movement_id': id, 'reason': reason},
      where: 'expense_id=?',
      whereArgs: [expense],
    );
  });
  static const metadataTables = {
    'parcel': 'land_parcels',
    'harvest': 'trade_documents_v1',
    'machine': 'company_catalog_entries_v1',
    'maintenance': 'machine_expenses_v1',
    'worker': 'company_catalog_entries_v1',
    'payroll': 'personnel_payrolls_v1',
    'stock': 'inventory_items_v2',
    'capital': 'finance_documents_v2',
    'run': 'machine_runs_v1',
  };
  static Future<Map<String, Object?>> metadataEntity(
    DatabaseExecutor db,
    String farm,
    String kind,
    String id,
  ) async {
    final table = metadataTables[kind];
    if (table == null)
      throw const FormatException('Unknown report detail type.');
    if (kind != 'capital')
      return SqliteTradeRepository.one(db, table, farm, id);
    final rows = await db.query(
      table,
      where: 'id=? AND organization_id=?',
      whereArgs: [id, farm],
    );
    if (rows.length != 1)
      throw StateError('Cash document unavailable in this farm.');
    return rows.single;
  }

  static Future<void> validateMetadataLinks(
    DatabaseExecutor db,
    String kind,
    Map<String, Object?> entity,
    Map<String, String> values,
  ) async {
    if (kind != 'capital' || (values['capitalKind'] ?? '').isEmpty) return;
    final id = entity['id'];
    for (final link in [
      'integration_cash_links_v1',
      'integration_salary_reversals_v1',
      if (await SqlitePayrollAdjustments.enabled(db))
        SqlitePayrollAdjustments.refunds,
      'trade_settlements_v1',
      'trade_reversals_v1',
    ]) {
      if ((await db.query(
        link,
        where: 'finance_id=?',
        whereArgs: [id],
      )).isNotEmpty)
        throw StateError('A settlement cannot also be owner capital.');
    }
  }

  static const metadataFields = {
    'stock': {'minimumQuantity'},
    'capital': {'capitalKind', 'reason'},
    'run': {
      'conditionBefore',
      'conditionAfter',
      'fuelConsumedLitres',
      'incident',
    },
    'parcel': {'soilType', 'pH', 'preparedOn', 'evaluation'},
    'harvest': {'freshKg', 'dryKg', 'quality'},
    'machine': {'type', 'manufacturer', 'year', 'purchasedOn', 'warrantyUntil'},
    'maintenance': {'parts', 'quantity', 'unitPrice', 'performer'},
    'worker': {'title'},
    'payroll': {'insurance'},
  };
  Future<void> metadata(
    String farm,
    String kind,
    String id,
    int revision,
    Map<String, String> values,
    String actorId,
  ) => database.transaction((tx) async {
    await actor(actorId);
    if (!metadataFields.containsKey(kind) ||
        values.keys.any((k) => !metadataFields[kind]!.contains(k)) ||
        values.values.any((v) => v.length > 1000))
      throw const FormatException('Invalid metadata.');
    final entity = await metadataEntity(tx, farm, kind, id);
    if ((kind == 'machine' || kind == 'worker') && entity['kind'] != kind)
      throw StateError('Wrong catalog type.');
    if (kind == 'harvest' && entity['kind'] != 'harvest' ||
        kind == 'maintenance' && entity['kind'] != 'maintenance')
      throw StateError('Wrong source type.');
    validateMetadata(kind, values, entity);
    await validateMetadataLinks(tx, kind, entity, values);
    final old = await tx.query(
      'integration_report_metadata_v1',
      where: 'farm_id=? AND kind=? AND entity_id=?',
      whereArgs: [farm, kind, id],
    );
    if ((old.isEmpty ? 0 : old.single['revision']) != revision)
      throw StateError('Stale metadata.');
    await tx.insert('integration_report_metadata_v1', {
      'farm_id': farm,
      'kind': kind,
      'entity_id': id,
      'body': jsonEncode(values),
      'revision': revision + 1,
      'actor_id': actorId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
  static void validateMetadata(
    String kind,
    Map<String, String> values,
    Map<String, Object?> entity,
  ) {
    if (!metadataFields.containsKey(kind) ||
        values.keys.any((k) => !metadataFields[kind]!.contains(k)) ||
        values.values.any((v) => v.length > 1000))
      throw const FormatException('Invalid metadata.');
    for (final key in ['minimumQuantity', 'fuelConsumedLitres']) {
      final text = values[key] ?? '';
      if (text.isEmpty) continue;
      final number = ExactDecimal.parse(text, maxScale: 6);
      final units = number.coefficient * BigInt.from(10).pow(6 - number.scale);
      if (units < BigInt.zero || units > BigInt.from(9007199254740991))
        throw const FormatException('Invalid exact quantity.');
    }
    if (kind == 'capital') {
      final tag = values['capitalKind'] ?? '';
      if (!{'', 'contribution', 'return'}.contains(tag))
        throw const FormatException('Select a capital classification.');
      if (tag.isNotEmpty &&
          ((values['reason'] ?? '').trim().isEmpty ||
              entity['kind'] != (tag == 'contribution' ? 'THU' : 'CHI')))
        throw StateError(
          'Capital needs a reason and the matching cash direction.',
        );
    }
    for (final field in [
      'freshKg',
      'dryKg',
      'quantity',
      'unitPrice',
      'insurance',
    ]) {
      if ((values[field] ?? '').isNotEmpty)
        LaborMoney.nonNegative(values[field]!);
    }
    for (final f in ['preparedOn', 'purchasedOn', 'warrantyUntil']) {
      if ((values[f] ?? '').isNotEmpty) TradeMath.date(values[f]!);
    }
    if ((values['pH'] ?? '').isNotEmpty &&
        (double.tryParse(values['pH']!) == null ||
            !double.parse(values['pH']!).isFinite ||
            double.parse(values['pH']!) < 0 ||
            double.parse(values['pH']!) > 14))
      throw const FormatException('pH must be 0–14.');
    if ((values['year'] ?? '').isNotEmpty &&
        (int.tryParse(values['year']!) == null ||
            int.parse(values['year']!) < 1900 ||
            int.parse(values['year']!) > DateTime.now().year + 1))
      throw const FormatException('Invalid year.');
    if ((values['freshKg'] ?? '').isNotEmpty &&
        (values['dryKg'] ?? '').isNotEmpty &&
        ExactDecimal.parse(
              values['dryKg']!,
            ).compareTo(ExactDecimal.parse(values['freshKg']!)) >
            0)
      throw const FormatException('Dry quantity exceeds fresh.');
    if ((values['purchasedOn'] ?? '').isNotEmpty &&
        (values['warrantyUntil'] ?? '').isNotEmpty &&
        values['warrantyUntil']!.compareTo(values['purchasedOn']!) < 0)
      throw const FormatException('Warranty before purchase.');
    if (kind == 'payroll' &&
        (values['insurance'] ?? '').isNotEmpty &&
        ExactDecimal.parse(
              values['insurance']!,
            ).compareTo(ExactDecimal.parse(entity['deduction'] as String)) >
            0)
      throw StateError(
        'Insurance is a disclosed component of existing deductions, not a new deduction.',
      );
    if (kind == 'maintenance' &&
        (values['quantity'] ?? '').isNotEmpty &&
        (values['unitPrice'] ?? '').isNotEmpty) {
      final total =
          ExactDecimal.parse(values['quantity']!) *
          ExactDecimal.parse(values['unitPrice']!);
      if (total.compareTo(
            ExactDecimal.parse(body(entity['body'])['amount'] as String),
          ) >
          0)
        throw StateError('Parts exceed declared maintenance total.');
    }
  }
}
