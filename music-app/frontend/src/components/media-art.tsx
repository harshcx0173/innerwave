/* eslint-disable @next/next/no-img-element */
import { useState } from "react";
import { Disc3, Play, User } from "lucide-react";
import type { MediaItem } from "@/lib/types";

export function MediaArt({ item, className = "" }: { item: MediaItem; className?: string }) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);

  const primarySrc = item.thumbnail;
  const fallbackHq = item.videoId ? `https://i.ytimg.com/vi/${item.videoId}/hqdefault.jpg` : null;
  const fallbackMq = item.videoId ? `https://i.ytimg.com/vi/${item.videoId}/mqdefault.jpg` : null;

  let currentSrc: string | null = null;
  if (primarySrc && failedUrl !== primarySrc) {
    currentSrc = primarySrc;
  } else if (fallbackHq && failedUrl !== fallbackHq) {
    currentSrc = fallbackHq;
  } else if (fallbackMq && failedUrl !== fallbackMq) {
    currentSrc = fallbackMq;
  }

  const handleError = () => {
    if (currentSrc) {
      setFailedUrl(currentSrc);
    }
  };

  const isArtist = item.type === "artist";

  return (
    <div className={`group/art relative overflow-hidden bg-white/5 ${isArtist ? "rounded-full" : "rounded-2xl"} ${className}`}>
      {currentSrc ? (
        <img
          key={currentSrc}
          src={currentSrc}
          alt={item.title || ""}
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
          onError={handleError}
          className="h-full w-full object-cover transition duration-500 group-hover/art:scale-105"
        />
      ) : (
        <div className="grid h-full w-full place-items-center text-white/25">
          {isArtist ? <User size={28} /> : <Disc3 size={28} />}
        </div>
      )}
      {item.videoId && (
        <div className="absolute inset-0 grid place-items-center bg-black/30 opacity-0 transition group-hover/art:opacity-100">
          <span className="grid size-12 place-items-center rounded-full bg-white text-black shadow-xl">
            <Play size={20} fill="currentColor" />
          </span>
        </div>
      )}
    </div>
  );
}
