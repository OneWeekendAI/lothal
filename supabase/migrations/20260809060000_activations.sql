-- The email list. Firebase Auth used to BE the list — its user records were the only store, and
-- the design note said explicitly that there must not be a database, because an earlier draft had
-- a Firestore collection that was written on every issue and read by nothing.
--
-- Moving to Supabase changes that reasoning rather than overturning it: there is no auth provider
-- holding the addresses any more, so this table IS the list, not a second copy of one.
--
-- Still written by exactly one thing and read at runtime by nothing. The app never asks whether
-- an address is present; licences verify offline against a signature. So a write failure here
-- must never deny a licence, which is why the issuer logs and continues rather than erroring.
create table if not exists public.activations (
  email       text primary key,
  first_seen  timestamptz not null default now(),
  last_issued timestamptz not null default now()
);

-- Re-issuing is free and unlimited by design: issuing is stateless, there is no device table and
-- no unbind request. So a repeat activation updates the timestamp instead of erroring, and
-- first_seen keeps the date the address actually joined the list.
create or replace function public.touch_activation()
returns trigger language plpgsql as $$
begin
  new.first_seen := coalesce(old.first_seen, new.first_seen);
  return new;
end $$;

drop trigger if exists activations_touch on public.activations;
create trigger activations_touch before update on public.activations
  for each row execute function public.touch_activation();

-- RLS on with NO policies: the service-role key used by the Edge Function bypasses RLS, and
-- every other key (including the anon key that ships in the page) can therefore read nothing.
-- The addresses are the one piece of personal data this system holds; leaving RLS off would
-- publish the entire mailing list to anyone who found the project URL.
alter table public.activations enable row level security;
