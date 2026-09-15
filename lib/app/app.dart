import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../core/security/app_lock.dart';
import 'app_router.dart';

class AlHesabApp extends StatelessWidget {
  const AlHesabApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'عَ الحساب',
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.system,
    initialRoute: AppRoutes.home,
    onGenerateRoute: AppRouter.onGenerateRoute,
    builder: (context, child) => AppLockGate(child: child!),
  );
}
