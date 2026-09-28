export type MediaType = "song" | "album" | "playlist" | "artist" | "unknown";

export type MediaItem = {
  id: string;
  videoId: string | null;
  browseId: string | null;
  browseParams: string | null;
  playlistId: string | null;
  title: string;
  subtitle: string;
  artists: string[];
  thumbnail: string | null;
  type: MediaType;
  duration: string | null;
  watchParams: string | null;
  index: number | null;
};

export type Shelf = {
  id: string;
  title: string;
  layout: "list" | "songs" | "carousel";
  items: MediaItem[];
};

export type Feed = {
  shelves: Shelf[];
  continuation?: string | null;
  source?: string;
  query?: string;
  chips?: string[];
  hasMore?: boolean;
  nextPage?: number | null;
};
