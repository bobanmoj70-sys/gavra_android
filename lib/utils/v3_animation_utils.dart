import 'package:flutter/material.dart';

/// V3AnimationUtils - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ АНИМАЦИЈАМА
/// Елиминише све AnimationController дупликате!
class V3AnimationUtils {
  // Мапа за чување AnimationController инстанци
  static final Map<String, AnimationController> _controllers = {};

  /// Креира нови AnimationController или враћа постојећи
  static AnimationController getController({
    required String key,
    required TickerProvider vsync,
    required Duration duration,
    Duration? reverseDuration,
    String? debugLabel,
    double lowerBound = 0.0,
    double upperBound = 1.0,
    AnimationBehavior animationBehavior = AnimationBehavior.normal,
  }) {
    // Ако контролер постоји, dispose га пре креирања новог
    _controllers[key]?.dispose();

    final controller = AnimationController(
      vsync: vsync,
      duration: duration,
      reverseDuration: reverseDuration,
      debugLabel: debugLabel,
      lowerBound: lowerBound,
      upperBound: upperBound,
      animationBehavior: animationBehavior,
    );

    _controllers[key] = controller;
    return controller;
  }

  /// Добиј постојећи контролер (може бити null)
  static AnimationController? getExistingController(String key) {
    return _controllers[key];
  }

  /// Уништи контролер
  static void disposeController(String key) {
    _controllers[key]?.dispose();
    _controllers.remove(key);
  }

  /// Уништи све контролере
  static void disposeAllControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  // ─── АНИМАЦИЈА ХЕЛПЕРИ ──────────────────────────────────────────

  /// Креира Tween анимацију
  static Animation<double> createTween({
    required AnimationController controller,
    double begin = 0.0,
    double end = 1.0,
    Curve curve = Curves.linear,
  }) {
    return Tween<double>(begin: begin, end: end).animate(CurvedAnimation(parent: controller, curve: curve));
  }
}
