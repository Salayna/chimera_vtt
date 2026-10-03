-- Players' characters (docs/SYSTEMS.md): made on a user's home, each for
-- one system, owned by whoever made it. The app checks a sheet against its
-- system's pack; the table bounds its size and keeps it to its owner. The
-- GMs of linked campaigns get read access with linking.
create table public.characters (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- A pack id, built in or installed, checked like one: not a foreign key.
  system text not null check (system ~ '^[a-z0-9][a-z0-9-]{0,39}$'),
  name text not null check (char_length(name) between 1 and 60),
  sheet jsonb not null default '{}' check (octet_length(sheet::text) <= 262144),
  updated_at timestamptz not null default now()
);

create index characters_owner_idx on public.characters (owner);

alter table public.characters enable row level security;

-- Anonymous players own characters too, for as long as their session.
create policy "characters: owners read theirs"
on public.characters for select
to authenticated
using (owner = (select auth.uid()));

create policy "characters: owners make theirs"
on public.characters for insert
to authenticated
with check (owner = (select auth.uid()));

create policy "characters: owners change theirs"
on public.characters for update
to authenticated
using (owner = (select auth.uid()))
with check (owner = (select auth.uid()));

create policy "characters: owners remove theirs"
on public.characters for delete
to authenticated
using (owner = (select auth.uid()));
