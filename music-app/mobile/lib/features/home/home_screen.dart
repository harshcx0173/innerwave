import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/audio/player_provider.dart';
import '../../core/audio/queue_policy.dart';
import '../../core/models/media_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';
import '../../core/widgets/user_onboarding_dialog.dart';
import '../collection/collection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Feed? _feed;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _activeChip = 'All';
  String _userName = '';
  int _nextPage = 1;
  String? _continuation;
  final ScrollController _scrollController = ScrollController();

  final List<String> _defaultChips = [
    'All',
    'Relax',
    'Energize',
    'Workout',
    'Commute',
    'Focus',
    'Party',
    'Romance',
    'Feel Good',
  ];

  @override
  void initState() {
    super.initState();
    _initUserAndFeed();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initUserAndFeed() async {
    await UserOnboardingDialog.checkAndShow(context, (name) {
      if (mounted) setState(() => _userName = name);
    });
    _loadHomeFeed();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 450) {
      _loadMore();
    }
  }

  Future<void> _loadHomeFeed({bool forceRefresh = false}) async {
    final player = context.read<PlayerProvider>();
    setState(() {
      _loading = _feed == null || forceRefresh;
      _error = null;
      _activeChip = 'All';
    });

    try {
      // 1. Fetch base home feed (Quick picks + initial chips)
      final homeFuture = player.api.getHome(forceRefresh: forceRefresh);

      // 2. Concurrently fetch initial discovery shelves (New releases, Albums for you)
      final disc1Future = player.api.getMoreHome(page: 1, forceRefresh: forceRefresh).catchError((_) => Feed(shelves: []));
      final disc2Future = player.api.getMoreHome(page: 2, forceRefresh: forceRefresh).catchError((_) => Feed(shelves: []));

      // 3. Extract listening history artists for personalized shelves
      List<String> historyArtists = [];
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawHistory = prefs.getString('innerwave_mobile_history');
        if (rawHistory != null && rawHistory.isNotEmpty) {
          final items = (json.decode(rawHistory) as List<dynamic>)
              .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
              .toList();
          historyArtists = items.expand((i) => i.artists).where((a) => a.trim().isNotEmpty).toSet().take(3).toList();
        }
      } catch (_) {}

      final recsFuture = historyArtists.isNotEmpty
          ? player.api.getRecommendations(historyArtists, forceRefresh: forceRefresh).catchError((_) => <Shelf>[])
          : Future.value(<Shelf>[]);

      final results = await Future.wait([homeFuture, disc1Future, disc2Future, recsFuture]);

      final homeRes = results[0] as Feed;
      final disc1Res = results[1] as Feed;
      final disc2Res = results[2] as Feed;
      final recsRes = results[3] as List<Shelf>;

      final combinedShelves = <Shelf>[];
      combinedShelves.addAll(homeRes.shelves);
      combinedShelves.addAll(recsRes);
      combinedShelves.addAll(disc1Res.shelves);
      combinedShelves.addAll(disc2Res.shelves);

      // Deduplicate shelves by id
      final seenShelfIds = <String>{};
      final uniqueShelves = <Shelf>[];
      for (final shelf in combinedShelves) {
        if (shelf.items.isNotEmpty && !seenShelfIds.contains(shelf.id)) {
          seenShelfIds.add(shelf.id);
          uniqueShelves.add(shelf);
        }
      }

      final ordered = orderHomeShelves(uniqueShelves);

      if (mounted) {
        setState(() {
          _feed = Feed(
            shelves: ordered,
            chips: homeRes.chips?.isNotEmpty == true ? homeRes.chips : _defaultChips,
            continuation: homeRes.continuation,
            hasMore: true,
            nextPage: 3,
          );
          _nextPage = 3;
          _continuation = homeRes.continuation;
        });
      }
    } catch (e) {
      if (mounted && _feed == null) {
        setState(() => _error = 'Could not load home feed. Please check connection.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _feed == null || _nextPage > 12) return;
    final player = context.read<PlayerProvider>();
    setState(() => _loadingMore = true);

    try {
      final more = await player.api.getMoreHome(
        page: _nextPage,
        continuation: _continuation,
        chip: _activeChip == 'All' ? null : _activeChip,
      );

      if (mounted && more.shelves.isNotEmpty) {
        final existingIds = _feed!.shelves.map((s) => s.id).toSet();
        final freshShelves = more.shelves.where((s) => !existingIds.contains(s.id) && s.items.isNotEmpty).toList();

        final merged = [..._feed!.shelves, ...freshShelves];
        final ordered = orderHomeShelves(merged);

        setState(() {
          _feed = Feed(
            shelves: ordered,
            chips: _feed!.chips,
            continuation: more.continuation ?? _continuation,
            hasMore: more.hasMore,
            nextPage: _nextPage + 1,
          );
          _nextPage = _nextPage + 1;
          _continuation = more.continuation;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _selectChip(String chip) async {
    if (_activeChip == chip) return;
    setState(() {
      _activeChip = chip;
      _loading = true;
      _error = null;
    });

    final player = context.read<PlayerProvider>();
    try {
      if (chip == 'All') {
        await _loadHomeFeed();
      } else {
        final moodMoreFuture = player.api.getMoreHome(page: 1, chip: chip).catchError((_) => Feed(shelves: []));
        final moodSearchFuture = player.api.search('$chip music').catchError((_) => Feed(shelves: []));

        final results = await Future.wait([moodMoreFuture, moodSearchFuture]);
        final moreRes = results[0];
        final searchRes = results[1];

        final combined = <Shelf>[];
        combined.addAll(moreRes.shelves);
        combined.addAll(searchRes.shelves);

        final seenIds = <String>{};
        final unique = <Shelf>[];
        for (final shelf in combined) {
          if (shelf.items.isNotEmpty && !seenIds.contains(shelf.id)) {
            seenIds.add(shelf.id);
            unique.add(shelf);
          }
        }

        if (mounted) {
          setState(() {
            _feed = Feed(
              shelves: unique,
              chips: _feed?.chips ?? _defaultChips,
              hasMore: false,
              nextPage: 2,
            );
            _nextPage = 2;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load mood.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onItemTapped(MediaItem item, List<MediaItem> contextList, {Shelf? shelf}) {
    if (item.videoId != null) {
      context.read<PlayerProvider>().play(
        item,
        shelf != null &&
                startsSongRadioQueue(
                  shelfId: shelf.id,
                  shelfTitle: shelf.title,
                )
            ? const []
            : contextList,
      );
    } else if (item.browseId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CollectionScreen(item: item)),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.album, color: Colors.black, size: 18),
            ),
            const SizedBox(width: 8),
            const Text(
              'InnerWave',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (context) => UserOnboardingDialog(
                  onComplete: (newName) async {
                    await prefs.setString('innerwave_user_name', newName);
                    setState(() => _userName = newName);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppTheme.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: Text(
                _userName.isNotEmpty ? _userName.substring(0, _userName.length >= 2 ? 2 : 1).toUpperCase() : 'IW',
                style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.surface,
        onRefresh: () => _loadHomeFeed(forceRefresh: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 1. Welcome Greeting Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName.isNotEmpty ? 'Made for $_userName' : 'Made for your day',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'A living mix of fresh finds, familiar favorites and everything between.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Featured Music App Hero Banner (Spotify / Apple Music style)
            SliverToBoxAdapter(
              child: _buildHeroBanner(context, _feed, player),
            ),

            // 3. Mood Chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: (_feed?.chips?.isNotEmpty ?? false) ? _feed!.chips!.length : _defaultChips.length,
                    itemBuilder: (context, index) {
                      final chip = (_feed?.chips?.isNotEmpty ?? false) ? _feed!.chips![index] : _defaultChips[index];
                      final isSelected = _activeChip == chip;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(chip),
                          selected: isSelected,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                          selectedColor: AppTheme.accent,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onSelected: (_) => _selectChip(chip),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // 4. Section 1: "Recently Played"
            SliverToBoxAdapter(
              child: _buildRecentlyPlayedSection(context, player),
            ),

            // 5. Section 2: "Most Replayed"
            SliverToBoxAdapter(
              child: _buildMostReplayedSection(context, player),
            ),

            // Loading / Error / Other Discovery Shelves
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _loadHomeFeed(forceRefresh: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.surfaceElevated,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_feed != null && _feed!.shelves.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final shelf = _feed!.shelves[index];
                    return _buildShelf(context, shelf);
                  },
                  childCount: _feed!.shelves.length,
                ),
              )
            else
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No music results found.',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),

            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  /// State-of-the-art Hero Music App Banner (Spotify / Apple Music / YouTube Music style)
  Widget _buildHeroBanner(BuildContext context, Feed? feed, PlayerProvider player) {
    MediaItem? featuredItem;
    if (feed != null && feed.shelves.isNotEmpty) {
      for (final shelf in feed.shelves) {
        if (shelf.items.isNotEmpty) {
          featuredItem = shelf.items.firstWhere((i) => i.videoId != null, orElse: () => shelf.items.first);
          break;
        }
      }
    }

    if (featuredItem == null && player.history.isNotEmpty) {
      featuredItem = player.history.first;
    }

    if (featuredItem == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        height: 195,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF1E2818), Color(0xFF13171B), Color(0xFF0B0D0F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Background blurred artwork thumbnail
              Positioned(
                right: -30,
                top: -30,
                bottom: -30,
                width: 220,
                child: Opacity(
                  opacity: 0.45,
                  child: MediaArt(item: featuredItem, width: 220, height: 220, borderRadius: 0),
                ),
              ),

              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF080A0C).withValues(alpha: 0.95),
                        const Color(0xFF080A0C).withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),

              // Banner Content
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.graphic_eq_rounded, color: AppTheme.accent, size: 13),
                          SizedBox(width: 5),
                          Text(
                            'FEATURED RELEASE',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Title and Artist
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          featuredItem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          featuredItem.subtitle.isNotEmpty ? featuredItem.subtitle : featuredItem.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),

                    // Play Now Action Pill
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _onItemTapped(featuredItem!, [featuredItem]),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
                          label: const Text(
                            'Play Now',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          featuredItem.type.toUpperCase(),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Section 1: "Recently Played" (First Section)
  Widget _buildRecentlyPlayedSection(BuildContext context, PlayerProvider player) {
    List<MediaItem> items = player.history;

    // Fallback if brand new install without history: take top songs from feed
    if (items.isEmpty && _feed != null && _feed!.shelves.isNotEmpty) {
      items = _feed!.shelves.expand((s) => s.items).where((i) => i.videoId != null).take(6).toList();
    }

    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history_rounded, color: AppTheme.accent, size: 18),
              SizedBox(width: 6),
              Text(
                'Recently Played',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 126,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: 6,
              mainAxisSpacing: 8,
            ),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];
              return Material(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _onItemTapped(item, displayItems),
                  child: Row(
                    children: [
                      MediaArt(item: item, width: 52, height: 52, borderRadius: 10),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle.isNotEmpty ? item.subtitle : item.artists.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.play_circle_filled_rounded, color: AppTheme.accent, size: 20),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  /// Section 2: "Most Replayed" (Second Section)
  Widget _buildMostReplayedSection(BuildContext context, PlayerProvider player) {
    List<MediaItem> items = player.mostReplayed;

    // Fallback if play history is small: extract top songs from feed
    if (items.length < 3 && _feed != null && _feed!.shelves.isNotEmpty) {
      final feedSongs = _feed!.shelves.expand((s) => s.items).where((i) => i.videoId != null).toList();
      items = {...items, ...feedSongs}.take(8).toList();
    }

    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 19),
              SizedBox(width: 6),
              Text(
                'Most Replayed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 280,
              crossAxisSpacing: 6,
              mainAxisSpacing: 10,
            ),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _onItemTapped(item, displayItems),
                  child: Row(
                    children: [
                      // Rank Indicator Badge
                      Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index < 3 ? AppTheme.accent : AppTheme.textMuted,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      MediaArt(item: item, width: 44, height: 44, borderRadius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle.isNotEmpty ? item.subtitle : item.artists.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white24, size: 18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildShelf(BuildContext context, Shelf shelf) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    // 1. Song Grid Layout (e.g. Quick picks, Because you listened to, Covers and remixes)
    if (shelf.layout == 'songs') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              shelf.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
          ),
          SizedBox(
            height: 250,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 270,
                crossAxisSpacing: 6,
                mainAxisSpacing: 10,
              ),
              itemCount: shelf.items.length,
              itemBuilder: (context, index) {
                final item = shelf.items[index];
                return GestureDetector(
                  onTap: () => _onItemTapped(item, shelf.items, shelf: shelf),
                  child: Row(
                    children: [
                      MediaArt(item: item, width: 48, height: 48, borderRadius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle.isNotEmpty ? item.subtitle : item.artists.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_arrow_rounded, color: Colors.white24, size: 18),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    }

    // 2. Numbered List Layout (e.g. Long listens, charts)
    if (shelf.layout == 'list') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              shelf.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shelf.items.length > 8 ? 8 : shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${index + 1}'.padLeft(2, '0'),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      MediaArt(item: item, width: 44, height: 44, borderRadius: 8),
                    ],
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    item.subtitle.isNotEmpty ? item.subtitle : item.artists.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  trailing: item.duration != null
                      ? Text(item.duration!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))
                      : const Icon(Icons.play_circle_outline, color: Colors.white24, size: 18),
                  onTap: () => _onItemTapped(item, shelf.items, shelf: shelf),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
        ],
      );
    }

    // 3. Carousel Layout (New releases, Albums for you, Featured playlists, Hindi Hits)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            shelf.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
            ),
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return Container(
                width: 135,
                margin: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => _onItemTapped(item, shelf.items, shelf: shelf),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          MediaArt(item: item, width: 135, height: 135, borderRadius: 14),
                          if (item.type == 'album' || item.type == 'playlist')
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black87,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent, size: 16),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle.isNotEmpty ? item.subtitle : item.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
