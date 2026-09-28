import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../audio/player_provider.dart';
import '../theme/app_theme.dart';
import 'media_art.dart';
import '../../features/player/fullscreen_player.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final current = player.current;
        if (current == null) return const SizedBox.shrink();

        final progress = player.duration.inMilliseconds > 0
            ? (player.position.inMilliseconds / player.duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (context, anim, secAnim) => const FullscreenPlayerScreen(),
                transitionsBuilder: (context, anim, secAnim, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF161A1D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        MediaArt(
                          item: current,
                          width: 44,
                          height: 44,
                          borderRadius: 10,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                current.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                current.subtitle.isNotEmpty
                                    ? current.subtitle
                                    : current.artists.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppTheme.textPrimary,
                            size: 24,
                          ),
                          onPressed: player.togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next,
                            color: AppTheme.textPrimary,
                            size: 24,
                          ),
                          onPressed: player.next,
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    minHeight: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
