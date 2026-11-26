-- The two Storage buckets the backend writes to (backend/app/db/storage.py).
--
-- Both PRIVATE. A public attachments bucket would put a student's routine --
-- name, student ID, schedule -- behind a guessable URL with no
-- authentication at all, which no amount of RLS elsewhere would undo
-- (PRD 8.4). Only the backend touches these, with the service key, on paths
-- it builds from the caller's own id; no storage policies grant clients
-- anything.
--
-- 0001 does not create them, so without this a fresh project comes up with no
-- buckets and every upload fails.

insert into storage.buckets (id, name, public)
values
  ('documents', 'documents', false),
  ('attachments', 'attachments', false)
on conflict (id) do update set public = false;
