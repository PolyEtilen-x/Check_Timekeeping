import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'pages/intro.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TimeKeepingApp());
}

class TimeKeepingApp extends StatelessWidget {
  const TimeKeepingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Timekeeping App',
      debugShowCheckedModeBanner: false,
      home: IntroPage(), // vẫn là Intro
    );
  }
}
