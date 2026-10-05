import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:permission_handler/permission_handler.dart';

import 'core/api/music_api.dart';
import 'core/auth/auth_controller.dart';
import 'core/auth/auth_screen.dart';
import 'core/audio/innerwave_audio_handler.dart';
import 'core/audio/player_provider.dart';
import 'core/config/supabase_config.dart';
import 'core/sync/playback_sync_controller.dart';
import 'core/social/listening_room_controller.dart';
import 'core/social/room_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/mini_player.dart';
import 'features/home/home_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/library/library_screen.dart';
import 'features/social/listening_room_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await RoomNotificationService.initialize();

  final audioHandler = await AudioService.init(
    builder: () => InnerWaveAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.innerwave.mobile.audio',
      androidNotificationChannelName: 'InnerWave Music Playback',
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: false,
    ),
  );

  unawaited(() async {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }());

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
        ChangeNotifierProvider<AuthController>(create: (_) => AuthController()),
        ChangeNotifierProvider<PlayerProvider>(
          create: (context) => PlayerProvider(
            api: context.read<MusicApi>(),
            audioHandler: audioHandler,
          ),
        ),
        ChangeNotifierProxyProvider2<AuthController, PlayerProvider,
            PlaybackSyncController>(
          create: (_) => PlaybackSyncController(),
          update: (_, auth, player, sync) => sync!..update(auth, player),
        ),
        ChangeNotifierProxyProvider2<AuthController, PlayerProvider,
            ListeningRoomController>(
          create: (_) => ListeningRoomController(),
          update: (_, auth, player, rooms) => rooms!..update(auth, player),
        ),
      ],
      child: MaterialApp(
        title: 'InnerWave',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AuthGate(child: MainNavigationShell()),
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const AuthGate(child: MainNavigationShell()),
          settings: settings,
        ),
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

  void _showConnect() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF151817),
      builder: (sheetContext) => Consumer3<PlaybackSyncController, AuthController, PlayerProvider>(
        builder: (_, sync, auth, player, child) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(auth.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(auth.user?.email ?? '', style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 20),
                const Text('InnerWave Connect', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Choose the device that should play music.', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 10),
                ...sync.devices.map((device) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(device.platform == 'Android' || device.platform == 'iOS' ? Icons.smartphone : Icons.computer),
                      title: Text(device.name),
                      subtitle: Text(device.id == sync.deviceId ? 'This device' : 'Online'),
                      trailing: device.id == sync.activeDeviceId
                          ? const Text('PLAYING', style: TextStyle(color: Color(0xFFD5FF63), fontSize: 11, fontWeight: FontWeight.w800))
                          : null,
                      onTap: () async {
                        await sync.activateDevice(device.id);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    )),
                if (sync.devices.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Connecting…', style: TextStyle(color: Colors.white54))),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.volume_down, size: 20),
                  Expanded(
                    child: Slider(
                      value: player.volume,
                      onChanged: (value) => unawaited(player.setVolume(value)),
                    ),
                  ),
                  const Icon(Icons.volume_up, size: 20),
                ]),
                const Divider(),
                TextButton.icon(
                  onPressed: () async { Navigator.pop(sheetContext); await auth.signOut(); },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showListeningRoom() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF151817),
      builder: (_) => const ListeningRoomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Row(children: [
              Consumer<ListeningRoomController>(builder: (context, room, child) => IconButton.filledTonal(onPressed: _showListeningRoom, tooltip: 'Listening room', icon: Icon(Icons.forum_outlined, color: room.room != null && room.connected ? const Color(0xFFD5FF63) : Colors.white70))),
              const SizedBox(width: 6),
              Consumer<PlaybackSyncController>(builder: (context, sync, child) => IconButton.filledTonal(onPressed: _showConnect, tooltip: 'InnerWave Connect', icon: Icon(Icons.speaker_group_outlined, color: sync.connected ? const Color(0xFFD5FF63) : Colors.white70))),
            ]),
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
