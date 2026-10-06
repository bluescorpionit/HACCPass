import 'govee_h5179_model.dart';
import 'sensor_model.dart';

/// Registry dei modelli di sensore disponibili: aggiungere un modello
/// futuro = nuova classe [SensorModel] + una riga qui, senza toccare
/// schermate o registro temperature.
const List<SensorModel> sensorRegistry = [
  GoveeH5179Model(),
];

SensorModel? sensorModelById(String? id) {
  for (final model in sensorRegistry) {
    if (model.id == id) return model;
  }
  return null;
}

/// Sorgente "Manuale": comportamento pre-esistente, default di ogni
/// attrezzatura (nessun sensore collegato).
const String manualSourceId = 'manual';
