-- Spellbound multiplayer turn synchronization (migration 003)
-- Execute after 002_turns.sql in Supabase SQL Editor.
-- This is a trusted turn-sequencing foundation, not a server-validated combat engine.
alter table public.spellbound_matches add column if not exists game_state jsonb not null default '{}'::jsonb;
create or replace function public.spellbound_save_turn(p_match_id uuid,p_expected_turn integer,p_action jsonb,p_state jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare m public.spellbound_matches; n integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if jsonb_typeof(p_action) <> 'object' or jsonb_typeof(p_state) <> 'object'
    or length(p_action::text)>8192 or length(p_state::text)>120000
 then raise exception 'Invalid turn payload'; end if;
 select * into m from public.spellbound_matches where id=p_match_id for update;
 if m.id is null or m.status <> 'active' then raise exception 'Match unavailable'; end if;
 if auth.uid() <> m.host_id and auth.uid() <> m.guest_id then raise exception 'Not a participant'; end if;
 if m.current_player is distinct from auth.uid() then raise exception 'Not your turn'; end if;
 if m.turn_number <> p_expected_turn then raise exception 'Match has advanced'; end if;
 n:=m.turn_number+1;
 insert into public.spellbound_turns(match_id,turn_number,player_id,move)
 values(m.id,n,auth.uid(),p_action);
 update public.spellbound_matches
 set game_state=p_state,turn_number=n,
 current_player=case when auth.uid()=host_id then guest_id else host_id end,
 updated_at=now()
 where id=m.id;
 return n;
end $$;
revoke all on function public.spellbound_save_turn(uuid,integer,jsonb,jsonb) from public,anon;
grant execute on function public.spellbound_save_turn(uuid,integer,jsonb,jsonb) to authenticated;
-- SECURITY LIMITATION: clients can currently submit forged game_state.
-- Do not use for competitive/ranked matches until move legality, damage and bag draws
-- are validated on a trusted server.
