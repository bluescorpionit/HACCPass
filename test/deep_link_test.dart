import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/deep_links.dart';

/// Parser dei collegamenti profondi (Prompt 9): schema attuale
/// haccpass:// e schema storico bluehaccp:// entrambi validi.
void main() {
  test('schema attuale haccpass://equipment/<id>', () {
    expect(parseEquipmentDeepLink('haccpass://equipment/12'), 12);
  });

  test('schema storico bluehaccp:// resta valido (QR già stampati)', () {
    expect(parseEquipmentDeepLink('bluehaccp://equipment/3'), 3);
  });

  test('scheme e host errati: null', () {
    expect(parseEquipmentDeepLink('https://equipment/12'), isNull);
    expect(parseEquipmentDeepLink('haccpass://attrezzatura/12'), isNull);
    expect(parseEquipmentDeepLink('haccpass://equipment/abc'), isNull);
    expect(parseEquipmentDeepLink('haccpass://equipment/0'), isNull);
    expect(parseEquipmentDeepLink('haccpass://equipment/-4'), isNull);
    expect(parseEquipmentDeepLink(''), isNull);
    expect(parseEquipmentDeepLink(null), isNull);
  });
}
