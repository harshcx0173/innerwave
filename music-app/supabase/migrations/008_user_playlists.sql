-- Migration: 008_user_playlists.sql
-- Description: Create tables and RLS policies for custom user playlists and playlist items

CREATE TABLE IF NOT EXISTS public.user_playlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    cover_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_playlist_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID NOT NULL REFERENCES public.user_playlists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    song JSONB NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_playlists_user_id ON public.user_playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_user_playlist_items_playlist_id ON public.user_playlist_items(playlist_id);
CREATE INDEX IF NOT EXISTS idx_user_playlist_items_user_id ON public.user_playlist_items(user_id);

-- Enable RLS
ALTER TABLE public.user_playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_playlist_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_playlists
CREATE POLICY "Users can view their own playlists"
    ON public.user_playlists
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own playlists"
    ON public.user_playlists
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own playlists"
    ON public.user_playlists
    FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own playlists"
    ON public.user_playlists
    FOR DELETE
    USING (auth.uid() = user_id);

-- RLS Policies for user_playlist_items
CREATE POLICY "Users can view their own playlist items"
    ON public.user_playlist_items
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own playlist items"
    ON public.user_playlist_items
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own playlist items"
    ON public.user_playlist_items
    FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own playlist items"
    ON public.user_playlist_items
    FOR DELETE
    USING (auth.uid() = user_id);
