-- Bia Marques Confeitaria: pedido com link para o cliente (pedido.html#código).
-- Rodar uma vez no Supabase, DEPOIS do schema.sql: SQL Editor → New query → colar tudo → Run.
-- Pode rodar de novo sem problema.
--
-- Cada link tem um código aleatório de 43 caracteres. O cliente não faz login: ele só
-- consegue ver e aceitar o pedido daquele código, pelas funções bia_ver_pedido e
-- bia_aceitar_pedido. A tabela em si continua fechada para quem não é membro.

create table if not exists public.bia_links (
  token      text        primary key check (length(token) >= 32),
  pedido_id  text        not null,
  dados      jsonb       not null,
  criado_em  timestamptz not null default now(),
  criado_por uuid                 default auth.uid(),
  visto_em   timestamptz,
  aceite     jsonb,
  aceito_em  timestamptz
);
create index if not exists bia_links_pedido on public.bia_links (pedido_id);

alter table public.bia_links enable row level security;
revoke all on public.bia_links from anon;

drop policy if exists "bia membros gerenciam links" on public.bia_links;
create policy "bia membros gerenciam links" on public.bia_links for all to authenticated
  using (public.bia_e_membro()) with check (public.bia_e_membro());

-- O cliente abre o link. Na primeira vez, marca no pedido que o cliente viu.
create or replace function public.bia_ver_pedido(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.bia_links;
begin
  select * into r from public.bia_links where token = p_token;
  if not found then
    return null;
  end if;
  if r.visto_em is null and not public.bia_e_membro() then
    update public.bia_links set visto_em = now() where token = p_token;
    update public.bia_docs
       set data = data || jsonb_build_object('linkVistoEm', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
     where col = 'pedidos' and id = r.pedido_id;
  end if;
  return jsonb_build_object('dados', r.dados, 'aceite', r.aceite);
end;
$$;

-- O cliente aceita o orçamento. O pedido continua "Orçamento" até a Bia receber o sinal:
-- no app ele aparece como "Aceito pelo cliente".
create or replace function public.bia_aceitar_pedido(p_token text, p_nome text, p_whats text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.bia_links;
  ac jsonb;
begin
  select * into r from public.bia_links where token = p_token for update;
  if not found then
    raise exception 'pedido não encontrado' using errcode = 'P0002';
  end if;
  if r.aceite is not null then
    return r.aceite;  -- já aceito: não sobrescreve
  end if;

  p_nome  := left(btrim(coalesce(p_nome, '')), 200);
  p_whats := left(btrim(coalesce(p_whats, '')), 30);
  if p_nome = '' then
    raise exception 'informe o nome' using errcode = '22023';
  end if;

  ac := jsonb_build_object('nome', p_nome, 'whats', p_whats, 'via', 'link',
                           'data', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));

  update public.bia_links set aceite = ac, aceito_em = now() where token = p_token;
  update public.bia_docs set data = data || jsonb_build_object('aceite', ac)
   where col = 'pedidos' and id = r.pedido_id;

  return ac;
end;
$$;

revoke all on function public.bia_ver_pedido(text) from public;
revoke all on function public.bia_aceitar_pedido(text, text, text) from public;
grant execute on function public.bia_ver_pedido(text) to anon, authenticated;
grant execute on function public.bia_aceitar_pedido(text, text, text) to anon, authenticated;

-- PDF do pedido para o cliente baixar pela página. Pasta pública, mas o nome de cada arquivo
-- é o código secreto do link: só quem tem o link chega no PDF.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bia-links', 'bia-links', true, 10485760, array['application/pdf'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "bia membros enviam pdf" on storage.objects;
drop policy if exists "bia membros alteram pdf" on storage.objects;
drop policy if exists "bia membros apagam pdf" on storage.objects;
create policy "bia membros enviam pdf" on storage.objects for insert to authenticated
  with check (bucket_id = 'bia-links' and public.bia_e_membro());
create policy "bia membros alteram pdf" on storage.objects for update to authenticated
  using (bucket_id = 'bia-links' and public.bia_e_membro()) with check (bucket_id = 'bia-links' and public.bia_e_membro());
create policy "bia membros apagam pdf" on storage.objects for delete to authenticated
  using (bucket_id = 'bia-links' and public.bia_e_membro());
