"use client";

import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";

type YoutubePlayer = {
  cueVideoById: (options: { videoId: string; startSeconds?: number }) => void;
  loadVideoById: (options: { videoId: string; startSeconds?: number }) => void;
  playVideo: () => void;
  pauseVideo: () => void;
  stopVideo: () => void;
  seekTo: (seconds: number, allowSeekAhead: boolean) => void;
  setVolume: (volume: number) => void;
  getCurrentTime: () => number;
  getDuration: () => number;
  getVideoLoadedFraction: () => number;
  destroy: () => void;
};

type YoutubeNamespace = {
  Player: new (
    element: HTMLElement,
    options: {
      width: string;
      height: string;
      playerVars: Record<string, string | number>;
      events: {
        onReady: () => void;
        onStateChange: (event: { data: number }) => void;
        onError: (event: { data: number }) => void;
      };
    },
  ) => YoutubePlayer;
};

declare global {
  interface Window {
    YT?: YoutubeNamespace;
    onYouTubeIframeAPIReady?: () => void;
  }
}

let apiPromise: Promise<YoutubeNamespace> | null = null;

function loadYoutubeApi() {
  if (window.YT?.Player) return Promise.resolve(window.YT);
  if (apiPromise) return apiPromise;
  apiPromise = new Promise<YoutubeNamespace>((resolve) => {
    const previous = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previous?.();
      if (window.YT) resolve(window.YT);
    };
    if (!document.querySelector('script[src="https://www.youtube.com/iframe_api"]')) {
      const script = document.createElement("script");
      script.src = "https://www.youtube.com/iframe_api";
      script.async = true;
      document.head.appendChild(script);
    }
  });
  return apiPromise;
}

export type YoutubeTransportHandle = {
  load: (videoId: string, startSeconds: number, autoplay: boolean) => void;
  play: () => void;
  pause: () => void;
  stop: () => void;
  seek: (seconds: number) => void;
  setVolume: (volume: number) => void;
};

type YoutubeTransportProps = {
  onTime: (currentTime: number, duration: number, buffered: number) => void;
  onPlayingChange: (playing: boolean) => void;
  onEnded: () => void;
  onError: (message: string) => void;
};

export const YoutubeTransport = forwardRef<YoutubeTransportHandle, YoutubeTransportProps>(
  function YoutubeTransport({ onTime, onPlayingChange, onEnded, onError }, ref) {
    const hostRef = useRef<HTMLDivElement>(null);
    const playerRef = useRef<YoutubePlayer | null>(null);
    const pendingRef = useRef<{ videoId: string; startSeconds: number; autoplay: boolean } | null>(null);
    const desiredVolumeRef = useRef(0.8);
    const callbacksRef = useRef({ onTime, onPlayingChange, onEnded, onError });
    callbacksRef.current = { onTime, onPlayingChange, onEnded, onError };

    const loadPending = () => {
      const player = playerRef.current;
      const pending = pendingRef.current;
      if (!player || !pending) return;
      const options = { videoId: pending.videoId, startSeconds: pending.startSeconds };
      if (pending.autoplay) player.loadVideoById(options);
      else player.cueVideoById(options);
      pendingRef.current = null;
    };

    useImperativeHandle(ref, () => ({
      load(videoId, startSeconds, autoplay) {
        pendingRef.current = { videoId, startSeconds, autoplay };
        loadPending();
      },
      play: () => playerRef.current?.playVideo(),
      pause: () => playerRef.current?.pauseVideo(),
      stop: () => playerRef.current?.stopVideo(),
      seek: (seconds) => playerRef.current?.seekTo(seconds, true),
      setVolume(volume) {
        desiredVolumeRef.current = volume;
        playerRef.current?.setVolume(Math.round(volume * 100));
      },
    }));

    useEffect(() => {
      let disposed = false;
      let timer = 0;
      loadYoutubeApi().then((YT) => {
        if (disposed || !hostRef.current) return;
        playerRef.current = new YT.Player(hostRef.current, {
          width: "200",
          height: "200",
          playerVars: {
            autoplay: 0,
            controls: 0,
            disablekb: 1,
            playsinline: 1,
            rel: 0,
            origin: window.location.origin,
          },
          events: {
            onReady: () => {
              playerRef.current?.setVolume(Math.round(desiredVolumeRef.current * 100));
              loadPending();
              timer = window.setInterval(() => {
                const player = playerRef.current;
                if (!player) return;
                const duration = player.getDuration() || 0;
                callbacksRef.current.onTime(
                  player.getCurrentTime() || 0,
                  duration,
                  duration * (player.getVideoLoadedFraction() || 0),
                );
              }, 500);
            },
            onStateChange: ({ data }) => {
              if (data === 1) callbacksRef.current.onPlayingChange(true);
              if (data === 0) callbacksRef.current.onEnded();
            },
            onError: ({ data }) => callbacksRef.current.onError(`YouTube player error (${data}).`),
          },
        });
      }).catch(() => callbacksRef.current.onError("YouTube player could not be loaded."));
      return () => {
        disposed = true;
        if (timer) window.clearInterval(timer);
        playerRef.current?.destroy();
        playerRef.current = null;
      };
    }, []);

    return <div className="youtube-transport" aria-hidden="true"><div ref={hostRef} /></div>;
  },
);
