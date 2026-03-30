import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const selectedBlue = Color(0xFF2563EB);
    const unselectedGrey = Color(0xFF9CA3AF);

    BottomNavigationBarItem item(IconData icon, String label, int index) {
      final selected = currentIndex == index;

      return BottomNavigationBarItem(
        label: label,
        icon: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 6,
              width: selected ? 44 : 0,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: selected ? selectedBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Icon(icon, size: 28),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      decoration: const BoxDecoration(color: Colors.white),
      child: BottomNavigationBar(
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,

        selectedItemColor: selectedBlue,
        unselectedItemColor: unselectedGrey,

        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        selectedFontSize: 12,
        unselectedFontSize: 12,

        items: [
          item(Ionicons.home, 'HOME', 0),
          item(Ionicons.compass, 'SCANS', 1),
          item(Ionicons.newspaper, 'HISTORY', 2),
          item(Ionicons.settings, 'SETTINGS', 3),
        ],
      ),
    );
  }
}
