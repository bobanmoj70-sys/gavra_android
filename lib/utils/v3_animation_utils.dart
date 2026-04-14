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

  // ─── СПЕЦИЈАЛИЗОВАНЕ АНИМАЦИЈЕ ───────────────────────────────────

  /// Pulse анимација за forced update dialog
  static AnimationController createPulseController({
    required TickerProvider vsync,
    Duration duration = const Duration(seconds: 2),
  }) {
    return getController(
      key: 'pulse',
      vsync: vsync,
      duration: duration,
      debugLabel: 'Pulse Animation',
    );
  }

  /// Fade анимација за екране
  static AnimationController createFadeController({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 1000),
  }) {
    return getController(
      key: 'fade',
      vsync: vsync,
      duration: duration,
      debugLabel: 'Fade Animation',
    );
  }

  /// Slide анимација за екране
  static AnimationController createSlideController({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 800),
  }) {
    return getController(
      key: 'slide',
      vsync: vsync,
      duration: duration,
      debugLabel: 'Slide Animation',
    );
  }

  /// Permission screen анимација
  static AnimationController createPermissionController({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return getController(
      key: 'permission',
      vsync: vsync,
      duration: duration,
      debugLabel: 'Permission Animation',
    );
  }

  // ─── АНИМАЦИЈА ХЕЛПЕРИ ──────────────────────────────────────────

  /// Креира Tween анимацију
  static Animation<double> createTween({
    required AnimationController controller,
    double begin = 0.0,
    double end = 1.0,
    Curve curve = Curves.linear,
  }) {
    return Tween<double>(begin: begin, end: end)
        .animate(CurvedAnimation(parent: controller, curve: curve));
  }

  /// Креира Color Tween анимацију
  static Animation<Color?> createColorTween({
    required AnimationController controller,
    required Color begin,
    required Color end,
    Curve curve = Curves.linear,
  }) {
    return ColorTween(begin: begin, end: end)
        .animate(CurvedAnimation(parent: controller, curve: curve));
  }

  /// Масовно покретање анимације
  static void forwardAll(List<String> keys) {
    for (final key in keys) {
      _controllers[key]?.forward();
    }
  }

  /// Масовно заустављање анимације
  static void reverseAll(List<String> keys) {
    for (final key in keys) {
      _controllers[key]?.reverse();
    }
  }

  /// Масовно ресетовање анимације
  static void resetAll(List<String> keys) {
    for (final key in keys) {
      _controllers[key]?.reset();
    }
  }

  /// Провери статус анимације
  static AnimationStatus? getStatus(String key) {
    return _controllers[key]?.status;
  }

  /// Провери да ли је анимација у току
  static bool isAnimating(String key) {
    final controller = _controllers[key];
    return controller?.isAnimating ?? false;
  }
}
