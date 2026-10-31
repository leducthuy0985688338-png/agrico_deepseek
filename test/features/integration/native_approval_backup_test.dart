import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import '../../support/approval_b_test_support.dart';

void main() {
  sqfliteFfiInit();
  test(
    'real native B posting survives snapshot and startup restore with guards and live authority',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'agrico-native-b-',
      );
      final path = '${directory.path}/agrico.db';
      var db = await databaseFactoryFfi.openDatabase(path);
      final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db',
      );
      final authority = SyntheticApprovalAuthority()..partyUsers['vendor'] = {};
      var live = approvalUser('maker');
      NativeApprovalRepository flow() => NativeApprovalRepository(
        SqliteApprovalPolicyStore(
          db,
          opened: live,
          currentSubject: () => live,
          authority: authority,
        ),
      );
      try {
        await costs.execute('CREATE TABLE test_costs(id TEXT PRIMARY KEY)');
        await SqliteCompanyCatalog.createSchema(db);
        await db.insert('company_catalog_entries_v1', {
          'id': 'vendor',
          'farm_id': 'f',
          'kind': 'supplier',
          'code': 'TEST',
          'name': 'Synthetic supplier',
          'name_key': 'synthetic supplier',
          'active': 1,
          'revision': 1,
        });
        await SqliteFinanceDocumentRepository.createSchema(db);
        await SqliteDocumentApproval.createSchema(db);
        await syntheticPolicy(db, authority, ApprovalKind.cashPayment, 'VND');
        await NativeApprovalGuard.install(db);
        await FinanceDocumentService(
          repository: SqliteFinanceDocumentRepository(db),
          subject: live,
          currentSubject: () => live,
        ).create(
          id: 'original',
          organizationId: 'f',
          kind: BusinessDocumentKind.payment,
          occurredAt: DateTime(2026, 10, 20),
          amountMinor: 123,
          currency: 'VND',
          category: 'TEST',
          beneficiaryPartyId: 'vendor',
        );
        const ref = NativeApprovalRef(NativeApprovalType.finance, 'original');
        await flow().submit(ref);
        live = approvalUser('reviewer');
        expect(
          (await flow().approve(ref, 'Independent native posting')).allowed,
          isTrue,
        );
        final snapshot = await LocalDatabaseSnapshot.create(
          db,
          costsDatabase: costs,
        );
        final decoded = LocalDatabaseSnapshot.decodeDatabases(snapshot);
        expect(
          (decoded['agrico.db']!['tables'] as Map).containsKey(
            NativeApprovalGuard.lease,
          ),
          isFalse,
        );
        await db.close();
        await costs.close();
        final activation = LocalRestoreActivation(
          directory,
          databaseFactoryFfi,
        );
        await activation.schedule(snapshot);
        expect(await activation.applyPending(), isTrue);
        db = await databaseFactoryFfi.openDatabase(path);
        expect(await NativeApprovalGuard.enabled(db), isTrue);
        await NativeApprovalGuard.validate(db);
        await SqliteDocumentApproval.validate(db);
        expect(
          (await db.query(
            SqliteFinanceDocumentRepository.table,
          )).single['amount_minor'],
          123,
        );
        await expectLater(
          db.delete(SqliteFinanceDocumentRepository.table),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await flow().approve(ref, 'Retry after restore')).allowed,
          isTrue,
        );
        expect(
          (await db.query(SqliteFinanceDocumentRepository.table)).length,
          1,
        );
        authority.current = false;
        expect(
          await SqliteApprovalPolicyStore(
            db,
            opened: live,
            currentSubject: () => live,
            authority: authority,
          ).effective(db, 'f', ApprovalKind.cashPayment, 'VND'),
          isNull,
        );
      } finally {
        if (db.isOpen) await db.close();
        if (costs.isOpen) await costs.close();
        // Preserve this newly generated synthetic restore evidence for inspection.
      }
    },
  );
}
