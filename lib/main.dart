import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape both ways so the tabletop counters stay put; never auto-rotate to
  // a single default. catchError swallows the async platform-channel failure on
  // desktop/test targets that have no orientation plugin.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).catchError((Object _) {});
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
