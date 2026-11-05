-- Bia Marques Confeitaria: banco do app.
-- Rodar uma vez no Supabase: SQL Editor → New query → colar tudo → Run. Pode rodar de novo sem problema.
--
-- Fica no mesmo projeto da DaylinTech, mas com tabelas e pasta de fotos próprias:
-- os dados da Bia e da DaylinTech não se misturam, e cada app tem a sua lista de membros.
--
-- Todos os dados (ingredientes, partes do bolo, cardápio, receitas, pedidos e ajustes) ficam
-- na tabela "bia_docs", um registro por documento, no mesmo formato do backup do app.
-- Só quem está na tabela "bia_membros" consegue ler ou gravar qualquer coisa.

create table if not exists public.bia_docs (
  col            text        not null check (col ~ '^[a-z_]{1,40}$'),
  id             text        not null,
  data           jsonb       not null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid                 default auth.uid(),
  primary key (col, id)
);

-- E-mails com acesso ao app da Bia. Sem regra de acesso de propósito: pelo app ninguém lê
-- nem altera esta lista. Edite pelo painel do Supabase (Table Editor → bia_membros).
create table if not exists public.bia_membros (
  email text primary key check (email = lower(email))
);

create or replace function public.bia_e_membro()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bia_membros
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.bia_e_membro() from public, anon;
grant execute on function public.bia_e_membro() to authenticated;

create or replace function public.bia_docs_carimbo()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  new.atualizado_por := auth.uid();
  return new;
end;
$$;

drop trigger if exists bia_docs_carimbo on public.bia_docs;
create trigger bia_docs_carimbo before insert or update on public.bia_docs
  for each row execute function public.bia_docs_carimbo();

alter table public.bia_docs    enable row level security;
alter table public.bia_membros enable row level security;

revoke all on public.bia_docs    from anon;
revoke all on public.bia_membros from anon, authenticated;

drop policy if exists "bia membros leem"    on public.bia_docs;
drop policy if exists "bia membros incluem" on public.bia_docs;
drop policy if exists "bia membros alteram" on public.bia_docs;
drop policy if exists "bia membros apagam"  on public.bia_docs;
create policy "bia membros leem"    on public.bia_docs for select to authenticated using (public.bia_e_membro());
create policy "bia membros incluem" on public.bia_docs for insert to authenticated with check (public.bia_e_membro());
create policy "bia membros alteram" on public.bia_docs for update to authenticated using (public.bia_e_membro()) with check (public.bia_e_membro());
create policy "bia membros apagam"  on public.bia_docs for delete to authenticated using (public.bia_e_membro());

-- Atualização ao vivo entre os celulares.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bia_docs') then
    alter publication supabase_realtime add table public.bia_docs;
  end if;
end $$;

-- Fotos dos bolos do cardápio: pasta "bia-fotos". Qualquer um com o endereço da foto vê
-- (são fotos de bolos, para mostrar aos clientes); só membros enviam ou apagam.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bia-fotos', 'bia-fotos', true, 5242880, array['image/jpeg'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "bia membros enviam fotos" on storage.objects;
drop policy if exists "bia membros alteram fotos" on storage.objects;
drop policy if exists "bia membros apagam fotos" on storage.objects;
create policy "bia membros enviam fotos" on storage.objects for insert to authenticated
  with check (bucket_id = 'bia-fotos' and public.bia_e_membro());
create policy "bia membros alteram fotos" on storage.objects for update to authenticated
  using (bucket_id = 'bia-fotos' and public.bia_e_membro()) with check (bucket_id = 'bia-fotos' and public.bia_e_membro());
create policy "bia membros apagam fotos" on storage.objects for delete to authenticated
  using (bucket_id = 'bia-fotos' and public.bia_e_membro());

-- Troque pelos e-mails que vão entrar no app (em minúsculas): o seu e o da Bia.
insert into public.bia_membros (email) values ('seu-email@exemplo.com') on conflict do nothing;
insert into public.bia_membros (email) values ('email-da-bia@exemplo.com') on conflict do nothing;
