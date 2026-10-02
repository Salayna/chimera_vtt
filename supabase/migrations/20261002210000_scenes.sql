-- A campaign's scenes, each the whole scene as the app saves it (the same
-- JSON as a scene file). Only the GM reads them: players get the live scene
-- from the GM over Realtime, already filtered, so hidden tokens stay hidden.
create table public.scenes (
  id uuid primary key default gen_random_uuid(),
  campaign uuid not null references public.campaigns (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index scenes_campaign_idx on public.scenes (campaign);

-- The scene the room shows, so reopening the campaign resumes it.
alter table public.campaigns
  add column live_scene uuid references public.scenes (id) on delete set null;

create index campaigns_live_scene_idx on public.campaigns (live_scene);

alter table public.scenes enable row level security;

create policy "scenes: campaign owners do everything"
on public.scenes for all
to authenticated
using (
  exists (
    select 1 from public.campaigns c
    where c.id = scenes.campaign and c.owner = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.campaigns c
    where c.id = scenes.campaign and c.owner = (select auth.uid())
  )
);
