import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api/music_api.dart';
import 'core/audio/innerwave_audio_handler.dart';
import 'core/audio/player_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/mini_player.dart';
import 'features/home/home_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/library/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init(
    builder: () => InnerWaveAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.innerwave.mobile.audio',
      androidNotificationChannelName: 'InnerWave Music Playback',
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: true,
    ),
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090B0D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(InnerWaveApp(audioHandler: audioHandler));
}

class InnerWaveApp extends StatelessWidget {
  final InnerWaveAudioHandler audioHandler;

  const InnerWaveApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<MusicApi>(create: (_) => MusicApi()),
        ChangeNotifierProvider<PlayerProvider>(
          create: (context) => PlayerProvider(
            api: context.read<MusicApi>(),
            audioHandler: audioHandler,
          ),
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
          IndexedStack(index: _currentIndex, children: _screens),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
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
