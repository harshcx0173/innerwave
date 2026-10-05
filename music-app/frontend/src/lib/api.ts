import type { Feed, MediaItem } from "./types";

export const API_URL = process.env.NEXT_PUBLIC_API_URL || "/backend";

async function getJson<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, { signal, cache: "no-store" });
  if (!response.ok) {
    const payload = await response.json().catch(() => null);
    throw new Error(payload?.detail || `Request failed (${response.status})`);
  }
  return response.json() as Promise<T>;
}

type LyricsPayload = { lyrics: string; source?: string | null; lines: { time: number; text: string }[]; synced: boolean; syncSource?: string | null };
const lyricsCache = new Map<string, { expires: number; value: LyricsPayload }>();
const lyricsInFlight = new Map<string, Promise<LyricsPayload>>();

function withAbort<T>(request: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return request;
  if (signal.aborted) return Promise.reject(new DOMException("Aborted", "AbortError"));
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(new DOMException("Aborted", "AbortError"));
    signal.addEventListener("abort", abort, { once: true });
    request.then(resolve, reject).finally(() => signal.removeEventListener("abort", abort));
  });
}

export const musicApi = {
  home: (signal?: AbortSignal) => getJson<Feed>("/api/home", signal),
  search: (query: string, continuation?: string | null, signal?: AbortSignal) =>
    getJson<Feed>(
      `/api/search?q=${encodeURIComponent(query)}${continuation ? `&continuation=${encodeURIComponent(continuation)}` : ""}`,
      signal,
    ),
  browse: (id: string, params?: string | null, signal?: AbortSignal) =>
    getJson<Feed>(
      `/api/browse?id=${encodeURIComponent(id)}${params ? `&params=${encodeURIComponent(params)}` : ""}`,
      signal,
    ),
  next: (item: MediaItem, continuation?: string | null) => {
    const query = new URLSearchParams({
      videoId: item.videoId || "",
      title: item.title,
      artist: item.artists.join(", ") || item.subtitle.split(" · ")[0] || "",
    });
    if (continuation) query.set("continuation", continuation);
    if (item.playlistId) query.set("playlistId", item.playlistId);
    if (item.watchParams) query.set("params", item.watchParams);
    if (item.index != null) query.set("index", String(item.index));
    return getJson<{ items: MediaItem[]; continuation?: string | null }>(`/api/next?${query}`);
  },
  lyrics: (item: MediaItem, duration?: number, signal?: AbortSignal) => {
    const artist = item.artists.join(", ") || item.subtitle.split(" · ")[0] || "";
    const query = new URLSearchParams({ videoId: item.videoId || "", title: item.title, artist });
    if (duration && Number.isFinite(duration)) query.set("duration", String(duration));
    const key = `${item.videoId || item.id}:${duration ? Math.round(duration) : 0}`;
    const cached = lyricsCache.get(key);
    if (cached && cached.expires > Date.now()) return withAbort(Promise.resolve(cached.value), signal);
    let request = lyricsInFlight.get(key);
    if (!request) {
      request = getJson<LyricsPayload>(`/api/lyrics?${query}`).then((value) => {
        lyricsCache.set(key, { value, expires: Date.now() + 12 * 60 * 60 * 1000 });
        return value;
      }).finally(() => lyricsInFlight.delete(key));
      lyricsInFlight.set(key, request);
    }
    return withAbort(request, signal);
  },
  related: (item: MediaItem, signal?: AbortSignal) => {
    const artist = item.artists.join(", ") || item.subtitle.split(" · ")[0] || "";
    const query = new URLSearchParams({ videoId: item.videoId || "", title: item.title, artist });
    return getJson<Feed>(`/api/related?${query}`, signal);
  },
  moreHome: (page: number, continuation?: string | null, seed?: string) =>
    getJson<Feed>(
      `/api/home/more?page=${page}${continuation ? `&continuation=${encodeURIComponent(continuation)}` : ""}${seed ? `&seed=${encodeURIComponent(seed)}` : ""}`,
    ),
  recommendations: (artists: string[]) =>
    getJson<Feed>(`/api/recommendations?artists=${encodeURIComponent(artists.join(","))}`),
};
