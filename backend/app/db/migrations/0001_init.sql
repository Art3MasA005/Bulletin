-- Bulletin -- initial schema. PRD 9.
--
-- CLAUDE.md #5: "RLS is not optional. Row-level security on institution_id for
-- every table, an audience predicate on chunks, a user_id predicate on
-- attachments. Do not filter in Python and call it done."
--
-- The application-layer audience predicate (backend/app/retrieve/audience.py)
-- and these policies are defence in depth. Both, always.
--
-- BEFORE RUNNING: set the embedding dimension on `chunks.embedding` to match
-- the model chosen in Phase 1, and keep BULLETIN_EMBEDDING_DIM equal to it.
-- Changing it later needs a migration and a full re-index (CLAUDE.md).

create extension if not exists vector;
create extension if not exists pg_trgm;

-- ── enums ───────────────────────────────────────────────────────────────────

create type user_role as enum ('student', 'teacher', 'admin');
create type doc_audience as enum ('all', 'students', 'teachers', 'admin_only');
create type doc_status as enum ('uploaded', 'extracting', 'embedding', 'ready', 'failed');
create type extraction_method as enum ('native_text', 'legacy', 'scanned');

-- ── tables ──────────────────────────────────────────────────────────────────

create table institutions (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  invite_code  text not null unique,
  created_at   timestamptz not null default now()
);

create table profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  institution_id  uuid not null references institutions (id) on delete cascade,
  email           text not null,
  display_name    text,
  role            user_role not null default 'student',
  preferred_lang  text not null default 'en',
  created_at      timestamptz not null default now()
);
create index on profiles (institution_id);

create table documents (
  id                    uuid primary key default gen_random_uuid(),
  institution_id        uuid not null references institutions (id) on delete cascade,
  uploaded_by           uuid references profiles (id) on delete set null,
  title                 text not null,
  filename              text not null,
  mime_type             text not null,
  storage_path          text not null,
  -- No default: the publish flow requires a deliberate choice (DESIGN 6.7).
  audience              doc_audience not null,
  status                doc_status not null default 'uploaded',
  page_count            int,
  lang_detected         text,
  extraction_method     extraction_method,
  extraction_confidence real,
  failure_reason        text,
  created_at            timestamptz not null default now()
);
create index on documents (institution_id, status);

create table chunks (
  id                 bigserial primary key,
  doc_id             uuid not null references documents (id) on delete cascade,
  institution_id     uuid not null references institutions (id) on delete cascade,
  -- Denormalized from documents so the audience filter applies in a single
  -- query, before vector search (PRD 9, CLAUDE.md #4).
  audience           doc_audience not null,
  content            text not null,
  page_no            int not null,
  section            text,
  lang               text not null,
  extraction_method  extraction_method not null,
  embedding          vector(1024) not null,   -- <-- match BULLETIN_EMBEDDING_DIM
  created_at         timestamptz not null default now()
);

-- Dense arm (PRD 7.2 step 5). Cosine, HNSW.
create index chunks_embedding_idx on chunks
  using hnsw (embedding vector_cosine_ops);

-- The audience filter must be cheap, since it runs on every query.
create index chunks_scope_idx on chunks (institution_id, audience);

-- Lexical arm: tsvector for English, trigram for Bangla. Bangla has no
-- Postgres stemmer, which is exactly why pg_trgm carries that side.
create index chunks_fts_en_idx on chunks
  using gin (to_tsvector('english', content)) where lang = 'en';
create index chunks_trgm_idx on chunks
  using gin (content gin_trgm_ops);

create table conversations (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles (id) on delete cascade,
  institution_id  uuid not null references institutions (id) on delete cascade,
  title           text,
  created_at      timestamptz not null default now()
);
create index on conversations (user_id, created_at desc);

create table messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references conversations (id) on delete cascade,
  role             text not null check (role in ('user', 'assistant')),
  content          text not null,
  query_lang       text,
  citations        jsonb not null default '[]'::jsonb,
  created_at       timestamptz not null default now()
);
create index on messages (conversation_id, created_at);

-- PRD 8.1: architecturally opposite to `documents`.
-- NOTE THE ABSENCE OF AN EMBEDDING COLUMN. It is not an oversight and must not
-- be "fixed" -- a student's routine is personal and semester-scoped, and
-- indexing it puts one student's schedule where another student's query can
-- retrieve it (CLAUDE.md #2).
create table attachments (
  id                   uuid primary key default gen_random_uuid(),
  message_id           uuid references messages (id) on delete cascade,
  user_id              uuid not null references profiles (id) on delete cascade,
  institution_id       uuid not null references institutions (id) on delete cascade,
  storage_path         text not null,
  mime_type            text not null,
  extracted_json       jsonb,
  -- CLAUDE.md #3: a join answer cannot generate while this is false.
  extraction_confirmed boolean not null default false,
  created_at           timestamptz not null default now(),
  image_expires_at     timestamptz not null default (now() + interval '7 days')
);
create index on attachments (user_id, created_at desc);
create index on attachments (image_expires_at);

-- ── helpers ─────────────────────────────────────────────────────────────────

-- SECURITY DEFINER so policies can read profiles without recursing into the
-- profiles policy. STABLE so the planner calls it once per query.
create or replace function current_institution_id()
returns uuid
language sql stable security definer set search_path = public
as $$ select institution_id from profiles where id = auth.uid() $$;

create or replace function current_user_role()
returns user_role
language sql stable security definer set search_path = public
as $$ select role from profiles where id = auth.uid() $$;

-- Role -> allowed audiences. Mirrors backend/app/retrieve/audience.py; the two
-- must be changed together.
create or replace function allowed_audiences(r user_role)
returns doc_audience[]
language sql immutable
as $$
  select case r
    when 'admin'   then array['all','students','teachers','admin_only']::doc_audience[]
    when 'teacher' then array['all','students','teachers']::doc_audience[]
    else                array['all','students']::doc_audience[]
  end
$$;

-- ── row-level security ──────────────────────────────────────────────────────

alter table institutions  enable row level security;
alter table profiles      enable row level security;
alter table documents     enable row level security;
alter table chunks        enable row level security;
alter table conversations enable row level security;
alter table messages      enable row level security;
alter table attachments   enable row level security;

-- Institutions: members read their own.
create policy institutions_read on institutions for select
  using (id = current_institution_id());

-- Profiles: members see the roster of their own institution.
create policy profiles_read on profiles for select
  using (institution_id = current_institution_id());
create policy profiles_update_self on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- Documents: scoped by institution AND audience. Admins publish.
create policy documents_read on documents for select
  using (
    institution_id = current_institution_id()
    and audience = any (allowed_audiences(current_user_role()))
  );
create policy documents_admin_write on documents for all
  using (institution_id = current_institution_id() and current_user_role() = 'admin')
  with check (institution_id = current_institution_id() and current_user_role() = 'admin');

-- Chunks: the audience predicate CLAUDE.md #4 demands, at the database.
-- A student query physically cannot see a teacher-scoped row, regardless of
-- what the application sends.
create policy chunks_read on chunks for select
  using (
    institution_id = current_institution_id()
    and audience = any (allowed_audiences(current_user_role()))
  );

-- Conversations and messages: private to their owner.
create policy conversations_own on conversations for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy messages_own on messages for all
  using (
    exists (
      select 1 from conversations c
      where c.id = messages.conversation_id and c.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from conversations c
      where c.id = messages.conversation_id and c.user_id = auth.uid()
    )
  );

-- Attachments: the user_id predicate CLAUDE.md #5 requires. Never visible to
-- another user, in any conversation (PRD 8.4).
create policy attachments_own on attachments for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
