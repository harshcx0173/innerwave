from __future__ import annotations

import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app import main


def call_next(*, continuation: str | None = None) -> dict:
    return main.next_tracks(
        videoId="seed-video",
        playlistId=None,
        params=None,
        index=None,
        continuation=continuation,
        title="Seed song",
        artist="Seed artist",
    )


class NextQueueTests(unittest.TestCase):
    @patch.object(main, "_search_recommendations")
    @patch.object(main, "parse_feed")
    @patch.object(main.service, "next")
    def test_uses_youtube_radio_before_search_fallback(
        self,
        service_next,
        parse_feed,
        search_recommendations,
    ) -> None:
        service_next.return_value = {"raw": "radio"}
        names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima"]
        radio_items = [
            {"videoId": f"related-{index}", "title": f"Track {name}", "artists": [f"Artist {name}"]}
            for index, name in enumerate(names)
        ]
        parse_feed.return_value = {
            "shelves": [{"id": "up-next", "items": radio_items}],
            "continuation": "next-page-token",
        }

        result = call_next()

        self.assertEqual(result["source"], "youtube-radio")
        self.assertEqual(result["items"], radio_items)
        self.assertEqual(result["continuation"], "next-page-token")
        search_recommendations.assert_not_called()

    @patch.object(main, "_search_recommendations")
    @patch.object(main.service, "next", side_effect=TimeoutError("watch-next timed out"))
    def test_search_is_only_a_new_radio_fallback(
        self,
        service_next,
        search_recommendations,
    ) -> None:
        search_recommendations.return_value = [{"videoId": "fallback-1"}]

        result = call_next()

        self.assertEqual(result["source"], "search-radio-fallback")
        self.assertEqual(result["items"], [{"videoId": "fallback-1"}])
        self.assertIsNone(result["continuation"])
        search_recommendations.assert_called_once_with(
            "seed-video",
            "Seed song",
            "Seed artist",
        )

    @patch.object(main, "_search_recommendations")
    @patch.object(main, "parse_feed")
    @patch.object(main.service, "next")
    def test_replaces_a_polluted_radio_with_ranked_search(
        self,
        service_next,
        parse_feed,
        search_recommendations,
    ) -> None:
        service_next.return_value = {"raw": "radio"}
        parse_feed.return_value = {
            "shelves": [{"id": "up-next", "items": [{
                "videoId": "podcast",
                "title": "Unrelated podcast episode",
                "subtitle": "Podcast · Host",
            }]}],
            "continuation": None,
        }
        search_recommendations.return_value = [{
            "videoId": "good-song",
            "title": "A related song",
            "subtitle": "Song · Seed artist",
            "artists": ["Seed artist"],
        }]

        result = call_next()

        self.assertEqual(result["source"], "search-radio-fallback")
        self.assertEqual([item["videoId"] for item in result["items"]], ["good-song"])

    @patch.object(main, "_search_recommendations")
    @patch.object(main.service, "next", side_effect=TimeoutError("continuation timed out"))
    def test_continuation_failure_does_not_replace_existing_queue(
        self,
        service_next,
        search_recommendations,
    ) -> None:
        with self.assertRaises(HTTPException) as raised:
            call_next(continuation="next-page-token")

        self.assertEqual(raised.exception.status_code, 502)
        search_recommendations.assert_not_called()


if __name__ == "__main__":
    unittest.main()
