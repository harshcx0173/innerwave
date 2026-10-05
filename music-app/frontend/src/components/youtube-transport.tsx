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
  getPlayerState?: () => number;
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
        onReady: (event: { target: YoutubePlayer }) => void;
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
    const readyRef = useRef(false);
    const pendingRef = useRef<{ videoId: string; startSeconds: number; autoplay: boolean } | null>(null);
    const pendingSeekRef = useRef<number | null>(null);
    const desiredPlaybackRef = useRef<"play" | "pause" | "stop" | null>(null);
    const desiredVolumeRef = useRef(0.8);
    const targetSeekSecondsRef = useRef<number | null>(null);
    const callbacksRef = useRef({ onTime, onPlayingChange, onEnded, onError });
    callbacksRef.current = { onTime, onPlayingChange, onEnded, onError };

    const loadPending = () => {
      const player = playerRef.current;
      const pending = pendingRef.current;
      if (!readyRef.current || !player || !pending) return;
      if (pending.startSeconds > 0) {
        targetSeekSecondsRef.current = pending.startSeconds;
      }
      const options = { videoId: pending.videoId, startSeconds: pending.startSeconds };
      if (pending.autoplay && typeof player.loadVideoById === "function") player.loadVideoById(options);
      else if (typeof player.cueVideoById === "function") player.cueVideoById(options);
      pendingRef.current = null;
    };

    useImperativeHandle(ref, () => ({
      load(videoId, startSeconds, autoplay) {
        pendingRef.current = { videoId, startSeconds, autoplay };
        pendingSeekRef.current = null;
        if (startSeconds > 0) {
          targetSeekSecondsRef.current = startSeconds;
        }
        desiredPlaybackRef.current = autoplay ? "play" : "pause";
        loadPending();
      },
      play() {
        desiredPlaybackRef.current = "play";
        const player = playerRef.current;
        if (readyRef.current && typeof player?.playVideo === "function") player.playVideo();
      },
      pause() {
        desiredPlaybackRef.current = "pause";
        const player = playerRef.current;
        if (readyRef.current && typeof player?.pauseVideo === "function") player.pauseVideo();
      },
      stop() {
        pendingRef.current = null;
        pendingSeekRef.current = null;
        targetSeekSecondsRef.current = null;
        desiredPlaybackRef.current = "stop";
        const player = playerRef.current;
        if (readyRef.current && typeof player?.stopVideo === "function") player.stopVideo();
      },
      seek(seconds) {
        pendingSeekRef.current = seconds;
        targetSeekSecondsRef.current = seconds;
        const player = playerRef.current;
        if (readyRef.current && typeof player?.seekTo === "function") {
          player.seekTo(seconds, true);
          pendingSeekRef.current = null;
        }
      },
      setVolume(volume) {
        desiredVolumeRef.current = volume;
        const player = playerRef.current;
        if (readyRef.current && typeof player?.setVolume === "function") {
          player.setVolume(Math.round(volume * 100));
        }
      },
    }));

    useEffect(() => {
      let disposed = false;
      let timer = 0;
      let createdPlayer: YoutubePlayer | null = null;
      loadYoutubeApi().then((YT) => {
        if (disposed || !hostRef.current) return;
        createdPlayer = new YT.Player(hostRef.current, {
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
            onReady: ({ target }) => {
              if (disposed) {
                if (typeof target.destroy === "function") target.destroy();
                return;
              }
              playerRef.current = target;
              readyRef.current = true;
              if (typeof target.setVolume === "function") {
                target.setVolume(Math.round(desiredVolumeRef.current * 100));
              }
              loadPending();
              if (pendingSeekRef.current != null && typeof target.seekTo === "function") {
                targetSeekSecondsRef.current = pendingSeekRef.current;
                target.seekTo(pendingSeekRef.current, true);
                pendingSeekRef.current = null;
              }
              if (desiredPlaybackRef.current === "play" && typeof target.playVideo === "function") target.playVideo();
              else if (desiredPlaybackRef.current === "pause" && typeof target.pauseVideo === "function") target.pauseVideo();
              else if (desiredPlaybackRef.current === "stop" && typeof target.stopVideo === "function") target.stopVideo();
              timer = window.setInterval(() => {
                const player = playerRef.current;
                if (!readyRef.current || !player) return;
                const duration = typeof player.getDuration === "function" ? player.getDuration() || 0 : 0;
                const rawCurrentTime = typeof player.getCurrentTime === "function" ? player.getCurrentTime() || 0 : 0;
                const loadedFraction = typeof player.getVideoLoadedFraction === "function" ? player.getVideoLoadedFraction() || 0 : 0;
                const state = typeof player.getPlayerState === "function" ? player.getPlayerState() : -1;

                let currentTime = rawCurrentTime;
                if (targetSeekSecondsRef.current != null) {
                  const target = targetSeekSecondsRef.current;
                  // If player is still buffering or reporting a time far behind target, hold at target
                  if (state !== 1 || rawCurrentTime < Math.max(0, target - 2.5)) {
                    currentTime = target;
                  } else {
                    targetSeekSecondsRef.current = null;
                  }
                }

                callbacksRef.current.onTime(
                  currentTime,
                  duration,
                  duration * loadedFraction,
                );
              }, 500);
            },
            onStateChange: ({ data }) => {
              if (data === 1) {
                callbacksRef.current.onPlayingChange(true);
                const player = playerRef.current;
                const rawCurrentTime = typeof player?.getCurrentTime === "function" ? player.getCurrentTime() || 0 : 0;
                if (targetSeekSecondsRef.current != null && rawCurrentTime >= Math.max(0, targetSeekSecondsRef.current - 2.5)) {
                  targetSeekSecondsRef.current = null;
                }
              }
              if (data === 2) callbacksRef.current.onPlayingChange(false);
              if (data === 0) {
                targetSeekSecondsRef.current = null;
                callbacksRef.current.onEnded();
              }
            },
            onError: ({ data }) => callbacksRef.current.onError(`YouTube player error (${data}).`),
          },
        });
      }).catch(() => callbacksRef.current.onError("YouTube player could not be loaded."));
      return () => {
        disposed = true;
        if (timer) window.clearInterval(timer);
        readyRef.current = false;
        if (createdPlayer && typeof createdPlayer.destroy === "function") createdPlayer.destroy();
        playerRef.current = null;
      };
    }, []);

    return <div className="youtube-transport" aria-hidden="true"><div ref={hostRef} /></div>;
  },
);
