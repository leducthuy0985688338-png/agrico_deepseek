import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/trade.dart';
import '../../inventory/data/local/sqlite_inventory_repository.dart';
import '../../inventory/domain/entities/inventory_item.dart';
import '../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../core/identity/domain/business_reference_code.dart';

class SqliteTradeRepository implements TradeRepository {
  const SqliteTradeRepository(this.database);
  final Database database;
  static const tables = {
    'trade_documents_v1',
    'trade_lots_v1',
    'trade_stock_links_v1',
    'trade_settlements_v1',
    'trade_reversals_v1',
    'trade_sequences_v1',
    'trade_audit_v1',
  };
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_documents_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('harvest','sale','purchase','expense')),code TEXT NOT NULL,day TEXT NOT NULL,party_id TEXT REFERENCES company_catalog_entries_v1(id),plan_id TEXT REFERENCES production_plans_v1(id),currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),total TEXT NOT NULL,reference TEXT NOT NULL,body TEXT NOT NULL,snapshot TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('draft','posted','void')),revision INTEGER NOT NULL CHECK(revision>=0),void_day TEXT,UNIQUE(farm_id,code))''',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_trade_external_reference ON trade_documents_v1(farm_id,party_id,reference) WHERE kind IN ('purchase','expense') AND status<>'void'",
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_lots_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,harvest_id TEXT NOT NULL REFERENCES trade_documents_v1(id),item_id TEXT NOT NULL REFERENCES inventory_items_v2(id),plan_id TEXT NOT NULL REFERENCES production_plans_v1(id),day TEXT NOT NULL,code TEXT NOT NULL,original_units INTEGER NOT NULL CHECK(original_units>0),stock_units INTEGER NOT NULL CHECK(stock_units>=0 AND stock_units<=original_units),price TEXT NOT NULL,currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),item_name TEXT NOT NULL,unit TEXT NOT NULL,UNIQUE(farm_id,code))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_stock_links_v1(movement_id TEXT PRIMARY KEY REFERENCES inventory_movements_v2(id),document_id TEXT NOT NULL REFERENCES trade_documents_v1(id),farm_id TEXT NOT NULL,line_no INTEGER NOT NULL,lot_id TEXT REFERENCES trade_lots_v1(id),reversal INTEGER NOT NULL CHECK(reversal IN (0,1)),UNIQUE(document_id,line_no,reversal))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_settlements_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,document_id TEXT NOT NULL REFERENCES trade_documents_v1(id),finance_id TEXT NOT NULL UNIQUE REFERENCES finance_documents_v2(id),amount TEXT NOT NULL,currency TEXT NOT NULL CHECK(currency IN ('VND','LAK')),day TEXT NOT NULL,reference TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_reversals_v1(id TEXT PRIMARY KEY,payment_id TEXT NOT NULL UNIQUE REFERENCES trade_settlements_v1(id),farm_id TEXT NOT NULL,finance_id TEXT NOT NULL UNIQUE REFERENCES finance_documents_v2(id),day TEXT NOT NULL,reason TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_sequences_v1(farm_id TEXT NOT NULL,kind TEXT NOT NULL,month TEXT NOT NULL,value INTEGER NOT NULL CHECK(value>0),PRIMARY KEY(farm_id,kind,month))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS trade_audit_v1(id INTEGER PRIMARY KEY,farm_id TEXT NOT NULL,entity_id TEXT NOT NULL,action TEXT NOT NULL,actor_id TEXT NOT NULL,reason TEXT NOT NULL,occurred_at TEXT NOT NULL)''',
    );
  }

  static Map<String, dynamic> decode(Object? text) =>
      Map<String, dynamic>.from(jsonDecode(text as String) as Map);
  static Future<Map<String, Object?>> one(
    DatabaseExecutor tx,
    String table,
    String farm,
    String id,
  ) async {
    final rows = await tx.query(
      table,
      where: 'id=? AND farm_id=?',
      whereArgs: [id, farm],
    );
    if (rows.length != 1) throw StateError('Record unavailable in this farm.');
    return rows.single;
  }

  static Future<void> audit(
    DatabaseExecutor tx,
    String farm,
    String id,
    String action,
    String actor, [
    String reason = '',
  ]) async {
    TradeMath.requiredText(actor);
    await tx.insert('trade_audit_v1', {
      'farm_id': farm,
      'entity_id': id,
      'action': action,
      'actor_id': actor,
      'reason': reason,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static void postingDay(String day) {
    TradeMath.date(day);
    if (day.compareTo(TradeMath.day()) > 0) {
      throw const FormatException('Future posting is not allowed.');
    }
  }

  static Future<Map<String, Object?>> catalog(
    DatabaseExecutor tx,
    String farm,
    String id,
    Set<String> kinds, {
    bool active = true,
  }) async {
    final c = await one(tx, 'company_catalog_entries_v1', farm, id);
    if (!kinds.contains(c['kind']) || (active && c['active'] != 1)) {
      throw StateError('Wrong catalog type or inactive resource.');
    }
    return c;
  }

  static Future<String> paid(DatabaseExecutor tx, String id) async {
    final rows = await tx.rawQuery(
      'SELECT s.amount FROM trade_settlements_v1 s LEFT JOIN trade_reversals_v1 r ON r.payment_id=s.id WHERE s.document_id=? AND r.id IS NULL',
      [id],
    );
    return TradeMath.total(rows.map((r) => r['amount'] as String));
  }

  static Future<void> validateRefs(
    DatabaseExecutor tx,
    String farm,
    TradeDraft d, {
    bool posting = false,
  }) async {
    d.validate();
    if (d.kind == TradeKind.harvest) {
      final p = await one(tx, 'production_plans_v1', farm, d.planId!);
      if (p['status'] != 'active' ||
          d.day.compareTo(p['starts_on'] as String) < 0 ||
          d.day.compareTo(p['ends_on'] as String) > 0 ||
          p['currency'] != d.currency) {
        throw StateError('Active matching harvest plan required.');
      }
      final parcel = await one(
        tx,
        'land_parcels',
        farm,
        p['parcel_id'] as String,
      );
      final season = await one(
        tx,
        'production_seasons_v2',
        farm,
        p['season_id'] as String,
      );
      if (parcel['active'] != 1 ||
          parcel['kind'] != 'fieldPlot' ||
          season['active'] != 1 ||
          season['parcel_id'] != parcel['id']) {
        throw StateError('Harvest destination closed.');
      }
    } else {
      await catalog(tx, farm, d.partyId!, {
        d.kind == TradeKind.sale ? 'customer' : 'supplier',
      });
    }
    for (final l in d.lines) {
      if (d.kind == TradeKind.harvest || d.kind == TradeKind.purchase) {
        await catalog(tx, farm, l.ref, {
          d.kind == TradeKind.harvest ? 'product' : 'material',
        });
        await one(tx, 'inventory_items_v2', farm, l.ref);
      } else if (d.kind == TradeKind.sale) {
        final lot = await one(tx, 'trade_lots_v1', farm, l.ref);
        final harvest = await one(
          tx,
          'trade_documents_v1',
          farm,
          lot['harvest_id'] as String,
        );
        if (harvest['status'] != 'posted' ||
            lot['currency'] != d.currency ||
            (lot['day'] as String).compareTo(d.day) > 0 ||
            (posting && (lot['stock_units'] as int) < l.units)) {
          throw StateError('Lot/currency/quantity unavailable.');
        }
        await catalog(tx, farm, lot['item_id'] as String, {'product'});
      }
    }
  }

  @override
  Future<void> create(
    String farm,
    TradeDraft d,
    String actor,
  ) => database.transaction((tx) async {
    final old = await tx.query(
      'trade_documents_v1',
      where: 'id=?',
      whereArgs: [d.id],
    );
    if (old.isNotEmpty) {
      if (old.single['farm_id'] == farm &&
          old.single['body'] == jsonEncode(d.toJson())) {
        return;
      }
      throw StateError('Request identity conflict.');
    }
    await validateRefs(tx, farm, d);
    final month = d.day.substring(0, 7).replaceAll('-', '');
    await tx.rawInsert(
      'INSERT INTO trade_sequences_v1(farm_id,kind,month,value) VALUES(?,?,?,1) ON CONFLICT(farm_id,kind,month) DO UPDATE SET value=value+1',
      [farm, d.kind.name, month],
    );
    final counter =
        (await tx.query(
              'trade_sequences_v1',
              where: 'farm_id=? AND kind=? AND month=?',
              whereArgs: [farm, d.kind.name, month],
            )).single['value']
            as int;
    final prefix = {
      TradeKind.harvest: 'TH',
      TradeKind.sale: 'BH',
      TradeKind.purchase: 'MH',
      TradeKind.expense: 'CP',
    }[d.kind]!;
    final code = '$prefix-$month-${counter.toString().padLeft(3, '0')}';
    await tx.insert('trade_documents_v1', {
      'id': d.id,
      'farm_id': farm,
      'kind': d.kind.name,
      'code': code,
      'day': d.day,
      'party_id': d.partyId,
      'plan_id': d.planId,
      'currency': d.currency,
      'total': d.billed,
      'reference': d.reference.trim(),
      'body': jsonEncode(d.toJson()),
      'snapshot': '{}',
      'status': 'draft',
      'revision': 0,
    });
    await audit(tx, farm, d.id, 'create', actor);
  });
  Future<void> movement(
    Transaction tx,
    String farm,
    String doc,
    int index,
    String item,
    String quantity,
    String price,
    String currency,
    String day,
    String actor, {
    required bool receipt,
    String? lot,
    bool reversal = false,
  }) async {
    final units = TradeMath.units(quantity);
    final qty = ExactDecimal.quantityFromUnits(units);
    if (ExactDecimal.quantityUnits(qty) != units) {
      throw const FormatException('Quantity cannot round-trip exactly.');
    }
    final id = 'trade:$doc:$index:${reversal ? 'reverse' : 'post'}';
    await SqliteInventoryRepository(database).recordInTransaction(
      tx,
      InventoryMovement(
        id: id,
        farmId: farm,
        itemId: item,
        kind: receipt
            ? InventoryMovementKind.receipt
            : InventoryMovementKind.issue,
        quantity: qty,
        occurredAt: TradeMath.instant(day),
        unitPriceText: price,
        currency: currency,
        pricedBy: actor,
        zeroPriceConfirmed:
            ExactDecimal.parse(price).coefficient == BigInt.zero,
      ),
      finishedGoods: true,
    );
    await tx.insert('trade_stock_links_v1', {
      'movement_id': id,
      'document_id': doc,
      'farm_id': farm,
      'line_no': index,
      'lot_id': lot,
      'reversal': reversal ? 1 : 0,
    });
  }

  @override
  Future<void> post(
    String farm,
    String id,
    int revision,
    String actor,
  ) => database.transaction((tx) async {
    final row = await one(tx, 'trade_documents_v1', farm, id);
    if (row['status'] != 'draft' || row['revision'] != revision) {
      throw StateError('Stale or non-draft document.');
    }
    final d = TradeDraft.fromJson(decode(row['body']));
    postingDay(d.day);
    await validateRefs(tx, farm, d, posting: true);
    final snapshots = <String, dynamic>{'lines': <Map<String, dynamic>>[]};
    if (d.partyId != null) {
      final p = await one(tx, 'company_catalog_entries_v1', farm, d.partyId!);
      snapshots['partyName'] = p['name'];
      snapshots['partyCode'] = p['code'];
    }
    if (d.planId != null) {
      final p = await one(tx, 'production_plans_v1', farm, d.planId!);
      snapshots['planCode'] = p['code'];
      snapshots['parcelId'] = p['parcel_id'];
      snapshots['seasonId'] = p['season_id'];
    }
    final lineAmounts = TradeMath.lineAmounts(d);
    for (var i = 0; i < d.lines.length; i++) {
      final l = d.lines[i];
      if (d.kind == TradeKind.harvest) {
        final item = await one(tx, 'inventory_items_v2', farm, l.ref);
        final lot = '$id:$i';
        await tx.insert('trade_lots_v1', {
          'id': lot,
          'farm_id': farm,
          'harvest_id': id,
          'item_id': l.ref,
          'plan_id': d.planId,
          'day': d.day,
          'code': '${row['code']}-L${(i + 1).toString().padLeft(3, '0')}',
          'original_units': l.units,
          'stock_units': l.units,
          'price': l.price,
          'currency': d.currency,
          'item_name': item['name'],
          'unit': item['unit'],
        });
        await movement(
          tx,
          farm,
          id,
          i,
          l.ref,
          l.quantity,
          l.price,
          d.currency,
          d.day,
          actor,
          receipt: true,
          lot: lot,
        );
        (snapshots['lines'] as List).add({
          'name': item['name'],
          'unit': item['unit'],
          'itemId': l.ref,
          'lotId': lot,
          'cost': l.rawAmount,
        });
      } else if (d.kind == TradeKind.sale) {
        final lot = await one(tx, 'trade_lots_v1', farm, l.ref);
        final changed = await tx.rawUpdate(
          'UPDATE trade_lots_v1 SET stock_units=stock_units-? WHERE id=? AND farm_id=? AND stock_units>=?',
          [l.units, l.ref, farm, l.units],
        );
        if (changed != 1) throw StateError('Insufficient lot stock.');
        await movement(
          tx,
          farm,
          id,
          i,
          lot['item_id'] as String,
          l.quantity,
          l.issuePrice!,
          d.currency,
          d.day,
          actor,
          receipt: false,
          lot: l.ref,
        );
        (snapshots['lines'] as List).add({
          'name': lot['item_name'],
          'unit': lot['unit'],
          'itemId': lot['item_id'],
          'lotId': l.ref,
          'planId': lot['plan_id'],
          'cost':
              (ExactDecimal.parse(l.quantity) *
                      ExactDecimal.parse(l.issuePrice!))
                  .toString(),
        });
      } else if (d.kind == TradeKind.purchase) {
        final item = await one(tx, 'inventory_items_v2', farm, l.ref);
        await movement(
          tx,
          farm,
          id,
          i,
          l.ref,
          l.quantity,
          l.price,
          d.currency,
          d.day,
          actor,
          receipt: true,
        );
        (snapshots['lines'] as List).add({
          'name': item['name'],
          'unit': item['unit'],
          'itemId': l.ref,
          'cost': l.rawAmount,
        });
      } else {
        (snapshots['lines'] as List).add({
          'name': l.label,
          'cost': l.rawAmount,
        });
      }
    }
    for (var i = 0; i < d.lines.length; i++) {
      (snapshots['lines'] as List)[i]['billed'] = lineAmounts[i];
    }
    await tx.update(
      'trade_documents_v1',
      {
        'status': 'posted',
        'revision': revision + 1,
        'snapshot': jsonEncode(snapshots),
      },
      where: 'id=? AND farm_id=?',
      whereArgs: [id, farm],
    );
    await audit(tx, farm, id, 'post', actor);
  });
  @override
  Future<void> voidDocument(
    String farm,
    String id,
    int revision,
    String day,
    String reason,
    String actor,
  ) => database.transaction((tx) async {
    postingDay(day);
    TradeMath.requiredText(reason);
    final row = await one(tx, 'trade_documents_v1', farm, id);
    if (row['revision'] != revision || row['status'] == 'void') {
      throw StateError('Stale document.');
    }
    final d = TradeDraft.fromJson(decode(row['body']));
    if (day.compareTo(d.day) < 0) {
      throw const FormatException('Reversal precedes source.');
    }
    if (await paid(tx, id) != '0') {
      throw StateError('Reverse active payments first.');
    }
    if (row['status'] == 'posted') {
      for (var i = 0; i < d.lines.length; i++) {
        final l = d.lines[i];
        if (d.kind == TradeKind.harvest) {
          final lot = await one(tx, 'trade_lots_v1', farm, '$id:$i');
          if (lot['stock_units'] != lot['original_units']) {
            throw StateError('Harvest has consumed stock.');
          }
          await tx.update(
            'trade_lots_v1',
            {'stock_units': 0},
            where: 'id=?',
            whereArgs: ['$id:$i'],
          );
          await movement(
            tx,
            farm,
            id,
            i,
            l.ref,
            l.quantity,
            l.price,
            d.currency,
            day,
            actor,
            receipt: false,
            lot: '$id:$i',
            reversal: true,
          );
        } else if (d.kind == TradeKind.sale) {
          final lot = await one(tx, 'trade_lots_v1', farm, l.ref);
          final changed = await tx.rawUpdate(
            'UPDATE trade_lots_v1 SET stock_units=stock_units+? WHERE id=? AND farm_id=? AND stock_units+?<=original_units',
            [l.units, l.ref, farm, l.units],
          );
          if (changed != 1) throw StateError('Lot reversal overflow.');
          await movement(
            tx,
            farm,
            id,
            i,
            lot['item_id'] as String,
            l.quantity,
            l.issuePrice!,
            d.currency,
            day,
            actor,
            receipt: true,
            lot: l.ref,
            reversal: true,
          );
        } else if (d.kind == TradeKind.purchase) {
          final consumed = await tx.query(
            'inventory_movements_v2',
            columns: ['id'],
            where:
                "farm_id=? AND item_id=? AND kind='issue' AND occurred_at>=?",
            whereArgs: [
              farm,
              l.ref,
              TradeMath.instant(d.day).toIso8601String(),
            ],
            limit: 1,
          );
          if (consumed.isNotEmpty) {
            throw StateError(
              'Purchased item has subsequent issues; use a separate correction workflow.',
            );
          }
          await movement(
            tx,
            farm,
            id,
            i,
            l.ref,
            l.quantity,
            l.price,
            d.currency,
            day,
            actor,
            receipt: false,
            reversal: true,
          );
        }
      }
    }
    await tx.update(
      'trade_documents_v1',
      {'status': 'void', 'revision': revision + 1, 'void_day': day},
      where: 'id=? AND farm_id=?',
      whereArgs: [id, farm],
    );
    await audit(tx, farm, id, 'void', actor, reason);
  });
  static Future<String> cash(
    Transaction tx, {
    required String id,
    required String farm,
    required bool receipt,
    required String amount,
    required String currency,
    required String day,
    required String description,
  }) async {
    final money = TradeMath.money(amount, positive: true);
    return SqliteMonthlyDocumentSequence().saveWithCode(
      transaction: tx,
      organizationId: farm,
      kind: receipt
          ? BusinessDocumentKind.receipt
          : BusinessDocumentKind.payment,
      documentDate: DateTime.parse(day),
      save: (code) async {
        await tx.insert('finance_documents_v2', {
          'id': id,
          'organization_id': farm,
          'code': code,
          'kind': receipt ? 'THU' : 'CHI',
          'occurred_at': DateTime.parse(day).toIso8601String(),
          'amount_minor': money,
          'currency': currency,
          'category': 'TRADE_SETTLEMENT',
          'description': description,
        });
        return code;
      },
    );
  }

  @override
  Future<void> settle(
    String farm,
    String id,
    String documentId,
    String amount,
    String currency,
    String day,
    String reference,
    String actor,
  ) => database.transaction((tx) async {
    TradeMath.requiredText(id);
    TradeMath.requiredText(reference);
    postingDay(day);
    TradeMath.money(amount, positive: true);
    final existing = await tx.query(
      'trade_settlements_v1',
      where: 'id=?',
      whereArgs: [id],
    );
    if (existing.isNotEmpty) {
      final r = existing.single;
      if (r['farm_id'] == farm &&
          r['document_id'] == documentId &&
          r['amount'] == amount &&
          r['currency'] == currency &&
          r['day'] == day &&
          r['reference'] == reference.trim()) {
        return;
      }
      throw StateError('Payment request identity conflict.');
    }
    final duplicates = await tx.rawQuery(
      'SELECT s.id FROM trade_settlements_v1 s LEFT JOIN trade_reversals_v1 r ON r.payment_id=s.id WHERE s.farm_id=? AND s.document_id=? AND s.reference=? AND r.id IS NULL',
      [farm, documentId, reference.trim()],
    );
    if (duplicates.isNotEmpty) {
      throw StateError(
        'This source document already has an active settlement with this reference.',
      );
    }
    final row = await one(tx, 'trade_documents_v1', farm, documentId);
    if (row['status'] != 'posted' ||
        row['kind'] == 'harvest' ||
        row['currency'] != currency ||
        day.compareTo(row['day'] as String) < 0) {
      throw StateError('Invalid settlement source/date/currency.');
    }
    final balance = TradeMath.subtract(
      row['total'] as String,
      await paid(tx, documentId),
    );
    if (ExactDecimal.parse(amount).compareTo(ExactDecimal.parse(balance)) > 0) {
      throw StateError('Overpayment.');
    }
    final finance = 'trade-payment:$id';
    await cash(
      tx,
      id: finance,
      farm: farm,
      receipt: row['kind'] == 'sale',
      amount: amount,
      currency: currency,
      day: day,
      description: '${row['code']} · $reference',
    );
    await tx.insert('trade_settlements_v1', {
      'id': id,
      'farm_id': farm,
      'document_id': documentId,
      'finance_id': finance,
      'amount': amount,
      'currency': currency,
      'day': day,
      'reference': reference.trim(),
    });
    await audit(tx, farm, id, 'settle', actor);
  });
  @override
  Future<void> reversePayment(
    String farm,
    String paymentId,
    String reversalId,
    String day,
    String reason,
    String actor,
  ) => database.transaction((tx) async {
    postingDay(day);
    TradeMath.requiredText(reason);
    TradeMath.requiredText(reversalId);
    final p = await one(tx, 'trade_settlements_v1', farm, paymentId);
    final existing = await tx.query(
      'trade_reversals_v1',
      where: 'payment_id=? OR id=?',
      whereArgs: [paymentId, reversalId],
    );
    if (existing.isNotEmpty) {
      final r = existing.single;
      if (r['farm_id'] == farm &&
          r['id'] == reversalId &&
          r['payment_id'] == paymentId &&
          r['day'] == day &&
          r['reason'] == reason) {
        return;
      }
      throw StateError('Already reversed or identity conflict.');
    }
    if (day.compareTo(p['day'] as String) < 0) {
      throw const FormatException('Reversal precedes payment.');
    }
    final doc = await one(
      tx,
      'trade_documents_v1',
      farm,
      p['document_id'] as String,
    );
    final finance = 'trade-reversal:$reversalId';
    await cash(
      tx,
      id: finance,
      farm: farm,
      receipt: doc['kind'] != 'sale',
      amount: p['amount'] as String,
      currency: p['currency'] as String,
      day: day,
      description: 'Reverse ${p['finance_id']} · $reason',
    );
    await tx.insert('trade_reversals_v1', {
      'id': reversalId,
      'payment_id': paymentId,
      'farm_id': farm,
      'finance_id': finance,
      'day': day,
      'reason': reason,
    });
    await audit(tx, farm, reversalId, 'payment.reverse', actor, reason);
  });
  @override
  Future<List<TradeRecord>> documents(String farm) async {
    final rows = await database.query(
      'trade_documents_v1',
      where: 'farm_id=?',
      whereArgs: [farm],
      orderBy: 'day DESC,code DESC',
    );
    return [
      for (final r in rows)
        TradeRecord(
          TradeDraft.fromJson(decode(r['body'])),
          r['code'] as String,
          r['status'] as String,
          r['revision'] as int,
          decode(r['snapshot']),
          await paid(database, r['id'] as String),
        ),
    ];
  }

  @override
  Future<List<FinishedLot>> lots(String farm) async =>
      (await database.rawQuery(
            "SELECT l.* FROM trade_lots_v1 l JOIN trade_documents_v1 d ON d.id=l.harvest_id AND d.farm_id=l.farm_id WHERE l.farm_id=? AND d.status='posted' ORDER BY l.day,l.code",
            [farm],
          ))
          .map(
            (r) => FinishedLot(
              id: r['id'] as String,
              farm: farm,
              itemId: r['item_id'] as String,
              planId: r['plan_id'] as String,
              harvestId: r['harvest_id'] as String,
              day: r['day'] as String,
              originalUnits: r['original_units'] as int,
              stockUnits: r['stock_units'] as int,
              price: r['price'] as String,
              currency: r['currency'] as String,
              code: r['code'] as String,
              itemName: r['item_name'] as String,
              unit: r['unit'] as String,
            ),
          )
          .toList();
  @override
  Future<List<TradePayment>> payments(String farm) async =>
      (await database.rawQuery(
            'SELECT p.*,f.code,r.id AS reversed FROM trade_settlements_v1 p JOIN finance_documents_v2 f ON f.id=p.finance_id LEFT JOIN trade_reversals_v1 r ON r.payment_id=p.id WHERE p.farm_id=? ORDER BY p.day DESC,p.id',
            [farm],
          ))
          .map(
            (r) => TradePayment(
              id: r['id'] as String,
              documentId: r['document_id'] as String,
              financeId: r['finance_id'] as String,
              amount: r['amount'] as String,
              day: r['day'] as String,
              reference: r['reference'] as String,
              currency: r['currency'] as String,
              reversed: r['reversed'] != null,
              financeCode: r['code'] as String,
            ),
          )
          .toList();
  @override
  Future<List<Map<String, Object?>>> cashBook(String farm) => database.query(
    'finance_documents_v2',
    where: 'organization_id=?',
    whereArgs: [farm],
    orderBy: 'occurred_at DESC,code DESC',
  );
  @override
  Future<List<Map<String, Object?>>> choices(String farm, String kind) async {
    if (kind == 'plan') {
      return database.query(
        'production_plans_v1',
        where: "farm_id=? AND status='active'",
        whereArgs: [farm],
        orderBy: 'code',
      );
    }
    if (!{'customer', 'supplier', 'product', 'material'}.contains(kind)) {
      throw const FormatException('Invalid choice type.');
    }
    return database.query(
      'company_catalog_entries_v1',
      where: 'farm_id=? AND kind=? AND active=1',
      whereArgs: [farm, kind],
      orderBy: 'code',
    );
  }
}
