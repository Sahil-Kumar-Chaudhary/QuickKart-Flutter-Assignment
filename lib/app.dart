import 'package:flutter/material.dart';

import 'features/app_config/presentation/update_gate.dart';
import 'features/catalog/presentation/home_screen.dart';

class QuickKartApp extends StatelessWidget {
  const QuickKartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickKart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0C831F),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      // The update gate wraps the navigator (not just home) so a forced
      // update also covers pushed routes like the cart or a category.
      builder: (context, child) =>
          UpdateGate(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}
