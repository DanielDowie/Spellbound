-- Spellbound: participant-controlled permanent match deletion
-- Run once in Supabase SQL Editor.
create or replace function public.spellbound_delete_match(p_match_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare deleted_count integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.spellbound_matches
 where id=p_match_id and (host_id=auth.uid() or guest_id=auth.uid());
 get diagnostics deleted_count = row_count;
 return deleted_count > 0;
end $$;
create or replace function public.spellbound_delete_all_my_matches()
returns integer language plpgsql security definer set search_path = ''
as $$
declare deleted_count integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.spellbound_matches
 where host_id=auth.uid() or guest_id=auth.uid();
 get diagnostics deleted_count = row_count;
 return deleted_count;
end $$;
revoke all on function public.spellbound_delete_match(uuid) from public,anon;
revoke all on function public.spellbound_delete_all_my_matches() from public,anon;
grant execute on function public.spellbound_delete_match(uuid) to authenticated;
grant execute on function public.spellbound_delete_all_my_matches() to authenticated;
-- Existing spellbound_turns FK has ON DELETE CASCADE, so turn history is removed too.
