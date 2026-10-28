-- Minimal Supabase Auth contract for isolated PostgreSQL CI. No live project.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema extensions;
create table auth.users(id uuid primary key, email text unique, raw_user_meta_data jsonb default '{}'::jsonb);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users);
create table auth.refresh_tokens(id bigint primary key,session_id uuid references auth.sessions);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,service_role;
grant select on auth.users to service_role;
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key,bucket_id text references storage.buckets,name text,created_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select,insert,delete on storage.objects to authenticated;
