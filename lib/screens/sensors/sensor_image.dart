import 'package:flutter/material.dart';

import '../../core/sensors/sensor_model.dart';

/// Nota di non affiliazione (mostrata in Guida e nel foglio di
/// collegamento).
const String sensorTrademarkNote =
    'Govee \u00E8 un marchio dei rispettivi proprietari. HACCPass non \u00E8 '
    'affiliata a Govee.';

/// Immagine del sensore (fornita dal proprietario dell'app in
/// `assets/images/`): se l'asset mancade o non si carica compare un'icona
/// generica con i colori del tema, mai riquadri vuoti né crash.
class SensorModelImage extends StatelessWidget {
  const SensorModelImage({super.key, required this.model, this.size = 104});

  final SensorModel model;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.sensors,
        size: size * 0.5,
        color: theme.colorScheme.onPrimaryContainer,
        semanticLabel: 'Sensore ${model.displayName}',
      ),
    );

    final asset = model.imageAsset;
    if (asset == null) return fallback;

    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * 2).round(),
      semanticLabel: 'Sensore ${model.displayName}',
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
