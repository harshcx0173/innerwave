import { MusicApp } from "@/components/music-app";
import { AuthGate } from "@/components/auth-gate";
import { AuthProvider } from "@/context/auth-context";
import { PlayerProvider } from "@/context/player-context";
import { PlaylistProvider } from "@/context/playlist-context";
import { ConnectProvider } from "@/context/connect-context";
import { PresenceReporter } from "@/components/presence-reporter";
import { ListeningRoomProvider } from "@/context/listening-room-context";

export default function Home() {
  return (
    <AuthProvider>
      <AuthGate>
        <PlayerProvider>
          <PlaylistProvider>
            <ConnectProvider>
              <ListeningRoomProvider>
                <PresenceReporter />
                <MusicApp />
              </ListeningRoomProvider>
            </ConnectProvider>
          </PlaylistProvider>
        </PlayerProvider>
      </AuthGate>
    </AuthProvider>
  );
}
