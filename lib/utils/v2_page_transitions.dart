import 'package:flutter/material.dart';

class V2SmoothPageRoute<T> extends PageRouteBuilder<T> {
  V2SmoothPageRoute({
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
            // Slide and fade transition
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;

            final tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            final offsetAnimation = animation.drive(tween);

            final fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: curve),
            );

            return SlideTransition(
              position: offsetAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: pageChild,
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

  static Future<T?> pushSmooth<T>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.push<T>(
      context,
      V2SmoothPageRoute(child: page),
    );
  }

  static Future<T?> pushReplacementSmooth<T, TO>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.pushReplacement<T, TO>(
      context,
      V2SmoothPageRoute(child: page),
    );
  }
}
