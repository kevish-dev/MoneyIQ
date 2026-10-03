-- MoneyIQ cloud schema (Supabase / Postgres). Run once in the Supabase
-- dashboard: SQL Editor -> New query -> paste -> Run. Safe to re-run.
--
-- One generic table holds every synced record as JSON, keyed by the signed-in
-- user. The app keeps a full SwiftData copy on the device and syncs record by
-- record; Row Level Security below means a user can only ever read or write
-- their own rows, even though the app ships the public anon key.

create table if not exists public.records (
  user_id    uuid        not null default auth.uid()
                         references auth.users (id) on delete cascade,
  entity     text        not null,           -- e.g. 'expenseTransactions'
  id         uuid        not null,           -- the record's own UUID
  payload    jsonb       not null,           -- the record, as the Backup DTO
  deleted    boolean     not null default false,  -- tombstone so deletes sync
  updated_at timestamptz not null default now(),
  primary key (user_id, entity, id)
);

-- Pulling "everything changed since my last sync" is the hot query.
create index if not exists records_user_updated_idx
  on public.records (user_id, updated_at);

-- The server stamps updated_at, never the phone: device clocks drift, and the
-- pull cursor must be monotonic.
create or replace function public.records_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists records_touch_trg on public.records;
create trigger records_touch_trg
  before insert or update on public.records
  for each row execute function public.records_touch();

alter table public.records enable row level security;

drop policy if exists "records_select_own" on public.records;
create policy "records_select_own" on public.records
  for select using (auth.uid() = user_id);

drop policy if exists "records_insert_own" on public.records;
create policy "records_insert_own" on public.records
  for insert with check (auth.uid() = user_id);

drop policy if exists "records_update_own" on public.records;
create policy "records_update_own" on public.records
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "records_delete_own" on public.records;
create policy "records_delete_own" on public.records
  for delete using (auth.uid() = user_id);
