import 'package:flutter/material.dart';

import '../features/home/presentation/home_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
}

abstract final class AppRouter {
  static Route<void> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      AppRoutes.home => MaterialPageRoute<void>(
        builder: (_) => const HomeScreen(),
        settings: settings,
      ),
      _ => MaterialPageRoute<void>(
        builder: (_) => const HomeScreen(),
        settings: const RouteSettings(name: AppRoutes.home),
      ),
    };
  }
}
