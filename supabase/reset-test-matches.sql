-- Spellbound: clear all test matches and turn history.
-- Run ONCE in the Supabase SQL Editor for the Spellbound project.
-- This permanently deletes ALL current multiplayer matches and their turns.
-- It does not delete accounts, settings, or the solo game.
begin;
truncate table public.spellbound_turns, public.spellbound_matches restart identity;
commit;
