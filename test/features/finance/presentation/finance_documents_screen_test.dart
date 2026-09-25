import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('saved payment shows its generated code after reopening', (tester) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteFinanceDocumentRepository.createSchema(db);
    final repository = SqliteFinanceDocumentRepository(db);

    Widget app() => MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: FinanceDocumentsScreen(
        repository: repository,
        organizationId: 'farm-a',
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Chưa có dữ liệu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finance-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('finance-category')), 'ຂາຍມັນຕົ້ນ');
    await tester.enterText(find.byKey(const Key('finance-amount')), '25000');
    await tester.tap(find.byKey(const Key('finance-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('CHI-'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('CHI-'), findsWidgets);
    expect((await repository.listByOrganization('farm-a')).single.category, 'ຂາຍມັນຕົ້ນ');
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
