-- Characters played in campaigns (docs/SYSTEMS.md): a player links their
-- character to a campaign they're a member of, played with the character's
-- system. The campaign's GM then reads it; only its owner ever writes it.
create table public.campaign_characters (
  campaign uuid not null references public.campaigns (id) on delete cascade,
  character uuid not null references public.characters (id) on delete cascade,
  linked_at timestamptz not null default now(),
  primary key (campaign, character)
);

create index campaign_characters_character_idx on public.campaign_characters (character);

alter table public.campaign_characters enable row level security;

-- The character's owner, and the campaign's GM.
create policy "campaign_characters: owners and GMs read"
on public.campaign_characters for select
to authenticated
using (
  exists (
    select 1 from public.characters ch
    where ch.id = campaign_characters.character and ch.owner = (select auth.uid())
  )
  or exists (
    select 1 from public.campaigns c
    where c.id = campaign_characters.campaign and c.owner = (select auth.uid())
  )
);

create policy "campaign_characters: owners unlink"
on public.campaign_characters for delete
to authenticated
using (
  exists (
    select 1 from public.characters ch
    where ch.id = campaign_characters.character and ch.owner = (select auth.uid())
  )
);

-- Linking: the only way in. The caller must own the character and be a
-- member of the campaign, whose system must be the character's. Security
-- definer since members can't read campaigns.
create function public.link_character(campaign uuid, character_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.characters ch
    join public.campaigns c on c.id = link_character.campaign
    where ch.id = link_character.character_id
      and ch.owner = (select auth.uid())
      and ch.system = c.system
  ) or not public.is_member(link_character.campaign) then
    raise exception 'not your character, or not this campaign''s system';
  end if;
  insert into public.campaign_characters (campaign, character)
  values (link_character.campaign, link_character.character_id)
  on conflict do nothing;
end;
$$;

revoke execute on function public.link_character(uuid, uuid) from public, anon;
grant execute on function public.link_character(uuid, uuid) to authenticated;

-- Whether the caller is the GM of a campaign [character_id] is linked to.
-- Security definer so the characters policy can ask without recursing
-- through campaign_characters' own.
create function public.is_gm_of_character(character_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.campaign_characters cc
    join public.campaigns c on c.id = cc.campaign
    where cc.character = is_gm_of_character.character_id
      and c.owner = (select auth.uid())
  );
$$;

revoke execute on function public.is_gm_of_character(uuid) from public, anon;
grant execute on function public.is_gm_of_character(uuid) to authenticated;

-- The GMs of campaigns a character is linked to read it.
create policy "characters: GMs of linked campaigns read"
on public.characters for select
to authenticated
using (public.is_gm_of_character(characters.id));
