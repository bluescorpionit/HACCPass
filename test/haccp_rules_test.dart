import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/constants/haccp_rules.dart';
import 'package:haccpass/models/haccp_models.dart';

void main() {
  group('CleaningTask.state', () {
    CleaningTask task(
      String freqCode, {
      DateTime? lastCompletedAt,
      int todayDoneCount = 0,
    }) =>
        CleaningTask(
          id: 1,
          area: 'Cucina',
          title: 'Piani di lavoro',
          frequency: 'Giornaliera',
          freqCode: freqCode,
          lastCompletedAt: lastCompletedAt,
          todayDoneCount: todayDoneCount,
        );

    test('giornaliera senza esecuzioni oggi: da fare', () {
      expect(task('daily').state, CleaningState.dueToday);
    });

    test('giornaliera con una esecuzione oggi: fatto', () {
      expect(
        task('daily', todayDoneCount: 1).state,
        CleaningState.done,
      );
    });

    test('2 volte al giorno con una sola esecuzione: ancora da fare', () {
      expect(
        task('twice_daily', todayDoneCount: 1).state,
        CleaningState.dueToday,
      );
      expect(
        task('twice_daily', todayDoneCount: 2).state,
        CleaningState.done,
      );
    });

    test('dopo ogni utilizzo conta una volta al giorno', () {
      expect(
        task('after_use', todayDoneCount: 1).state,
        CleaningState.done,
      );
    });

    test('settimanale mai eseguita: scaduta', () {
      expect(task('weekly').state, CleaningState.overdue);
    });

    test('settimanale eseguita ieri: futura', () {
      expect(
        task('weekly', lastCompletedAt: DateTime.now().subtract(const Duration(days: 1))).state,
        CleaningState.upcoming,
      );
    });

    test('settimanale eseguita 7 giorni fa: scaduta', () {
      expect(
        task('weekly', lastCompletedAt: DateTime.now().subtract(const Duration(days: 8))).state,
        CleaningState.overdue,
      );
    });

    test('mappatura frequenze legacy v1', () {
      expect(
        CleaningFrequency.fromLegacyLabel('Dopo ogni utilizzo'),
        CleaningFrequency.afterUse,
      );
      expect(
        CleaningFrequency.fromLegacyLabel('2 volte al giorno'),
        CleaningFrequency.twiceDaily,
      );
      expect(
        CleaningFrequency.fromLegacyLabel('Settimanale'),
        CleaningFrequency.weekly,
      );
      expect(
        CleaningFrequency.fromLegacyLabel('Pulizia completa ogni 6 mesi'),
        CleaningFrequency.semiannual,
      );
    });
  });

  group('Livelli infestanti', () {
    test('roditori: 0 accettabile, 1 o più notevole', () {
      expect(pestLevelForRodents(0), PestLevel.acceptable);
      expect(pestLevelForRodents(1), PestLevel.severe);
      expect(pestLevelForRodents(5), PestLevel.severe);
    });

    test('striscianti: 0-3 accettabile, 4-7 modesto, 8+ notevole', () {
      expect(pestLevelForCrawlers(0), PestLevel.acceptable);
      expect(pestLevelForCrawlers(3), PestLevel.acceptable);
      expect(pestLevelForCrawlers(4), PestLevel.moderate);
      expect(pestLevelForCrawlers(7), PestLevel.moderate);
      expect(pestLevelForCrawlers(8), PestLevel.severe);
    });

    test('volanti: <=20 accettabile, 21-30 modesto, 31+ notevole', () {
      expect(pestLevelForFlyers(20), PestLevel.acceptable);
      expect(pestLevelForFlyers(21), PestLevel.moderate);
      expect(pestLevelForFlyers(30), PestLevel.moderate);
      expect(pestLevelForFlyers(31), PestLevel.severe);
    });
  });

  group('Conformità temperature per categoria merce', () {
    Receipt receipt(String code, double temp) => Receipt(
          id: 0,
          receivedAt: DateTime.now(),
          supplierId: 1,
          product: 'Test',
          category: code,
          temperature: temp,
        );

    test('latticini 0/+4', () {
      expect(receipt('dairy', 3).isTempCompliant, isTrue);
      expect(receipt('dairy', 6).isTempCompliant, isFalse);
    });

    test('pesce fresco -1/+2', () {
      expect(receipt('fish', 1).isTempCompliant, isTrue);
      expect(receipt('fish', 4).isTempCompliant, isFalse);
    });

    test('surgelati max -15', () {
      expect(receipt('frozen', -18).isTempCompliant, isTrue);
      expect(receipt('frozen', -10).isTempCompliant, isFalse);
    });

    test('cotti caldi min +60', () {
      expect(receipt('hot_cooked', 65).isTempCompliant, isTrue);
      expect(receipt('hot_cooked', 45).isTempCompliant, isFalse);
    });

    test('categoria a temperatura ambiente sempre conforme', () {
      expect(receipt('ambient', 25).isTempCompliant, isTrue);
    });

    test('temperatura assente considerata conforme', () {
      final r = Receipt(
        id: 0,
        receivedAt: DateTime.now(),
        supplierId: 1,
        product: 'Test',
        category: 'dairy',
      );
      expect(r.isTempCompliant, isTrue);
    });
  });

  group('Attrezzature', () {
    test('conformità entro i limiti', () {
      final fridge = Equipment(
        id: 1,
        name: 'Frigo',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
      );
      expect(fridge.isCompliant(2), isTrue);
      expect(fridge.isCompliant(5), isFalse);
      expect(fridge.isCompliant(-1), isFalse);
    });

    test('verifica termometro oltre 3 gradi: da sostituire', () {
      final check = ThermometerCheck(
        id: 1,
        equipmentId: 1,
        referenceTemp: 0,
        instrumentTemp: 3.5,
        checkedAt: DateTime.now(),
        operatorName: 'Op',
      );
      expect(check.deviation, 3.5);
      expect(check.mustReplace, isTrue);
    });
  });
}
