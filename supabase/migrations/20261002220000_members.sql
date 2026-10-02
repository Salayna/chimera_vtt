-- A campaign's members: players who entered its room at least once, signed
-- in or anonymous, with the name and colour they chose. Token owners are
-- members, so the GM can give a token to someone who isn't connected.
create table public.members (
  campaign uuid not null references public.campaigns (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  -- An index into the app's player palette.
  color smallint not null check (color between 0 and 15),
  joined_at timestamptz not null default now(),
  primary key (campaign, user_id)
);

create index members_user_idx on public.members (user_id);

-- Whether the caller is a member of [campaign]. Security definer so the
-- members policy can ask without recursing into itself.
create function public.is_member(campaign uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.members m
    where m.campaign = is_member.campaign and m.user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_member(uuid) from public, anon;
grant execute on function public.is_member(uuid) to authenticated;

alter table public.members enable row level security;

-- The GM sees their campaign's members; a member sees their fellow members
-- (names and colours at the table).
create policy "members: owners and fellow members read"
on public.members for select
to authenticated
using (
  exists (
    select 1 from public.campaigns c
    where c.id = members.campaign and c.owner = (select auth.uid())
  )
  or public.is_member(members.campaign)
);

create policy "members: owners remove"
on public.members for delete
to authenticated
using (
  exists (
    select 1 from public.campaigns c
    where c.id = members.campaign and c.owner = (select auth.uid())
  )
);

-- Entering a room: the only way in. Checks the code and adds the caller as
-- a member (or updates their name and colour), and returns the campaign's
-- id, or null for a code no campaign has. A removed member who still has
-- the code can come back; changing the code is what keeps them out.
create function public.join_campaign(code text, name text, color smallint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  found uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'sign in first';
  end if;
  select c.id into found from public.campaigns c where c.room_code = upper(code);
  if found is null then
    return null;
  end if;
  insert into public.members (campaign, user_id, name, color)
  values (found, (select auth.uid()), trim(join_campaign.name), join_campaign.color)
  on conflict (campaign, user_id)
    do update set name = excluded.name, color = excluded.color;
  return found;
end;
$$;

revoke execute on function public.join_campaign(text, text, smallint) from public, anon;
grant execute on function public.join_campaign(text, text, smallint) to authenticated;
