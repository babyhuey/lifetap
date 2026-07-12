import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/game_screen.dart';

void main() {
  runApp(const ProviderScope(child: LifeTapApp()));
}

class LifeTapApp extends StatelessWidget {
  const LifeTapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeTap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const GameScreen(),
    );
  }
}
