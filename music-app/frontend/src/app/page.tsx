import { MusicApp } from "@/components/music-app";
import { PlayerProvider } from "@/context/player-context";

export default function Home() {
  return <PlayerProvider><MusicApp /></PlayerProvider>;
}
