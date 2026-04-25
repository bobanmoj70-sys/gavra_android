import 'package:flutter/material.dart';

import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

class V3VremeDolaskaWidget extends StatelessWidget {
  final int etaMin;
  final int? routeOrder;
  final String terminVreme;
  final String vozacIme;

  const V3VremeDolaskaWidget({
    super.key,
    required this.etaMin,
    this.routeOrder,
    required this.terminVreme,
    required this.vozacIme,
  });

  @override
  Widget build(BuildContext context) {
    final etaLabel = '${etaMin.toString()}:00 minuta';

    return V3ContainerUtils.styledContainer(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: V3StyleHelper.radius16,
      backgroundColor: V3StyleHelper.whiteAlpha06,
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Procenjeno vreme dolaska prevoza',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha75,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            etaLabel,
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha9,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Vozač: $vozacIme',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha75,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            routeOrder != null
                ? 'ETA ~ $etaMin min • Redosled #$routeOrder • Termin $terminVreme'
                : 'ETA ~ $etaMin min • Termin $terminVreme',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha75,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
