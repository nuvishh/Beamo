import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const BeamoApp());
}

class BeamoApp extends StatelessWidget {
  const BeamoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beamo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
