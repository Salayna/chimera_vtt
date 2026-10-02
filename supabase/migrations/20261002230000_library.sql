-- A GM's library: the images they've uploaded, shared by all their
-- campaigns, to pick from instead of uploading again. The images live in
-- Storage by content hash (ADR 006); a row only names one and points at it
-- and at a small thumbnail.
create table public.library (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('map', 'token')),
  name text not null check (char_length(name) between 1 and 80),
  asset text not null check (asset ~ '^[0-9a-f]{64}$'),
  thumb text not null check (thumb ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  -- The same image uploaded again is the same entry. Also serves listing a
  -- GM's maps or tokens (owner, kind).
  unique (owner, kind, asset)
);

alter table public.library enable row level security;

create policy "library: owners read theirs"
on public.library for select
to authenticated
using (owner = (select auth.uid()));

-- Players are anonymous sign-ins; only a GM with an account has a library.
create policy "library: signed-in GMs add to theirs"
on public.library for insert
to authenticated
with check (
  owner = (select auth.uid())
  and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
);

create policy "library: owners rename theirs"
on public.library for update
to authenticated
using (owner = (select auth.uid()))
with check (owner = (select auth.uid()));

create policy "library: owners delete theirs"
on public.library for delete
to authenticated
using (owner = (select auth.uid()));
