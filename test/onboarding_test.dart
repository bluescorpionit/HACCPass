import 'package:flutter_test/flutter_test.dart';

import 'package:blue_haccp/core/constants/business_templates.dart';
import 'package:blue_haccp/services/onboarding/onboarding_controller.dart';

void main() {
  // Costruisce una P.IVA valida calcolando la cifra di controllo come
  // da algoritmo ufficiale (Luhn-like).
  String vatWithCheck(String firstTenDigits) {
    assert(firstTenDigits.length == 10);
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final d = int.parse(firstTenDigits[i]);
      if (i.isEven) {
        sum += d;
      } else {
        final doubled = d * 2;
        sum += doubled > 9 ? doubled - 9 : doubled;
      }
    }
    final check = (10 - (sum % 10)) % 10;
    return '$firstTenDigits$check';
  }

  group('Validazione Partita IVA', () {
    test('P.IVA con checksum corretto accettata', () {
      final vat = vatWithCheck('0123456789');
      expect(isValidItalianVat(vat), isTrue);
    });

    test('lunghezza errata rifiutata', () {
      expect(isValidItalianVat('12345'), isFalse);
      expect(isValidItalianVat('123456789012'), isFalse);
      expect(isValidItalianVat('ABCDEFGHIJK'), isFalse);
      expect(isValidItalianVat(''), isFalse);
    });

    test('cifra di controllo errata rifiutata', () {
      final vat = vatWithCheck('0123456789');
      final wrong = vat.substring(0, 10) +
          (vat[10] == '9' ? '0' : (int.parse(vat[10]) + 1).toString());
      expect(isValidItalianVat(wrong), isFalse);
    });

    test('numeri notoriamente errati rifiutati', () {
      expect(isValidItalianVat('00743160584'), isFalse);
    });
  });

  group('Modelli per tipo di attivit\u00E0', () {
    test('un modello per ogni tipo dichiarato', () {
      expect(templates.length, greaterThanOrEqualTo(11));
      expect(templates.map((t) => t.key).toSet().length, templates.length);
    });

    test('ogni modello ha ATECO e attrezzature coerenti', () {
      for (final template in templates) {
        expect(template.ateco, isNotEmpty);
        for (final equipment in template.equipment) {
          expect(equipment.minTemp, lessThanOrEqualTo(equipment.maxTemp));
        }
      }
    });

    test('merge senza duplicati', () {
      final bar = BusinessTemplate.byKey('bar');
      final pizzeria = BusinessTemplate.byKey('pizzeria');
      final merged = mergeEquipment([bar, pizzeria]);
      expect(
        merged.length,
        lessThan(bar.equipment.length + pizzeria.equipment.length),
        reason: 'congelatore comune deduplicato',
      );
      final keys = merged.map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('prodotti con allergeni indicativi', () {
      final bar = BusinessTemplate.byKey('bar');
      final brioche = bar.products.firstWhere((p) => p.key == 'brioche');
      expect(brioche.allergens, containsAll(['gluten', 'eggs', 'milk']));
    });
  });
}
