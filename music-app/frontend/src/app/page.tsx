import { MusicApp } from "@/components/music-app";
import { AuthGate } from "@/components/auth-gate";
import { AuthProvider } from "@/context/auth-context";
import { PlayerProvider } from "@/context/player-context";
import { ConnectProvider } from "@/context/connect-context";

export default function Home() {
  return <AuthProvider><AuthGate><PlayerProvider><ConnectProvider><MusicApp /></ConnectProvider></PlayerProvider></AuthGate></AuthProvider>;
}
