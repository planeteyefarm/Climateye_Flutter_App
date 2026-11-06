import 'package:flutter/material.dart';

/// Non-opaque route so the underlying [MapScreen] (and its live FlutterMap)
/// stays painted during navigation. Does not recreate the map.
class MapBackedPageRoute<T> extends PageRouteBuilder<T> {
  MapBackedPageRoute({
    required WidgetBuilder builder,
    super.transitionDuration = const Duration(milliseconds: 220),
  }) : super(
          opaque: false,
          barrierDismissible: false,
          barrierColor: Colors.transparent,
          reverseTransitionDuration: transitionDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        );
}
