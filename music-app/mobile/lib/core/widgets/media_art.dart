import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_model.dart';
import '../theme/app_theme.dart';

class MediaArt extends StatelessWidget {
  final MediaItem item;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool showPlayOverlay;
  final VoidCallback? onPlay;

  const MediaArt({
    super.key,
    required this.item,
    this.width,
    this.height,
    this.borderRadius = 12.0,
    this.showPlayOverlay = false,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final isArtist = item.type == 'artist';
    final effectiveRadius = isArtist ? 999.0 : borderRadius;
    final thumbUrl = item.highResThumbnail;

    final memWidth = width != null ? (width! * 2).toInt().clamp(80, 720) : 320;
    final memHeight = height != null ? (height! * 2).toInt().clamp(80, 720) : memWidth;

    return ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: Container(
        width: width,
        height: height,
        color: AppTheme.surfaceElevated,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumbUrl,
                fit: BoxFit.cover,
                memCacheWidth: memWidth,
                memCacheHeight: memHeight,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) => Container(
                  color: AppTheme.surfaceElevated,
                  child: Center(
                    child: Icon(
                      isArtist ? Icons.person : Icons.album,
                      color: AppTheme.textMuted,
                      size: (width != null ? width! * 0.4 : 24.0).clamp(16.0, 36.0),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  // Fallback to youtube HQ default if primary url fails
                  if (item.videoId != null && !url.contains('hqdefault.jpg')) {
                    return CachedNetworkImage(
                      imageUrl: 'https://i.ytimg.com/vi/${item.videoId}/hqdefault.jpg',
                      fit: BoxFit.cover,
                      memCacheWidth: memWidth,
                      memCacheHeight: memHeight,
                      errorWidget: (c, u, e) => _placeholder(isArtist),
                    );
                  }
                  return _placeholder(isArtist);
                },
              )
            else
              _placeholder(isArtist),
            if (showPlayOverlay && item.videoId != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPlay,
                  child: Container(
                    color: Colors.black26,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(bool isArtist) {
    return Container(
      color: AppTheme.surfaceElevated,
      child: Center(
        child: Icon(
          isArtist ? Icons.person : Icons.album,
          color: AppTheme.textMuted,
          size: (width != null ? width! * 0.4 : 24.0).clamp(16.0, 36.0),
        ),
      ),
    );
  }
}
