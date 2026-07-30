import 'package:flutter/material.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/employee_terminal_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepOrangeAccent),
      ),
      home: const EmployeeTerminalScreen(),
    );
  }
}
