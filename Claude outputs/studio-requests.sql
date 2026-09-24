-- JohnsonX Studio — mockup requests
-- Copyright (c) 2026 Anndy Johnson, operating as JohnsonXCorp. All rights reserved.
-- Anyone can SUBMIT a request from the website. Nobody but the owner can READ or change them.

create table if not exists public.studio_requests (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  name        text not null check (char_length(name) between 1 and 120),
  business    text not null check (char_length(business) between 1 and 160),
  phone       text check (char_length(phone) <= 40),
  email       text check (char_length(email) <= 200),
  site        text check (char_length(site) <= 300),
  need        text check (char_length(need) <= 80),
  message     text check (char_length(message) <= 4000),
  consent     boolean not null default false,
  source      text check (char_length(source) <= 80),
  status      text not null default 'new'
              check (status in ('new','contacted','mockup','proposal','won','launched','care','lost')),
  quote_cents integer check (quote_cents >= 0),
  notes       text check (char_length(notes) <= 8000),
  constraint studio_requests_reachable check (coalesce(phone,'') <> '' or coalesce(email,'') <> '')
);

-- Who counts as the owner (the dashboard login). Add rows here, never in the app.
create table if not exists public.studio_owners (email text primary key);
insert into public.studio_owners(email) values ('johnsonxcorp@outlook.com') on conflict do nothing;

create or replace function public.is_studio_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.studio_owners o
                 where lower(o.email) = lower(coalesce(auth.jwt() ->> 'email','')));
$$;

alter table public.studio_requests enable row level security;
alter table public.studio_owners  enable row level security;

-- the website: insert only, and only as a fresh, consented request
drop policy if exists "public can submit" on public.studio_requests;
create policy "public can submit" on public.studio_requests
  for insert to anon, authenticated
  with check (consent = true and status = 'new' and notes is null and quote_cents is null);

-- the owner: read, update, delete
drop policy if exists "owner reads"   on public.studio_requests;
drop policy if exists "owner updates" on public.studio_requests;
drop policy if exists "owner deletes" on public.studio_requests;
create policy "owner reads"   on public.studio_requests for select to authenticated using (public.is_studio_owner());
create policy "owner updates" on public.studio_requests for update to authenticated using (public.is_studio_owner()) with check (public.is_studio_owner());
create policy "owner deletes" on public.studio_requests for delete to authenticated using (public.is_studio_owner());

-- nobody reads the owner list through the API
revoke all on public.studio_owners from anon, authenticated;
grant insert on public.studio_requests to anon, authenticated;
grant select, update, delete on public.studio_requests to authenticated;

create or replace function public.studio_touch() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists studio_requests_touch on public.studio_requests;
create trigger studio_requests_touch before update on public.studio_requests
  for each row execute function public.studio_touch();
