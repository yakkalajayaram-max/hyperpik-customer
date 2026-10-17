import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_customer/core/place.dart';

void main() {
  test('distances read as metres up close and kilometres further out', () {
    expect(Place.readableDistance(52), '50 m');
    expect(Place.readableDistance(318), '320 m');
    // Rounded before the unit is chosen: never "1000 m".
    expect(Place.readableDistance(994), '990 m');
    expect(Place.readableDistance(996), '1.0 km');
    expect(Place.readableDistance(1240), '1.2 km');
  });

  test('the thresholds are 50 m (at the address) and 1 km (use the phone position instead)', () {
    expect(Place.atAddressMetres, 50);
    expect(Place.nearAddressMetres, 1000);
  });
}
