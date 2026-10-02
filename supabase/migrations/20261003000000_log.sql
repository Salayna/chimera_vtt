-- A campaign's log: rolls, chat messages and condition changes, as the
-- events the GM's session makes (the same JSON as on the wire). Only the GM
-- reads and writes it: players get the log from the GM over Realtime,
-- without the GM's secret rolls. Entries are never edited.
create table public.log_entries (
  id bigint generated always as identity primary key,
  campaign uuid not null references public.campaigns (id) on delete cascade,
  event jsonb not null check (pg_column_size(event) <= 8192),
  secret boolean not null default false,
  created_at timestamptz not null default now()
);

-- The room loads a campaign's latest entries.
create index log_entries_campaign_id_idx on public.log_entries (campaign, id desc);

alter table public.log_entries enable row level security;

create policy "log: campaign owners read"
on public.log_entries for select
to authenticated
using (
  exists (
    select 1 from public.campaigns c
    where c.id = log_entries.campaign and c.owner = (select auth.uid())
  )
);

create policy "log: campaign owners add"
on public.log_entries for insert
to authenticated
with check (
  exists (
    select 1 from public.campaigns c
    where c.id = log_entries.campaign and c.owner = (select auth.uid())
  )
);
