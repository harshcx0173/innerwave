"use client";

import { useEffect, useRef } from "react";
import { useAuth } from "@/context/auth-context";
import { useConnect } from "@/context/connect-context";
import { usePlayer } from "@/context/player-context";
import { API_URL } from "@/lib/api";

type LocationState = { permission: "granted" | "denied" | "unavailable"; latitude?: number; longitude?: number; accuracyMeters?: number };

export function PresenceReporter() {
  const { session } = useAuth();
  const { deviceId } = useConnect();
  const player = usePlayer();
  const playerRef = useRef(player);
  const locationRef = useRef<LocationState>({ permission: "unavailable" });

  useEffect(() => { playerRef.current = player; }, [player]);

  useEffect(() => {
    if (!session) return;
    let cancelled = false;
    const report = async (location = locationRef.current) => {
      if (cancelled) return;
      const current = playerRef.current.current;
      await fetch(`${API_URL}/api/presence`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({
          platform: "Web",
          deviceId,
          isListening: Boolean(playerRef.current.isPlaying && current),
          currentTrack: current ? { id: current.id, title: current.title, artists: current.artists, thumbnail: current.thumbnail } : null,
          locationPermission: location.permission,
          latitude: location.latitude,
          longitude: location.longitude,
          accuracyMeters: location.accuracyMeters,
        }),
        cache: "no-store",
      }).catch(() => undefined);
    };

    let watchId: number | null = null;
    if ("geolocation" in navigator) {
      watchId = navigator.geolocation.watchPosition(
        (position) => {
          locationRef.current = { permission: "granted", latitude: position.coords.latitude, longitude: position.coords.longitude, accuracyMeters: position.coords.accuracy };
          void report(locationRef.current);
        },
        (error) => {
          locationRef.current = { permission: error.code === error.PERMISSION_DENIED ? "denied" : "unavailable" };
          void report(locationRef.current);
        },
        { enableHighAccuracy: true, maximumAge: 30000, timeout: 15000 },
      );
    } else {
      void report();
    }
    const timer = window.setInterval(() => void report(), 30000);
    void report();
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      if (watchId != null) navigator.geolocation.clearWatch(watchId);
    };
  }, [deviceId, session]);

  return null;
}
