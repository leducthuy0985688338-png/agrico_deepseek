import 'package:sqflite/sqflite.dart';
import '../domain/trade.dart';
import 'sqlite_trade_repository.dart';

abstract final class TradeIntegrity {
  static Future<void> validate(DatabaseExecutor db) async {
    void require(bool condition) {
      if (!condition) throw StateError('Trade backup integrity failure.');
    }

    final rows = await db.query('trade_documents_v1');
    final docs = {for (final r in rows) r['id']: r};
    final lots = {for (final r in await db.query('trade_lots_v1')) r['id']: r};
    final stock = await db.query('trade_stock_links_v1');
    final payments = await db.query('trade_settlements_v1');
    final reversals = await db.query('trade_reversals_v1');
    final finance = {
      for (final r in await db.query('finance_documents_v2')) r['id']: r,
    };
    final inventory = {
      for (final r in await db.query('inventory_movements_v2')) r['id']: r,
    };
    final lotSold = <Object?, int>{};
    for (final r in rows) {
      final d = TradeDraft.fromJson(SqliteTradeRepository.decode(r['body']));
      d.validate();
      final farm = r['farm_id'] as String;
      final snap = SqliteTradeRepository.decode(r['snapshot']);
      require(
        d.id == r['id'] &&
            d.kind.name == r['kind'] &&
            d.day == r['day'] &&
            d.currency == r['currency'] &&
            d.billed == r['total'] &&
            d.planId == r['plan_id'] &&
            d.partyId == r['party_id'] &&
            d.reference.trim() == r['reference'],
      );
      final prefix = {
        TradeKind.harvest: 'TH',
        TradeKind.sale: 'BH',
        TradeKind.purchase: 'MH',
        TradeKind.expense: 'CP',
      }[d.kind]!;
      final month = d.day.substring(0, 7).replaceAll('-', '');
      final match = RegExp(
        '^$prefix-$month-([0-9]{3,})\$',
      ).firstMatch(r['code'] as String);
      require(match != null);
      final number = int.parse(match!.group(1)!);
      require(number > 0);
      final counter = await db.query(
        'trade_sequences_v1',
        where: 'farm_id=? AND kind=? AND month=?',
        whereArgs: [farm, d.kind.name, month],
      );
      require(
        counter.length == 1 && (counter.single['value'] as int) >= number,
      );
      if (d.partyId != null) {
        await SqliteTradeRepository.catalog(db, farm, d.partyId!, {
          d.kind == TradeKind.sale ? 'customer' : 'supplier',
        }, active: false);
      }
      if (d.planId != null) {
        final p = await SqliteTradeRepository.one(
          db,
          'production_plans_v1',
          farm,
          d.planId!,
        );
        require(
          p['currency'] == d.currency &&
              d.day.compareTo(p['starts_on'] as String) >= 0 &&
              d.day.compareTo(p['ends_on'] as String) <= 0,
        );
      }
      final posted = snap.containsKey('lines');
      if (r['status'] == 'posted') require(posted);
      if (r['status'] == 'draft') require(!posted);
      if (r['status'] == 'void') {
        TradeMath.date(r['void_day'] as String);
        require((r['void_day'] as String).compareTo(d.day) >= 0);
      }
      if (posted) {
        final lines = snap['lines'] as List;
        require(lines.length == d.lines.length);
        final billed = TradeMath.lineAmounts(d);
        if (d.partyId != null) {
          require(
            (snap['partyName'] as String).isNotEmpty &&
                (snap['partyCode'] as String).isNotEmpty,
          );
        }
        for (var i = 0; i < lines.length; i++) {
          final detail = lines[i] as Map;
          final l = d.lines[i];
          require(
            detail['billed'] == billed[i] &&
                (detail['name'] as String).isNotEmpty,
          );
          if (d.kind == TradeKind.expense) {
            require(detail['cost'] == l.rawAmount);
            continue;
          }
          Map<String, Object?>? lot;
          if (d.kind == TradeKind.harvest) {
            lot = lots['${d.id}:$i'];
            require(
              lot != null &&
                  lot['harvest_id'] == d.id &&
                  lot['farm_id'] == farm &&
                  lot['item_id'] == l.ref &&
                  lot['original_units'] == l.units &&
                  lot['price'] == l.price &&
                  lot['currency'] == d.currency &&
                  lot['plan_id'] == d.planId &&
                  lot['day'] == d.day,
            );
          } else if (d.kind == TradeKind.sale) {
            lot = lots[l.ref];
            require(
              lot != null &&
                  lot['farm_id'] == farm &&
                  lot['currency'] == d.currency &&
                  (lot['day'] as String).compareTo(d.day) <= 0,
            );
            require(detail['planId'] == lot!['plan_id']);
            if (r['status'] == 'posted') {
              lotSold.update(
                l.ref,
                (v) => v + l.units,
                ifAbsent: () => l.units,
              );
            }
          }
          final item = lot == null ? l.ref : lot['item_id'] as String;
          await SqliteTradeRepository.catalog(db, farm, item, {
            d.kind == TradeKind.purchase ? 'material' : 'product',
          }, active: false);
          require(detail['itemId'] == item);
          final price = d.kind == TradeKind.sale ? l.issuePrice! : l.price;
          require(
            detail['cost'] ==
                (ExactDecimal.parse(l.quantity) * ExactDecimal.parse(price))
                    .toString(),
          );
          if (lot != null) require(detail['lotId'] == lot['id']);
          final links = stock
              .where((s) => s['document_id'] == d.id && s['line_no'] == i)
              .toList();
          require(links.length == (r['status'] == 'void' ? 2 : 1));
          for (final link in links) {
            final reversal = link['reversal'] == 1;
            final m = inventory[link['movement_id']];
            require(m != null);
            final receipt = (d.kind != TradeKind.sale) != reversal;
            require(
              link['farm_id'] == farm &&
                  link['lot_id'] == lot?['id'] &&
                  m!['farm_id'] == farm &&
                  m['item_id'] == item &&
                  m['kind'] == (receipt ? 'receipt' : 'issue') &&
                  m['quantity_units'] == l.units &&
                  m['unit_price_text'] == price &&
                  m['currency'] == d.currency &&
                  m['amount_text'] == detail['cost'],
            );
            require(
              m!['occurred_at'] ==
                  TradeMath.instant(
                    reversal ? r['void_day'] as String : d.day,
                  ).toIso8601String(),
            );
          }
        }
      } else {
        require(stock.where((s) => s['document_id'] == d.id).isEmpty);
      }
      final paid = await SqliteTradeRepository.paid(db, d.id);
      require(
        ExactDecimal.parse(paid).compareTo(ExactDecimal.parse(d.billed)) <= 0,
      );
      if (r['status'] != 'posted' || d.kind == TradeKind.harvest) {
        require(paid == '0');
      }
    }
    for (final l in lots.values) {
      final h = docs[l['harvest_id']];
      require(
        h != null &&
            h['kind'] == 'harvest' &&
            h['farm_id'] == l['farm_id'] &&
            h['status'] != 'draft',
      );
      final expected = h!['status'] == 'void'
          ? 0
          : (l['original_units'] as int) - (lotSold[l['id']] ?? 0);
      require(expected >= 0 && l['stock_units'] == expected);
    }
    // Finished-goods stock can only originate in referenced harvest/sale movements.
    final products = await db.query(
      'company_catalog_entries_v1',
      where: "kind='product'",
    );
    for (final p in products) {
      final item = await SqliteTradeRepository.one(
        db,
        'inventory_items_v2',
        p['farm_id'] as String,
        p['id'] as String,
      );
      final expected = lots.values
          .where((l) => l['item_id'] == p['id'])
          .fold<int>(0, (s, l) => s + (l['stock_units'] as int));
      require(item['stock_units'] == expected);
      for (final m in inventory.values.where((m) => m['item_id'] == p['id'])) {
        require(stock.any((s) => s['movement_id'] == m['id']));
      }
    }
    for (final link in stock) {
      require(
        docs.containsKey(link['document_id']) &&
            inventory.containsKey(link['movement_id']),
      );
    }
    for (final m in inventory.values.where(
      (m) => (m['id'] as String).startsWith('trade:'),
    )) {
      require(stock.any((s) => s['movement_id'] == m['id']));
    }
    final financeIds = <Object?>{};
    for (final p in payments) {
      TradeMath.money(p['amount'] as String, positive: true);
      TradeMath.date(p['day'] as String);
      TradeMath.requiredText(p['reference'] as String);
      final d = docs[p['document_id']];
      final f = finance[p['finance_id']];
      require(d != null && f != null);
      require(
        d!['farm_id'] == p['farm_id'] &&
            d['kind'] != 'harvest' &&
            d['currency'] == p['currency'] &&
            (p['day'] as String).compareTo(d['day'] as String) >= 0,
      );
      require(
        f!['organization_id'] == p['farm_id'] &&
            f['kind'] == (d['kind'] == 'sale' ? 'THU' : 'CHI') &&
            f['currency'] == p['currency'] &&
            f['amount_minor'] == int.parse(p['amount'] as String) &&
            f['occurred_at'] ==
                DateTime.parse(p['day'] as String).toIso8601String(),
      );
      financeIds.add(p['finance_id']);
    }
    for (final r in reversals) {
      final matches = payments
          .where((p) => p['id'] == r['payment_id'])
          .toList();
      require(matches.length == 1);
      final p = matches.single;
      final original = finance[p['finance_id']]!;
      final f = finance[r['finance_id']];
      require(f != null);
      require(
        r['farm_id'] == p['farm_id'] &&
            (r['day'] as String).compareTo(p['day'] as String) >= 0,
      );
      TradeMath.requiredText(r['reason'] as String);
      TradeMath.date(r['day'] as String);
      require(
        f!['organization_id'] == p['farm_id'] &&
            f['kind'] != (original['kind']) &&
            f['currency'] == p['currency'] &&
            f['amount_minor'] == original['amount_minor'] &&
            f['occurred_at'] ==
                DateTime.parse(r['day'] as String).toIso8601String(),
      );
      financeIds.add(r['finance_id']);
    }
    for (final f in finance.values.where(
      (f) =>
          (f['id'] as String).startsWith('trade-payment:') ||
          (f['id'] as String).startsWith('trade-reversal:'),
    )) {
      require(financeIds.contains(f['id']));
    }
  }
}
