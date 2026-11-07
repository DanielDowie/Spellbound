-- Spellbound multiplayer foundation v1
-- Run in Supabase SQL Editor. No secret keys belong in GitHub.
create extension if not exists pgcrypto;

create table if not exists public.spellbound_matches (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(9),'hex'),1,12)),
  host_id uuid not null references auth.users(id),
  guest_id uuid references auth.users(id),
  status text not null default 'waiting' check (status in ('waiting','active','finished')),
  current_player uuid references auth.users(id),
  turn_number integer not null default 0 check (turn_number >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint distinct_players check (guest_id is null or guest_id <> host_id)
);
create index if not exists spellbound_matches_host_idx on public.spellbound_matches(host_id);
create index if not exists spellbound_matches_guest_idx on public.spellbound_matches(guest_id);

create table if not exists public.spellbound_turns (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.spellbound_matches(id) on delete cascade,
  turn_number integer not null check (turn_number > 0),
  player_id uuid not null references auth.users(id),
  move jsonb not null,
  created_at timestamptz not null default now(),
  unique (match_id, turn_number)
);
create index if not exists spellbound_turns_match_idx on public.spellbound_turns(match_id,turn_number);

alter table public.spellbound_matches enable row level security;
alter table public.spellbound_turns enable row level security;

-- Members may view their own matches. Invites are joined using an RPC, not a public table scan.
create policy "members can read matches" on public.spellbound_matches for select to authenticated
  using (auth.uid() = host_id or auth.uid() = guest_id);
create policy "members can read turns" on public.spellbound_turns for select to authenticated
  using (exists(select 1 from public.spellbound_matches m where m.id = match_id
    and (m.host_id = auth.uid() or m.guest_id = auth.uid())));

-- No direct client insert/update/delete policies. Writes go through controlled functions.
create or replace function public.spellbound_create_match()
returns table(match_id uuid, code text)
language plpgsql security definer set search_path = ''
as $$
declare m public.spellbound_matches;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  insert into public.spellbound_matches(host_id,current_player)
    values(auth.uid(),auth.uid()) returning * into m;
  return query select m.id,m.invite_code;
end $$;

create or replace function public.spellbound_join_match(p_code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare m public.spellbound_matches;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.spellbound_matches
     set guest_id=auth.uid(),status='active',updated_at=now()
   where invite_code=upper(trim(p_code)) and status='waiting'
     and guest_id is null and host_id <> auth.uid()
   returning * into m;
  if m.id is null then raise exception 'Invite unavailable or already used'; end if;
  return m.id;
end $$;

revoke all on function public.spellbound_create_match() from public,anon;
revoke all on function public.spellbound_join_match(text) from public,anon;
grant execute on function public.spellbound_create_match() to authenticated;
grant execute on function public.spellbound_join_match(text) to authenticated;

-- Turn submission and game-state validation are intentionally NOT enabled yet.
-- They must be implemented together so the browser cannot forge damage, mana or wins.
