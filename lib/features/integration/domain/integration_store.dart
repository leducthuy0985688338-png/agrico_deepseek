import 'integration_snapshot.dart';
import '../../trade/domain/trade.dart' show MoneyRounding;

abstract interface class IntegrationStore {
  Future<IntegrationSnapshot> snapshot(String farm, String period);
  Future<List<String>> reconcile(String farm);
  Future<void> linkSalary(
    String farm,
    String id,
    String actorId, {
    String? existingFinanceId,
  });
  Future<void> reverseSalary(
    String farm,
    String payment,
    String id,
    String day,
    String reason,
    String actorId,
  );
  Future<void> machinePayable(
    String farm,
    String expense,
    String supplier,
    String reference,
    MoneyRounding rounding,
    String actorId, {
    String? existingDocumentId,
  });
  Future<void> fuelIssue(
    String farm,
    String expense,
    String item,
    String price,
    bool zero,
    String actorId, {
    String? existingMovementId,
  });
  Future<void> reverseFuel(
    String farm,
    String expense,
    String day,
    String reason,
    String actorId,
  );
  Future<void> metadata(
    String farm,
    String kind,
    String id,
    int revision,
    Map<String, String> values,
    String actorId,
  );
}
