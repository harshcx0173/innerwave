from __future__ import annotations

import unittest

from app.recommendations import rank_queue, recommendation_queries


def item(
    video_id: str,
    title: str,
    artist: str,
    *,
    subtitle_prefix: str = "Song",
    duration: str = "3:30",
) -> dict:
    return {
        "id": video_id,
        "videoId": video_id,
        "title": title,
        "artists": [artist],
        "subtitle": f"{subtitle_prefix} · {artist}",
        "duration": duration,
        "type": "song",
    }


class RecommendationRankingTests(unittest.TestCase):
    def test_removes_same_recording_podcasts_devotional_and_long_form(self) -> None:
        candidates = [
            item("duplicate", "Vaaroon Forever Lyrics", "Shreya Ghoshal"),
            item("reprise", "Vaaroon Reprise", "Shreya Ghoshal"),
            item("podcast", "Cinema Podcast Episode 18", "Host", subtitle_prefix="Podcast"),
            item("bhajan", "Morning Hanuman Bhajan", "Singer"),
            item("long", "A very long conversation", "Host", duration="1:04:00"),
            item("album", "Shreya Ghoshal Greatest Hits Full Album", "Uploader"),
            item("top-ten", "Shreya Ghoshal Top 10 Songs | Best Of", "Uploader"),
            item("valid-1", "Saibo", "Shreya Ghoshal"),
            item("valid-2", "Iktara", "Kavita Seth"),
        ]

        result = rank_queue(
            candidates,
            video_id="seed",
            title='Vaaroon Forever (From "Mirzapur The Movie")',
            artist="Shreya Ghoshal, Romy",
        )

        self.assertEqual([value["videoId"] for value in result], ["valid-1", "valid-2"])

    def test_collaboration_variants_do_not_bypass_seed_artist_diversity(self) -> None:
        candidates = [
            item(f"seed-artist-{index}", title, artist)
            for index, (title, artist) in enumerate([
                ("Alpha", "Shreya Ghoshal"),
                ("Bravo", "Shreya Ghoshal & Singer One"),
                ("Charlie", "Composer & Shreya Ghoshal"),
                ("Delta", "Shreya Ghoshal & Singer Two"),
                ("Echo", "Singer Three & Shreya Ghoshal"),
                ("Foxtrot", "Shreya Ghoshal & Singer Four"),
            ])
        ] + [item("discovery", "Different song", "Different Artist")]

        result = rank_queue(candidates, title="Seed song", artist="Shreya Ghoshal", limit=6)

        self.assertIn("discovery", [value["videoId"] for value in result])
        self.assertEqual(
            sum("shreya" in " ".join(value["artists"]).lower() for value in result),
            5,
        )

    def test_removes_duplicate_official_video_title(self) -> None:
        candidates = [
            item("song", "Do Numbari", "Dhanda Nyoliwala"),
            item(
                "video",
                "Dhanda Nyoliwala - Do Numbari (Official Video) | Mirzapur The Movie",
                "Dhanda Nyoliwala",
                subtitle_prefix="Video",
            ),
        ]

        result = rank_queue(candidates, title="Another seed", artist="Another Artist")

        self.assertEqual([value["videoId"] for value in result], ["song"])

    def test_removes_one_word_upload_variants_even_when_channel_differs(self) -> None:
        candidates = [
            item("song", "Ghoom Ghoom", "Rashmeet Kaur"),
            item(
                "video",
                "Ghoom Ghoom Official Video Telugu | Mirzapur The Movie",
                "Uploader channel",
                subtitle_prefix="Video",
            ),
        ]

        result = rank_queue(candidates, title="Another seed", artist="Another Artist")

        self.assertEqual([value["videoId"] for value in result], ["song"])

    def test_devotional_seed_keeps_devotional_music(self) -> None:
        result = rank_queue(
            [item("bhajan", "Shiv Bhajan", "Singer")],
            video_id="seed",
            title="Mahadev Aarti",
            artist="Singer",
        )

        self.assertEqual([value["videoId"] for value in result], ["bhajan"])

    def test_limits_one_artist_before_discovery_tracks(self) -> None:
        candidates = [
            item(f"same-{index}", title, "Seed Artist")
            for index, title in enumerate(["Alpha", "Bravo", "Charlie", "Delta", "Echo"])
        ] + [
            item("discovery-1", "Discovery one", "Another Artist"),
            item("discovery-2", "Discovery two", "Third Artist"),
        ]

        result = rank_queue(candidates, title="Seed", artist="Seed Artist", limit=5)
        ids = [value["videoId"] for value in result]

        self.assertIn("discovery-1", ids)
        self.assertIn("discovery-2", ids)
        self.assertEqual(sum(value.startswith("same-") for value in ids), 3)

    def test_queries_include_artist_and_movie_context(self) -> None:
        queries = recommendation_queries(
            'Vaaroon Forever (From "Mirzapur The Movie")',
            "Shreya Ghoshal, Romy",
        )

        self.assertIn("Shreya Ghoshal radio songs", queries)
        self.assertIn("Mirzapur The Movie songs", queries)


if __name__ == "__main__":
    unittest.main()
