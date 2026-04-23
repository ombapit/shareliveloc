import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'help_screen.dart';
import 'share_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _screens = const [
    DashboardScreen(),
    ShareScreen(),
    HelpScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // Fullscreen map in landscape: hide bottom nav when on Dashboard tab
    final hideBottomNav = isLandscape && _currentIndex == 0;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: hideBottomNav
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.share_location_outlined),
                  selectedIcon: Icon(Icons.share_location),
                  label: 'Share',
                ),
                NavigationDestination(
                  icon: Icon(Icons.help_outline),
                  selectedIcon: Icon(Icons.help),
                  label: 'Bantuan',
                ),
              ],
            ),
    );
  }
}
