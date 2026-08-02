import 'package:flutter/material.dart';

import 'customer_display_screen.dart';

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Customer Display',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepOrangeAccent)),
      home: const CustomerDisplayScreen(),
    );
  }
}
