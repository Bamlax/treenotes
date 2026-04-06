import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const TreeNotesApp());
}

class TreeNotesApp extends StatelessWidget {
  const TreeNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TreeNotes',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.lightGreen, // ======= 改为浅绿色 =======
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}