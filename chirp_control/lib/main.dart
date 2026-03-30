import 'package:flutter/material.dart';
import 'components/nav_bar.dart';
import './screens/home.dart';
import './screens/scan.dart';
import './screens/data.dart';
import './screens/menu.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

  List<Widget> get _pages => [
    HomeScreen(onNavScan: () => _onNavTapped(1)),
    const DeviceControlPage(),
    const DataScreen(),
    const MenuScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Initiate Scan', 'Data', 'Menu'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_selectedIndex])),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
      ),
    );
  }
}
