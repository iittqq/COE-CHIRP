import 'package:flutter/material.dart';
import 'components/nav_bar.dart';
import './screens/auth.dart';
import './screens/home.dart';
import './screens/scan.dart';
import './screens/data.dart';
import './screens/isp_data.dart';
import './screens/settings.dart';
import 'utils/auth_repository.dart';

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
      home: const AppRoot(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Gates the app's tab shell behind having a saved login session. Shows a
// loading spinner while the session check is in flight, then either the
// auth screen or the main shell - each side hands control back via a
// callback rather than routing, so there's no navigation stack to unwind on
// login/logout.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final loggedIn = await AuthRepository.isLoggedIn();
    if (mounted) setState(() => _loggedIn = loggedIn);
  }

  void _handleAuthenticated() {
    setState(() => _loggedIn = true);
  }

  void _handleLoggedOut() {
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loggedIn == false) {
      return AuthScreen(onAuthenticated: _handleAuthenticated);
    }

    return MainNavigation(onLoggedOut: _handleLoggedOut);
  }
}

class MainNavigation extends StatefulWidget {
  final VoidCallback onLoggedOut;

  const MainNavigation({super.key, required this.onLoggedOut});

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
    const IspDataPage(),
    SettingsScreen(onLoggedOut: widget.onLoggedOut),
  ];

  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Scans', 'Sonar Data', 'ISP Data', 'Settings'];

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
