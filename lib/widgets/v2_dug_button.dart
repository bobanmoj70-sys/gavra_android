import 'package:flutter/material.dart';

import '../theme.dart'; // Dodato za glassmorphism

class V2DugButton extends StatelessWidget {
  const V2DugButton({
    super.key,
    required this.brojDuznika,
    this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.textColor,
    this.wide = false,
    this.isLoading = false,
  });
  final int brojDuznika;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? textColor;
  final bool wide;
  // TODO: isLoading nije jos implementiran — dodati spinner i onTap blokadu kada je true
  final bool isLoading;

  // Pre-computed konstante da bi se izbegao ponovni MaterialColor[] lookup na svakom rebuild-u
  static const Color _defaultBg = Color(0xFFFFEBEE); // Colors.red[50]
  static const Color _defaultBorder = Color(0xFFE57373); // Colors.red[300]
  static const Color _defaultAccent = Color(0xFFD32F2F); // Colors.red[700]
  static const BorderRadius _borderRadius = BorderRadius.all(Radius.circular(8));

  /// Prikaz broja dužnika: pozitivan broj ili '-' ako nema dužnika.
  String get _labelBroj => brojDuznika > 0 ? brojDuznika.toString() : '-';

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      // Kompaktni prikaz (za sve ekrane osim admin)
      return InkWell(
        onTap: onTap,
        borderRadius: _borderRadius,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: backgroundColor ?? _defaultBg,
            borderRadius: _borderRadius,
            border: Border.all(color: _defaultBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning,
                color: iconColor ?? _defaultAccent,
                size: 18,
              ),
              const SizedBox(height: 2),
              const Text(
                'Dug',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _defaultAccent,
                ),
              ),
              Text(
                _labelBroj,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textColor ?? _defaultAccent,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Široki prikaz (kocka kao za admin screen)
      return InkWell(
        onTap: onTap,
        borderRadius: _borderRadius,
        child: Container(
          width: double.infinity,
          height: 60,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? Theme.of(context).glassContainer, // Glassmorphism
            borderRadius: _borderRadius,
            border: Border.all(
              color: Theme.of(context).glassBorder, // Transparentni border
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: iconColor ?? _defaultAccent,
                radius: 16,
                child: const Icon(Icons.warning, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dužnici',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textColor ?? _defaultAccent,
                      ),
                    ),
                    const Text(
                      'Dug',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF757575), // Colors.grey[600]
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.monetization_on,
                    color: iconColor ?? _defaultAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _labelBroj,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor ?? _defaultAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }
}
