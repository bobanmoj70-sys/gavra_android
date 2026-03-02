import 'package:flutter/material.dart';

class V2SmoothPageRoute<T> extends PageRouteBuilder<T> {
  V2SmoothPageRoute({
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Slide and fade transition
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            var offsetAnimation = animation.drive(tween);

            var fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: curve),
            );

            return SlideTransition(
              position: offsetAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            );
          },
        );
  final Widget child;
  final Duration duration;
}

// Helper funkcije za lako korišćenje
class V2AnimatedNavigation {
  V2AnimatedNavigation._();

  static Future<T?> pushSmooth<T extends Object?>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.push<T>(
      context,
      V2SmoothPageRoute(child: page),
    );
  }

  static Future<T?> pushReplacementSmooth<T extends Object?, TO extends Object?>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.pushReplacement<T, TO>(
      context,
      V2SmoothPageRoute(child: page),
    );
  }
}
