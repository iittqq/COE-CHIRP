import 'package:flutter/material.dart';
import 'components/nav_bar.dart';
import './screens/home.dart';
import './screens/scan.dart';
import './screens/data.dart';
import './screens/settings.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebSocket Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),

        scaffoldBackgroundColor: Colors.white,

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),

        useMaterial3: true,
      ),
      home: const MainNavigation(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  void _onNavTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Built once and kept alive via IndexedStack so switching tabs doesn't
  // tear down and recreate state (which was re-fetching weather/sonars and
  // reconnecting the WebSocket on every tab switch).
  late final List<Widget> _pages = [
    HomeScreen(onNavScan: () => _onNavTapped(1)),
    const DeviceControlPage(),
    const HistoryPage(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Scans', 'History', 'Settings'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_selectedIndex])),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
      ),
    );
  }
}
