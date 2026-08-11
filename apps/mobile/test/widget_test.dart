import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme.dart';

void main() {
  test('status colors map correctly', () {
    expect(AppTheme.statusColor('Riding'), AppTheme.riding);
    expect(AppTheme.statusColor('Emergency'), AppTheme.emergency);
    expect(AppTheme.statusColor('FuelNeeded'), AppTheme.fuel);
  });
}
