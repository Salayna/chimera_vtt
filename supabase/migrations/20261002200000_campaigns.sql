-- A campaign: everything one group plays with, owned by one signed-in GM.
-- Its room code is the Realtime channel players join (room:<code>); it
-- stays the same across sessions until the GM changes it.
create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  -- The app's alphabet: no 0/O, 1/I/L.
  room_code text not null unique check (room_code ~ '^[A-HJKMNP-Z2-9]{6}$'),
  created_at timestamptz not null default now()
);

create index campaigns_owner_idx on public.campaigns (owner);

alter table public.campaigns enable row level security;

create policy "campaigns: owners read theirs"
on public.campaigns for select
to authenticated
using (owner = (select auth.uid()));

-- Anonymous sign-ins (players) are `authenticated` too; only a GM with an
-- account may own a campaign.
create policy "campaigns: signed-in GMs create theirs"
on public.campaigns for insert
to authenticated
with check (
  owner = (select auth.uid())
  and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
);

create policy "campaigns: owners update theirs"
on public.campaigns for update
to authenticated
using (owner = (select auth.uid()))
with check (owner = (select auth.uid()));

create policy "campaigns: owners delete theirs"
on public.campaigns for delete
to authenticated
using (owner = (select auth.uid()));
