import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/media_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/media_art.dart';

class SongShareSheet extends StatefulWidget {
  final MediaItem song;
  final String? roomCode;

  const SongShareSheet({super.key, required this.song, this.roomCode});

  static Future<void> show(BuildContext context, MediaItem song, [String? roomCode]) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SongShareSheet(song: song, roomCode: roomCode),
    );
  }

  @override
  State<SongShareSheet> createState() => _SongShareSheetState();
}

class _SongShareSheetState extends State<SongShareSheet> {
  bool _copiedLink = false;
  bool _copiedRoom = false;

  void _copyLink() {
    final link = 'https://innerwave.onrender.com/?v=${widget.song.videoId ?? widget.song.id}';
    Clipboard.setData(ClipboardData(text: link));
    setState(() => _copiedLink = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedLink = false);
    });
  }

  void _copyRoomCode() {
    if (widget.roomCode == null) return;
    Clipboard.setData(ClipboardData(text: widget.roomCode!));
    setState(() => _copiedRoom = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedRoom = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final artistName = widget.song.artists.isNotEmpty
        ? widget.song.artists.join(', ')
        : widget.song.subtitle;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF14161F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Story Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C1947), Color(0xFF161824), Color(0xFF0F1017)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.graphic_eq, size: 14, color: AppTheme.accent),
                          SizedBox(width: 4),
                          Text(
                            'INNERWAVE MUSIC',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Artwork
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: MediaArt(item: widget.song),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  widget.song.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  artistName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),

                // Simulated soundwave graphic
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [18, 32, 14, 40, 26, 44, 20, 36, 28, 42, 22, 34, 16, 38]
                      .map(
                        (h) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 3.5,
                          height: h.toDouble() * 0.7,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Actions
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _copyLink,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: Icon(_copiedLink ? Icons.check : Icons.copy, size: 18),
              label: Text(
                _copiedLink ? 'Link Copied!' : 'Copy Track Link',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (widget.roomCode != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _copyRoomCode,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purpleAccent,
                  side: const BorderSide(color: Colors.purpleAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: Icon(_copiedRoom ? Icons.check : Icons.group, size: 18),
                label: Text(
                  _copiedRoom ? 'Room Code Copied!' : 'Share Room Code: ${widget.roomCode}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
