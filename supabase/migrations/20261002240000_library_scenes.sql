-- Scenes in the library: templates a campaign copies, never changed by
-- play. A scene row holds the scene's JSON in `data`; its thumbnail is its
-- map's, and it has no asset of its own.
alter table public.library drop constraint library_kind_check;
alter table public.library
  add constraint library_kind_check check (kind in ('map', 'token', 'scene'));

alter table public.library alter column asset drop not null;
alter table public.library add column data jsonb;

-- Images have an asset and no scene; scenes have a scene and no asset.
alter table public.library add constraint library_shape_check check (
  (kind = 'scene' and data is not null and asset is null)
  or (kind <> 'scene' and data is null and asset is not null)
);

-- Images always have a thumbnail; a scene has one only if it has a map.
alter table public.library alter column thumb drop not null;
alter table public.library add constraint library_image_thumb_check check (
  kind = 'scene' or thumb is not null
);
