-- A GM's installed system packs: modules teaching the app a game system
-- (docs/PACKS.md), for all their campaigns. The app checks a pack's
-- content; the table keeps its id and bounds its size. A scene played with
-- one carries its own copy, so players never read this table.
create table public.packs (
  owner uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- The pack's own id, as scenes name it: one install per id and GM.
  id text not null check (id ~ '^[a-z0-9][a-z0-9-]{0,39}$'),
  name text not null check (char_length(name) between 1 and 60),
  version integer not null default 1,
  data jsonb not null check (octet_length(data::text) <= 262144),
  installed_at timestamptz not null default now(),
  primary key (owner, id)
);

alter table public.packs enable row level security;

create policy "packs: owners read theirs"
on public.packs for select
to authenticated
using (owner = (select auth.uid()));

-- Players are anonymous sign-ins; only a GM with an account installs packs.
create policy "packs: signed-in GMs install theirs"
on public.packs for insert
to authenticated
with check (
  owner = (select auth.uid())
  and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
);

-- Installing a newer version of a pack replaces it.
create policy "packs: owners update theirs"
on public.packs for update
to authenticated
using (owner = (select auth.uid()))
with check (owner = (select auth.uid()));

create policy "packs: owners remove theirs"
on public.packs for delete
to authenticated
using (owner = (select auth.uid()));
