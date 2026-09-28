import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/parcel_work_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('records clearing with a machine and shows persisted event',
      (tester) async {
    final repository = _WorkRepository();
    repository.savedResources.add(const WorkResource(
      id: 'm1', farmId: 'farm-1', kind: WorkResourceKind.machine,
      code: 'M001', name: 'Máy khai hoang',
    ));
    const subject = AuthorizationSubject(
      userId: 'user', membershipId: 'actor', farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView, PermissionCodes.fieldEdit},
      dataScopes: {DataScope.allFarm},
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: ParcelWorkScreen(parcelId: 'parcel-1', subject: subject,
        service: ParcelWorkService(repository)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-add-event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Dọn thực bì');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final machine = find.byType(CheckboxListTile);
    await tester.ensureVisible(machine);
    await tester.tap(machine);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-save-event')));
    await tester.pumpAndSettle();
    expect(repository.savedEvents, hasLength(1));
    expect(repository.savedEvents.single.phase, ParcelWorkPhase.clearing);
    expect(repository.savedEvents.single.machineIds, ['m1']);
    expect(repository.savedEvents.single.description, 'Dọn thực bì');
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dọn thực bì'), findsOneWidget);
  });
}

class _WorkRepository implements ParcelWorkRepository {
  final savedResources = <WorkResource>[];
  final savedEvents = <ParcelWorkEvent>[];
  @override
  Future<void> register(WorkResource resource) async {
    savedResources.add(resource);
  }
  @override
  Future<List<WorkResource>> resources(String farmId) async =>
      savedResources.where((r) => r.farmId == farmId).toList();
  @override
  Future<void> record(ParcelWorkEvent event) async {
    savedEvents.add(event);
  }
  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async =>
      savedEvents.where((e) =>
          e.farmId == farmId && e.parcelId == parcelId).toList();
}
