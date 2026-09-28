import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api/music_api.dart';
import 'core/audio/player_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/mini_player.dart';
import 'features/home/home_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/library/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090B0D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const InnerWaveApp());
}

class InnerWaveApp extends StatelessWidget {
  const InnerWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<MusicApi>(create: (_) => MusicApi()),
        ChangeNotifierProvider<PlayerProvider>(
          create: (context) => PlayerProvider(api: context.read<MusicApi>()),
        ),
      ],
      child: MaterialApp(
        title: 'InnerWave',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainNavigationShell(),
      ),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    ExploreScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, size: 22),
            activeIcon: Icon(Icons.home, size: 22),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined, size: 22),
            activeIcon: Icon(Icons.explore, size: 22),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_outlined, size: 22),
            activeIcon: Icon(Icons.library_music, size: 22),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
