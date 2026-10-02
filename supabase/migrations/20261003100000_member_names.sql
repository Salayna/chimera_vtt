-- One name per campaign, ignoring case. Each anonymous browser (an incognito
-- window, another device) is a new player, so without this the same person
-- joining twice shows up twice. join_campaign's upsert only resolves
-- (campaign, user_id) conflicts, so taking someone else's name fails with a
-- unique violation the app reports. A player who lost their session gets
-- their name back once the GM removes their old member.

-- Existing duplicates keep their rows and get a number, in joining order:
-- "Aria", "Aria 2"… (37 characters + " NN" stays within the 40 allowed).
with ranked as (
  select campaign, user_id, name,
         row_number() over (partition by campaign, lower(name) order by joined_at) as n
  from public.members
)
update public.members m
set name = left(r.name, 37) || ' ' || r.n
from ranked r
where m.campaign = r.campaign and m.user_id = r.user_id and r.n > 1;

create unique index members_campaign_name_key
  on public.members (campaign, lower(name));
