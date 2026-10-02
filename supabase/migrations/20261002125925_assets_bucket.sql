-- Images (maps, later tokens) stored by content: each object's name is the
-- SHA-256 hex of its bytes (ADR 006). Same name, same bytes, so objects are
-- never overwritten and clients may cache them forever.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'assets',
  'assets',
  false,
  20 * 1024 * 1024,
  array['image/png', 'image/jpeg', 'image/webp']
);

-- Any signed-in client may read, anonymous sign-ins included: players load
-- what the GM uploads. The table is trusted (POC: knowing a hash is enough).
create policy "assets: signed-in clients read"
on storage.objects for select
to authenticated
using (bucket_id = 'assets');

-- Uploads only under a content-hash name. The policy can't check that the
-- hash matches the bytes; clients compute it, and a wrong one only hurts
-- the uploader's own scene. No update or delete policy: objects are
-- immutable, so an existing name can never be replaced.
create policy "assets: signed-in clients upload by hash"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'assets'
  and name ~ '^[0-9a-f]{64}$'
);
