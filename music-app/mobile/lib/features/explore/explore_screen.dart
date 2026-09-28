import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/audio/player_provider.dart';
import '../../core/models/media_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';
import '../collection/collection_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  Feed? _results;
  bool _loading = false;
  String? _error;
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Songs', 'Albums', 'Artists', 'Playlists'];

  @override
  void initState() {
    super.initState();
    _performSearch('Trending music');
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().length >= 2) {
      _debounceTimer = Timer(const Duration(milliseconds: 400), () {
        _performSearch(value.trim());
      });
    }
  }

  Future<void> _performSearch(String query) async {
    final player = context.read<PlayerProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await player.api.search(query);
      if (mounted) setState(() => _results = res);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onItemTapped(MediaItem item, List<MediaItem> contextList) {
    if (item.videoId != null) {
      context.read<PlayerProvider>().play(item, contextList);
    } else if (item.browseId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CollectionScreen(item: item)),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _results?.shelves.expand((s) => s.items).toList() ?? [];
    final filteredItems = _selectedFilter == 'All'
        ? allItems
        : allItems.where((item) => item.type.toLowerCase() == _selectedFilter.toLowerCase().substring(0, _selectedFilter.length - 1)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search & Explore', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.accent),
                ),
              ),
              onChanged: (val) {
                setState(() {});
                _onSearchChanged(val);
              },
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) _performSearch(val.trim());
              },
            ),
          ),

          // Filters row
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    selectedColor: AppTheme.accent,
                    backgroundColor: Colors.white.withOpacity(0.06),
                    side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (_) => setState(() => _selectedFilter = filter),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Results list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                    : filteredItems.isEmpty
                        ? const Center(child: Text('No results found.', style: TextStyle(color: AppTheme.textMuted)))
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                                child: Material(
                                  color: Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    leading: MediaArt(item: item, width: 46, height: 46, borderRadius: 10),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      item.subtitle.isNotEmpty ? item.subtitle : item.type,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                    ),
                                    trailing: Icon(
                                      item.videoId != null ? Icons.play_arrow : Icons.chevron_right,
                                      color: Colors.white30,
                                      size: 18,
                                    ),
                                    onTap: () => _onItemTapped(item, filteredItems),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
