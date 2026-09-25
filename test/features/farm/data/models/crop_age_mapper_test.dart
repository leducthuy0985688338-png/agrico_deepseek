import 'package:agrico_deepseek/features/farm/data/models/land_survey_mapper.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crop age survives JSON and older records remain without an age', () {
    final recordedAt = DateTime.utc(2026, 9, 25);
    final crop = CropRecord(
      id: 'crop-1',
      parcelId: 'parcel-1',
      cropType: 'ຢາງພາລາ',
      quantity: 12,
      unit: 'plants',
      ageMonths: 30,
      condition: CropCondition.healthy,
      active: true,
      createdAt: recordedAt,
      createdBy: 'member-1',
      updatedAt: recordedAt,
      updatedBy: 'member-1',
    );
    final json = LandSurveyMapper.cropToJson(crop);
    expect(LandSurveyMapper.cropFromJson(json).ageMonths, 30);
    json.remove('ageMonths');
    expect(LandSurveyMapper.cropFromJson(json).ageMonths, isNull);
  });
}
