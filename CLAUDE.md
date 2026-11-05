# Bia Marques Confeitaria — app

App da Bia Marques Confeitaria (bolos confeitados, Araras). Toda a interface é em português do Brasil.
Nasceu como artefato do claude.ai e foi trazido para fora do Claude do mesmo jeito que o app da DaylinTech
(repositório daylerson/daylintech-app): GitHub Pages + Supabase.

## Estrutura

- `index.html`: o app inteiro em um arquivo (HTML, CSS e JavaScript puro, sem framework). A logo está embutida em base64 (`LOGO`).
- `config.js`: URL e chave pública (publishable) do Supabase. Vazio = modo local, só no navegador. Nunca colocar a chave `service_role`/secret.
- `supabase/schema.sql`: tabelas `bia_docs` e `bia_membros`, função `bia_e_membro()`, regras de acesso (RLS), realtime e a pasta de fotos `bia-fotos`. Rodar uma vez no SQL Editor.
- `supabase/functions/bia-ler-nota/index.ts`: Edge Function que lê a foto da nota fiscal com a API da Anthropic (saída em JSON Schema). Só atende membros. Usa o segredo `ANTHROPIC_API_KEY` do projeto. Publicada pelo painel do Supabase (Edge Functions → editor).
- `vendor/`: Supabase JS, gerador de QR Code (Pix) e jsPDF (orçamento em PDF), servidos pelo próprio app.
- `manifest.webmanifest`, `sw.js` e `icons/`: PWA (instalar na tela inicial). Ao mudar a lista de arquivos do cache, subir a versão em `CACHE` no `sw.js`.
- `dados/`: backup com os dados reais. **Só local** (`.gitignore`), porque o repositório é público e tem chave Pix e dados de clientes.

## Supabase

- Mesmo projeto da DaylinTech (`pxlftfobcgrmdvbhxunr`), com tabelas e pasta próprias: os dados não se misturam e cada app tem a sua lista de membros.
- Tudo fica em `bia_docs` (`col`, `id`, `data` jsonb). Coleções: `ingredientes`, `componentes` (tamanhos, massas, recheios, coberturas, toppers; campo `tipo`), `cardapio` (fotos de bolos), `receitas`, `pedidos`, `compras` (notas lidas) e `config/geral` (ajustes).
- `nuvemDb()` imita a API do banco do artefato (`collection().doc().set/update/delete`, `add`, `onSnapshot`), então o resto do app não mudou.
- Login por e-mail e senha. Usuários criados em Authentication → Users → Add user (Auto confirm). Cadastro público desligado. Quem não está em `bia_membros` vê "Sem acesso".
- Fotos do cardápio: bucket público `bia-fotos` (leitura aberta, envio só de membros). `blobUrl(id)` monta o endereço público.
- Authentication → URL Configuration: incluir o endereço do app em Redirect URLs, para o "Esqueci a senha" funcionar.

## Regras de negócio

- Venda por tamanho com preço fixo (Bentô, Mini, PP, P, M, G, GG; Bolo de andar sob consulta). 1 massa e até 2 recheios. Recheio especial cobra o extra do tamanho (`adicEspecial`). Topo de bolo Simples/3D. Decoração com valor digitado.
- Lucro estimado no pedido: ingredientes pelo peso aproximado do tamanho (`pesoKg`) × custo por kg das partes, + gás/energia (%) + embalagem + horas × valor da hora.
- Receitas: preço sugerido por kg a partir dos ingredientes.
- Pix: BR Code estático com CRC16-CCITT (`pixCodigo`, `crc16`). Valor automático: sinal (orçamento sem sinal), falta pagar (com sinal) ou total.
- Envio do pedido: PDF (links clicáveis, Pix copia e cola em texto invisível de linha única sobre o código visível), imagem ou texto. Botões: Salvar, Compartilhar (Web Share com arquivo) e Enviar texto pelo WhatsApp.
- Retirada na Rua Amapá 227, Araras; prazo 3 dias com topo e 2 sem; horários em Ajustes.

## Rodar

Sirva a pasta com qualquer servidor estático (ex.: `npx serve .`). Para trazer os dados: Ajustes → Restaurar backup.
