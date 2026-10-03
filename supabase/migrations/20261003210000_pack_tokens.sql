-- Packs may now carry their ready-made tokens' cards (a module's threat
-- database), which scenes don't copy: room for them in the GM's install.
alter table public.packs drop constraint packs_data_check;
alter table public.packs
  add constraint packs_data_check check (octet_length(data::text) <= 4194304);
