-- Spellbound online match turn storage (migration 002)
-- Run after schema.sql. This adds a guarded atomic turn log, not client-trusted HP/damage.
alter table public.spellbound_matches
 add column if not exists game_state jsonb not null default '{}'::jsonb;

create or replace function public.spellbound_submit_turn(
 p_match_id uuid,
 p_expected_turn integer,
 p_move jsonb
) returns integer
language plpgsql security definer set search_path = ''
as $$
declare m public.spellbound_matches;
declare next_turn integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_move is null or jsonb_typeof(p_move) <> 'object'
    or length(p_move::text)>8192 then raise exception 'Invalid move'; end if;
 -- Only action descriptions are accepted. Never accept HP, mana, board, score or winner
 -- from a browser until server-side word and combat validation is implemented.
 if p_move ? 'hp' or p_move ? 'mana' or p_move ? 'damage'
    or p_move ? 'board' or p_move ? 'winner' or p_move ? 'scores'
    or p_move ? 'game_state' then raise exception 'Untrusted game-state field'; end if;
 select * into m from public.spellbound_matches
  where id=p_match_id for update;
 if m.id is null or m.status <> 'active' then raise exception 'Match unavailable'; end if;
 if m.host_id <> auth.uid() and m.guest_id <> auth.uid()
    then raise exception 'Not a player'; end if;
 if m.current_player is distinct from auth.uid()
    then raise exception 'Not your turn'; end if;
 if m.turn_number <> p_expected_turn then raise exception 'Outdated turn'; end if;
 next_turn := m.turn_number+1;
 insert into public.spellbound_turns(match_id,turn_number,player_id,move)
 values(m.id,next_turn,auth.uid(),p_move);
 update public.spellbound_matches
 set turn_number=next_turn,
     current_player=case when auth.uid()=host_id then guest_id else host_id end,
     updated_at=now()
 where id=m.id;
 return next_turn;
end $$;
revoke all on function public.spellbound_submit_turn(uuid,integer,jsonb) from public,anon;
grant execute on function public.spellbound_submit_turn(uuid,integer,jsonb) to authenticated;
-- This is infrastructure only. Combat moves must be validated before being enabled in UI.
