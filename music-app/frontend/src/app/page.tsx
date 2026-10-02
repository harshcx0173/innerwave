import { MusicApp } from "@/components/music-app";
import { AuthGate } from "@/components/auth-gate";
import { AuthProvider } from "@/context/auth-context";
import { PlayerProvider } from "@/context/player-context";
import { ConnectProvider } from "@/context/connect-context";
import { PresenceReporter } from "@/components/presence-reporter";

export default function Home() {
  return <AuthProvider><AuthGate><PlayerProvider><ConnectProvider><PresenceReporter /><MusicApp /></ConnectProvider></PlayerProvider></AuthGate></AuthProvider>;
}
