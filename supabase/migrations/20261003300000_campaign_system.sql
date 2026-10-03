-- A campaign is played with one game system: every scene in it uses the
-- campaign's pack (docs/PACKS.md). Built-in systems aren't rows of
-- `packs`, so this is the pack's id, checked like one, not a foreign key.
alter table public.campaigns
  add column system text not null default 'generic'
  check (system ~ '^[a-z0-9][a-z0-9-]{0,39}$');

-- Existing campaigns keep the system their live scene was played with.
update public.campaigns c
set system = s.data -> 'entities' -> 0 ->> 'pack'
from public.scenes s
where s.id = c.live_scene
  and s.data -> 'entities' -> 0 ->> 'pack' ~ '^[a-z0-9][a-z0-9-]{0,39}$';
