"use client";

/* eslint-disable @next/next/no-img-element */
import { Fragment, useCallback, useEffect, useRef, useState, type CSSProperties } from "react";
import { LoaderCircle, Play, RefreshCw, Shuffle } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { useAuth } from "@/context/auth-context";
import { musicApi } from "@/lib/api";
import type { Feed, MediaItem, Shelf as ShelfType } from "@/lib/types";
import { PlayerBar } from "./player-bar";
import { FullscreenPlayer } from "./fullscreen-player";
import { QueuePanel } from "./queue-panel";
import { Shelf } from "./shelf";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";
import { MediaArt } from "./media-art";
import { TasteBuilder } from "./taste-builder";
import { ProfilePage } from "./profile-page";
import { ExplorePage } from "./explore-page";
import { ListeningRoomPanel } from "./listening-room-panel";
import { usePlaylist, type UserPlaylist } from "@/context/playlist-context";
import { AddToPlaylistModal } from "./add-to-playlist-modal";
import { SongShareModal } from "./song-share-modal";
import { ArtistPage } from "./artist-view";

type View = "home" | "explore" | "library" | "profile";

function orderHomeShelves(shelves: ShelfType[]) {
  const rank = (shelf: ShelfType) => {
    if (shelf.id === "quick-picks" || shelf.title.toLowerCase().includes("quick picks")) return 0;
    const discoveryPage = Number(shelf.id.replace("discover-", ""));
    if (Number.isFinite(discoveryPage)) return discoveryPage * 10;
    if (shelf.id.startsWith("personal-")) return 25;
    return 200;
  };
  return [...shelves].sort((first, second) => rank(first) - rank(second));
}

function feedItems(feed: Feed) {
  return feed.shelves.flatMap((shelf) => shelf.items);
}

function uniqueItems(items: MediaItem[]) {
  return items.filter((item, index) => items.findIndex((candidate) => candidate.id === item.id) === index);
}

function interleaveItems(...groups: MediaItem[][]) {
  const mixed: MediaItem[] = [];
  const longest = Math.max(0, ...groups.map((group) => group.length));
  for (let index = 0; index < longest; index++) {
    for (const group of groups) if (group[index]) mixed.push(group[index]);
  }
  return uniqueItems(mixed);
}

function recentArtists(items: MediaItem[]) {
  return [...new Set(items.flatMap((item) => item.artists).filter((artist) => artist && !["song", "video"].includes(artist.toLowerCase())))].slice(0, 3);
}

function colorFromText(value: string) {
  let hash = 0;
  for (let index = 0; index < value.length; index++) hash = value.charCodeAt(index) + ((hash << 5) - hash);
  return `hsl(${Math.abs(hash) % 360} 58% 32%)`;
}

function useArtworkColor(url: string | null | undefined, seed: string) {
  const [sample, setSample] = useState<{ url: string; color: string } | null>(null);
  useEffect(() => {
    if (!url) return;
    const image = new Image();
    image.crossOrigin = "anonymous";
    image.referrerPolicy = "no-referrer";
    image.src = url;
    image.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = 20; canvas.height = 20;
        const context = canvas.getContext("2d", { willReadFrequently: true });
        if (!context) return;
        context.drawImage(image, 0, 0, 20, 20);
        const pixels = context.getImageData(0, 0, 20, 20).data;
        let r = 0, g = 0, b = 0, count = 0;
        for (let index = 0; index < pixels.length; index += 16) {
          if (pixels[index + 3] < 150) continue;
          r += pixels[index]; g += pixels[index + 1]; b += pixels[index + 2]; count++;
        }
        if (count) setSample({ url, color: `rgb(${Math.round(r / count)} ${Math.round(g / count)} ${Math.round(b / count)})` });
      } catch { /* cross-origin artwork falls back to a stable title color */ }
    };
    image.onerror = () => undefined;
  }, [url, seed]);
  return url && sample?.url === url ? sample.color : colorFromText(seed);
}

export function MusicApp() {
  const player = usePlayer();
  const { displayName, user } = useAuth();
  const { getPlaylistSongs } = usePlaylist();
  const historyKey = `innerwave-history:${user?.id || "guest"}`;
  const [feed, setFeed] = useState<Feed>({ shelves: [] });
  const [title, setTitle] = useState("Made for your day");
  const [subtitle, setSubtitle] = useState("A living mix of fresh finds, familiar favorites and everything between.");
  const [view, setView] = useState<View>("home");
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextPage, setNextPage] = useState<number | null>(1);
  const [homeContinuation, setHomeContinuation] = useState<string | null>(null);
  const [activeChip, setActiveChip] = useState("All");
  const [collection, setCollection] = useState<MediaItem | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exploreLanding, setExploreLanding] = useState(false);
  const [exploreMoods, setExploreMoods] = useState<string[]>([]);
  const [exploreSeed, setExploreSeed] = useState("");
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const exploreRequestRef = useRef(0);
  const artworkColor = useArtworkColor(player.current?.thumbnail, player.current?.title || "InnerWave");

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setTitle(`Made for ${displayName}`);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [displayName]);

  const loadHome = useCallback(async () => {
    exploreRequestRef.current += 1;
    setLoading(true); setError(null); setView("home");
    setQuery(""); setExploreLanding(false);
    setTitle(`Made for ${displayName}`);
    setCollection(null);
    setSubtitle("A living mix of fresh finds, familiar favorites and everything between.");
    try {
      const home = await musicApi.home();
      setFeed(home);
      setNextPage(home.nextPage ?? 1);
      setHomeContinuation(home.continuation || null);
      setActiveChip("All");
      const history = JSON.parse(localStorage.getItem(historyKey) || "[]") as MediaItem[];
      const artists = [...new Set(history.flatMap((item) => item.artists).filter(Boolean))].slice(0, 3);
      if (artists.length) {
        musicApi.recommendations(artists).then((personal) => {
          if (personal.shelves.length) {
            setFeed((current) => {
              const combined = [...personal.shelves, ...current.shelves];
              return {
                ...current,
                shelves: orderHomeShelves(combined.filter((shelf, index) => combined.findIndex((item) => item.id === shelf.id) === index)),
              };
            });
          }
        }).catch(() => undefined);
      }
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Could not load music"); }
    finally { setLoading(false); }
  }, [displayName, historyKey]);

  const loadMore = useCallback(async () => {
    if (view !== "home" || loading || loadingMore || nextPage == null) return;
    setLoadingMore(true);
    try {
      const more = await musicApi.moreHome(nextPage, homeContinuation, activeChip === "All" ? "" : activeChip);
      setFeed((current) => {
        const combined = [...current.shelves, ...more.shelves];
        return {
          ...current,
          shelves: orderHomeShelves(combined.filter((shelf, index) => combined.findIndex((item) => item.id === shelf.id) === index)),
        };
      });
      setHomeContinuation(more.continuation || null);
      setNextPage(more.hasMore ? (more.nextPage ?? nextPage + 1) : null);
    } catch {
      setNextPage(null);
    } finally {
      setLoadingMore(false);
    }
  }, [activeChip, homeContinuation, loading, loadingMore, nextPage, view]);

  useEffect(() => {
    const target = loadMoreRef.current;
    if (!target) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries[0]?.isIntersecting) loadMore();
    }, { rootMargin: "700px 0px" });
    observer.observe(target);
    return () => observer.disconnect();
  }, [loadMore]);

  useEffect(() => {
    const timer = window.setTimeout(loadHome, 0);
    return () => window.clearTimeout(timer);
  }, [loadHome]);

  const search = useCallback(async (value: string) => {
    if (!value.trim()) return;
    exploreRequestRef.current += 1;
    setCollection(null);
    setExploreLanding(false);
    setLoading(true); setError(null); setView("explore"); setTitle(`Results for “${value}”`); setSubtitle("Songs, albums, artists and playlists from YouTube Music.");
    try { setFeed(await musicApi.search(value)); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "Search failed"); }
    finally { setLoading(false); }
  }, []);

  const loadExplore = useCallback(async () => {
    const requestId = ++exploreRequestRef.current;
    setLoading(true); setError(null); setView("explore"); setCollection(null);
    setQuery(""); setExploreLanding(true);
    setTitle("Explore");
    setSubtitle("Fresh releases, charts and discoveries shaped by your listening.");
    try {
      const baseHome = await musicApi.home();
      if (requestId !== exploreRequestRef.current) return;
      const history = JSON.parse(localStorage.getItem(historyKey) || "[]") as MediaItem[];
      const sourceItems = history.length ? history : feedItems(baseHome);
      const artists = recentArtists(sourceItems);
      const primarySeed = artists[0] || sourceItems[0]?.title || "music";
      const secondarySeed = artists[1] || primarySeed;
      setExploreSeed(primarySeed);

      const [releaseFeed, trendingFeed, videoFeed, personalFeed] = await Promise.all([
        musicApi.search(`${primarySeed} new albums singles`).catch(() => ({ shelves: [] } as Feed)),
        musicApi.search(`${primarySeed} ${secondarySeed} trending songs`).catch(() => ({ shelves: [] } as Feed)),
        musicApi.search(`${secondarySeed} new music videos`).catch(() => ({ shelves: [] } as Feed)),
        artists.length ? musicApi.recommendations(artists).catch(() => ({ shelves: [] } as Feed)) : Promise.resolve({ shelves: [] } as Feed),
      ]);
      if (requestId !== exploreRequestRef.current) return;

      const releaseCandidates = uniqueItems(feedItems(releaseFeed));
      const releaseItems = uniqueItems([
        ...releaseCandidates.filter((item) => item.type === "album"),
        ...releaseCandidates.filter((item) => item.type === "playlist"),
        ...releaseCandidates.filter((item) => !["album", "playlist", "artist"].includes(item.type)),
      ]).slice(0, 7);
      const trendingItems = interleaveItems(
        feedItems(trendingFeed).filter((item) => item.videoId),
        feedItems(personalFeed).filter((item) => item.videoId),
      ).slice(0, 12);
      const videoCandidates = uniqueItems(feedItems(videoFeed).filter((item) => item.videoId));
      const explicitVideos = videoCandidates.filter((item) => {
        const label = `${item.title} ${item.subtitle}`.toLowerCase();
        return label.includes("video") || label.includes("views");
      });
      const videoItems = uniqueItems([...explicitVideos, ...videoCandidates]).slice(0, 6);
      const exploreShelves: ShelfType[] = [
        { id: "explore-releases", title: "New albums & singles", layout: "carousel", items: releaseItems },
        { id: "explore-trending", title: "Trending for you", layout: "list", items: trendingItems },
        { id: "explore-videos", title: "New music videos", layout: "carousel", items: videoItems },
      ];
      const shelves = exploreShelves.filter((shelf) => shelf.items.length);
      setExploreMoods((baseHome.chips || []).filter(Boolean).slice(0, 24));
      setFeed({ shelves });
    } catch (reason) {
      if (requestId === exploreRequestRef.current) setError(reason instanceof Error ? reason.message : "Could not build your Explore page");
    } finally {
      if (requestId === exploreRequestRef.current) setLoading(false);
    }
  }, [historyKey]);

  useEffect(() => {
    if (query.trim().length < 2) return;
    const timer = window.setTimeout(() => search(query.trim()), 450);
    return () => window.clearTimeout(timer);
  }, [query, search]);

  const selectItem = useCallback(async (item: MediaItem, context: MediaItem[], shelf: ShelfType) => {
    if (item.videoId) {
      const title = shelf.title.toLowerCase();
      const startsRadio = shelf.id === "quick-picks"
        || shelf.id.startsWith("personal-")
        || ["discover-7", "discover-8", "discover-11"].includes(shelf.id)
        || title.includes("quick picks")
        || title.includes("because you listened")
        || title.includes("covers and remixes")
        || title.includes("trending songs for you")
        || title.includes("long listens");
      player.play(item, startsRadio || (view === "explore" && !collection) ? [] : context);
      return;
    }
    if (!item.browseId) return;
    setLoading(true); setError(null); setCollection(item); setTitle(item.title); setSubtitle(item.subtitle || `Browse this ${item.type}`);
    try { setFeed(await musicApi.browse(item.browseId, item.browseParams)); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "Could not open this collection"); }
    finally { setLoading(false); }
  }, [collection, player, view]);

  const navigate = useCallback((nextView: View) => {
    player.closeArtistView();
    setCollection(null);
    if (nextView === "home") { loadHome(); return; }
    if (nextView === "explore") { loadExplore(); return; }
    exploreRequestRef.current += 1;
    const history = JSON.parse(localStorage.getItem(historyKey) || "[]") as MediaItem[];
    const shelf: ShelfType = { id: "history", title: "Recently played", layout: "list", items: history };
    setView("library"); setTitle("Your Library"); setSubtitle("Your last 50 plays stay private in this browser."); setFeed({ shelves: history.length ? [shelf] : [] }); setError(null);
  }, [historyKey, loadExplore, loadHome, player]);

  const openPlaylist = useCallback(async (playlist: UserPlaylist) => {
    player.closeArtistView();
    setLoading(true);
    setError(null);
    try {
      const songs = await getPlaylistSongs(playlist.id);
      const mockCollection: MediaItem = {
        id: playlist.id,
        videoId: null,
        browseId: null,
        browseParams: null,
        playlistId: playlist.id,
        title: playlist.name,
        subtitle: playlist.description || `${songs.length} tracks • Custom playlist`,
        artists: [],
        thumbnail: playlist.coverUrl || (songs[0]?.thumbnail ?? null),
        type: "playlist",
        duration: null,
        watchParams: null,
        index: null,
      };
      setCollection(mockCollection);
      setTitle(playlist.name);
      setSubtitle(playlist.description || "Custom Playlist");
      setFeed({
        shelves: [
          {
            id: `user-playlist-${playlist.id}`,
            title: "Playlist Songs",
            layout: "list",
            items: songs,
          },
        ],
      });
      setView("library");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load playlist songs");
    } finally {
      setLoading(false);
    }
  }, [getPlaylistSongs, player]);

  const browseExplore = useCallback((kind: "releases" | "charts" | "moods" | "podcasts") => {
    const seed = exploreSeed || "music";
    const requests = {
      releases: `${seed} new releases`,
      charts: `${seed} trending charts`,
      moods: `${seed} moods genres`,
      podcasts: `${seed} music podcasts`,
    };
    search(requests[kind]);
  }, [exploreSeed, search]);

  const browseMood = useCallback((mood: string) => {
    search(`${mood} ${exploreSeed || ""} music`.trim());
  }, [exploreSeed, search]);

  const playCollection = useCallback((shuffle = false) => {
    const tracks = feed.shelves.flatMap((shelf) => shelf.items).filter((item) => item.videoId);
    const unique = tracks.filter((item, index) => tracks.findIndex((other) => other.id === item.id) === index);
    if (!unique.length) return;
    const ordered = shuffle ? [...unique].sort(() => Math.random() - 0.5) : unique;
    player.play(ordered[0], ordered);
  }, [feed.shelves, player]);

  const playContainer = useCallback(async (item: MediaItem) => {
    if (!item.browseId) return;
    setLoading(true); setError(null); setCollection(item); setTitle(item.title); setSubtitle(item.subtitle || `Browse this ${item.type}`);
    try {
      const result = await musicApi.browse(item.browseId, item.browseParams);
      setFeed(result);
      const tracks = result.shelves.flatMap((shelf) => shelf.items).filter((track) => track.videoId);
      const unique = tracks.filter((track, index) => tracks.findIndex((other) => other.id === track.id) === index);
      if (unique.length) player.play(unique[0], unique);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Could not play this collection");
    } finally {
      setLoading(false);
    }
  }, [player]);

  const chooseChip = useCallback((chip: string) => {
    setActiveChip(chip);
    if (chip === "All") { loadHome(); return; }
    setView("home");
    setTitle(chip);
    setSubtitle(`Music for ${chip.toLowerCase()} moments.`);
    setLoading(true);
    musicApi.search(`${chip} music`).then((result) => {
      setFeed({ ...result, chips: feed.chips });
      setNextPage(1);
      setHomeContinuation(result.continuation || null);
    }).catch((reason) => setError(reason instanceof Error ? reason.message : "Could not load this mood"))
      .finally(() => setLoading(false));
  }, [feed.chips, loadHome]);

  return (
    <div className="app-shell" style={{ "--art-color": artworkColor } as CSSProperties}>
      <div className="ambient" />
      {player.current?.thumbnail && (
        <img
          className="artwork-ambient"
          src={player.current.thumbnail}
          alt=""
          referrerPolicy="no-referrer"
          onError={(e) => { e.currentTarget.style.display = "none"; }}
        />
      )}
      <Sidebar active={view} onNavigate={navigate} onSelectPlaylist={openPlaylist} />
      <main className="main-area">
        <Topbar
          query={query}
          setQuery={setQuery}
          onSearch={search}
          userName={displayName}
          onOpenProfile={() => setView("profile")}
        />
        <div className="page-content">
          {view === "profile" ? (
            <ProfilePage onBack={() => setView("home")} />
          ) : player.selectedArtistForView ? (
            <ArtistPage
              artistName={player.selectedArtistForView}
              onBack={() => player.closeArtistView()}
            />
          ) : (
            <>
              {collection ? (
                <section className="collection-header">
                  <MediaArt item={collection} className="collection-art" />
                  <div>
                    <span>{collection.type.toUpperCase()}</span>
                    <h1>{collection.title}</h1>
                    <p>{collection.subtitle}</p>
                    <div className="collection-actions">
                      <button onClick={() => playCollection(false)}><Play fill="currentColor" />Play all</button>
                      <button onClick={() => playCollection(true)}><Shuffle />Shuffle</button>
                    </div>
                  </div>
                </section>
              ) : view !== "home" && !exploreLanding ? (
                <section className="home-heading">
                  <h1>{title}</h1>
                  <p>{subtitle}</p>
                </section>
              ) : null}
              {view === "home" && (
                <div className="mood-chips">
                  {["All", ...(feed.chips || ["Relax", "Energize", "Workout", "Commute", "Focus"])].map((chip) => (
                    <button key={chip} className={activeChip === chip ? "active" : ""} onClick={() => chooseChip(chip)}>
                      {chip}
                    </button>
                  ))}
                </div>
              )}
              {loading ? (
                <div className="state"><LoaderCircle className="spin" /><p>Loading music…</p></div>
              ) : error ? (
                <div className="state error">
                  <p>{error}</p>
                  <button onClick={exploreLanding ? loadExplore : loadHome}><RefreshCw size={15} />Try again</button>
                </div>
              ) : exploreLanding ? (
                <ExplorePage shelves={feed.shelves} moods={exploreMoods} onSelect={selectItem} onPlayAll={playContainer} onBrowse={browseExplore} onMood={browseMood} />
              ) : feed.shelves.length ? (
                feed.shelves.map((shelf) => (
                  <Fragment key={shelf.id}>
                    <Shelf shelf={shelf} onSelect={selectItem} onPlayAll={playContainer} />
                    {shelf.id === "discover-1" && <TasteBuilder items={shelf.items} onExplore={() => search("Top artists")} />}
                  </Fragment>
                ))
              ) : (
                <div className="state"><p>No playable results found yet.</p></div>
              )}
              {view === "home" && (
                <div ref={loadMoreRef} className="load-more-sentinel">
                  {loadingMore ? <><LoaderCircle className="spin" /> Loading more</> : nextPage == null ? "You’re all caught up" : ""}
                </div>
              )}
            </>
          )}
        </div>
      </main>
      <QueuePanel />
      <FullscreenPlayer />
      <PlayerBar />
      <ListeningRoomPanel />
      <AddToPlaylistModal />
      <SongShareModal />
    </div>
  );
}
