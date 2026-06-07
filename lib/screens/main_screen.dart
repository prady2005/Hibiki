import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/theme_state.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;

  Widget _buildCurrentScreen() {
    switch (currentIndex) {
      case 0:
        return const HomePage();
      case 1:
        return const LibraryScreen();
      case 2:
        return const SearchScreen(key: ValueKey('search-screen-current'));
      case 3:
        return const ProfileScreen();
      default:
        return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          KeyedSubtree(
            key: ValueKey('tab-$currentIndex'),
            child: _buildCurrentScreen(),
          ),
          if (!isKeyboardOpen)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 92,
              child: AppMiniPlayer(bottomMargin: 4),
            ),
        ],
      ),
      bottomNavigationBar: isKeyboardOpen
          ? null
          : ValueListenableBuilder<AppThemeChoice>(
              valueListenable: appThemeChoiceNotifier,
              builder: (context, themeChoice, _) {
                return _BottomNavigationBar(
                  currentIndex: currentIndex,
                  onTap: (index) {
                    setState(() {
                      currentIndex = index;
                    });
                  },
                );
              },
            ),
    );
  }
}

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    const List<(IconData, String)> items = [
      (CupertinoIcons.house_fill, 'Home'),
      (CupertinoIcons.square_stack_fill, 'Library'),
      (CupertinoIcons.search, 'Search'),
      (Icons.settings, 'Settings'),
    ];

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final (IconData, String) item = items[index];
            final isActive = index == currentIndex;

            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(index),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$1,
                        color: isActive ? palette.accent : palette.mutedText,
                        size: 22,
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isActive ? palette.accent : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
