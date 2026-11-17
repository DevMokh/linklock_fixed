import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() {
  runApp(const LinkLockApp());
}

class LinkLockApp extends StatelessWidget {
  const LinkLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E6F5C);
    return MaterialApp(
      title: 'قفل الروابط',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: seed),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    );
  }
}