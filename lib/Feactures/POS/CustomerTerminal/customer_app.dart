import 'package:flutter/material.dart';

import 'customer_display_screen.dart';

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Customer Display',
      // Deliberately a very distinct, unmistakable dark theme (not the default light M3 surface
      // tone, which can look similar to a plain native window background) - see if the customer
      // panel actually turns this color, to tell whether it's our Flutter content rendering at
      // all versus something else (native window background, mirrored main screen, etc.).
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrangeAccent, brightness: Brightness.dark),
      ),
      home: const CustomerDisplayScreen(),
    );
  }
}
