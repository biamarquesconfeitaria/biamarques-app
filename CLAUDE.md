# Bia Marques Confeitaria — app

App da Bia Marques Confeitaria (bolos confeitados, Araras). Toda a interface é em português do Brasil.
Nasceu como artefato do claude.ai e foi trazido para fora do Claude do mesmo jeito que o app da DaylinTech
(repositório daylerson/daylintech-app): GitHub Pages + Supabase.

## Estrutura

- `index.html`: o app inteiro em um arquivo (HTML, CSS e JavaScript puro, sem framework). A logo está embutida em base64 (`LOGO`).
- `config.js`: URL e chave pública (publishable) do Supabase. Vazio = modo local, só no navegador. Nunca colocar a chave `service_role`/secret.
- `supabase/schema.sql`: tabelas `bia_docs` e `bia_membros`, função `bia_e_membro()`, regras de acesso (RLS), realtime e a pasta de fotos `bia-fotos`. Rodar uma vez no SQL Editor.
- `vendor/`: Supabase JS, gerador de QR Code (Pix), jsPDF (orçamento em PDF) e `vendor/tesseract/` (tesseract.js 6.0.1, núcleo 6.0.0 e português `por.traineddata.gz` best_int), servidos pelo próprio app. O Tesseract só é baixado quando a Bia lê uma foto (não está no cache inicial do `sw.js`).
- `manifest.webmanifest`, `sw.js` e `icons/`: PWA (instalar na tela inicial). Ao mudar a lista de arquivos do cache, subir a versão em `CACHE` no `sw.js`.
- `dados/`: backup com os dados reais. **Só local** (`.gitignore`), porque o repositório é público e tem chave Pix e dados de clientes.

## Supabase

- Projeto próprio da Bia Marques (`ruuzxqetlsrmhpidxfgo`), separado do da DaylinTech (`pxlftfobcgrmdvbhxunr`, usado antes).
- Tudo fica em `bia_docs` (`col`, `id`, `data` jsonb). Coleções: `ingredientes` (com `cat: 'embalagem'` para caixas, bases e fitas), `componentes` (tamanhos, massas, recheios, coberturas, toppers; campo `tipo`), `cardapio` (fotos de bolos), `receitas`, `pedidos`, `compras` (notas lidas) e `config/geral` (ajustes).
- `nuvemDb()` imita a API do banco do artefato (`collection().doc().set/update/delete`, `add`, `onSnapshot`), então o resto do app não mudou.
- Login por e-mail e senha. Usuários criados em Authentication → Users → Add user (Auto confirm). Cadastro público desligado. Quem não está em `bia_membros` vê "Sem acesso".
- Fotos do cardápio: bucket público `bia-fotos` (leitura aberta, envio só de membros). `blobUrl(id)` monta o endereço público.
- Authentication → URL Configuration: incluir o endereço do app em Redirect URLs, para o "Esqueci a senha" funcionar.

## Regras de negócio

- Venda por tamanho com preço fixo (Bentô, Mini, PP, P, M, G, GG; Bolo de andar sob consulta). 1 massa e até 2 recheios. Recheio especial cobra o extra do tamanho (`adicEspecial`). Topo de bolo Simples/3D. Decoração com valor digitado.
- Lucro estimado no pedido: ingredientes pelo peso aproximado do tamanho (`pesoKg`) × custo por kg das partes, + gás/energia (%) + embalagem + horas × valor da hora.
- Receitas: preço sugerido por kg a partir dos ingredientes.
- Pix: BR Code estático com CRC16-CCITT (`pixCodigo`, `crc16`). Valor automático: sinal (orçamento sem sinal), falta pagar (com sinal) ou total.
- Envio do pedido: PDF (links clicáveis; Pix sem QR Code, com a chave, o botão "Copiar código Pix" que abre `pix.html#<código>` e o código visível com texto invisível de linha única por cima), imagem ou texto.
- `pix.html#<BR Code>`: página pública que mostra valor e recebedor, confere o CRC e tem o botão de copiar. O código fica depois do `#`, então não vai para servidor nenhum. A página do link (`pedido.html`) também não mostra mais QR Code. Botões: Salvar, Compartilhar (Web Share com arquivo) e Enviar texto pelo WhatsApp.
- Retirada na Rua Amapá 227, Araras; prazo 3 dias com topo e 2 sem; horários em Ajustes.

## Rodar

Sirva a pasta com qualquer servidor estático (ex.: `npx serve .`). Para trazer os dados: Ajustes → Restaurar backup.

## Pedido com link para o cliente (igual à proposta da DaylinTech)

- `supabase/links.sql` (rodar depois do schema.sql): tabela `bia_links` (token de 43 caracteres, `pedido_id`, `dados` jsonb, `visto_em`, `aceite`), funções `bia_ver_pedido` e `bia_aceitar_pedido` (security definer, liberadas para anon) e pasta pública `bia-links` com o PDF de cada link (`<token>.pdf`).
- No app: Enviar via WhatsApp → "Por link" (`gerarLink`, `dadosLink`). Grava uma cópia do pedido (não o HTML) e envia o PDF; o pedido guarda `linkToken`. Gerar de novo atualiza a mesma cópia e mantém o link.
- `pedido.html#token`: página pública, sem login. Mostra o pedido, Pix (QR + "Copiar código Pix"), cartão, PDF (baixar/enviar), informações importantes, Instagram, avaliações e contatos. "Aceitar orçamento" pede nome e WhatsApp.
- O aceite grava `aceite` no pedido (`bia_docs`) sem mudar a situação: o pedido só vira Confirmado quando a Bia recebe o sinal. No app aparece o selo "Aceito pelo cliente" e um aviso ao vivo; abrir o link grava `linkVistoEm` ("Cliente viu").
- `read()` do formulário preserva `linkToken`, `aceite` e `linkVistoEm` ao salvar.

## Leitura de nota de compra (sem custo, sem IA)

- A Bia compra num distribuidor que dá um comprovante de venda (não é NFC-e: sem QR Code nem chave). Formato: `Cod  Descrição  Qtd Un  VL UN  Total`, com a descrição quebrada em várias linhas.
- "Tirar foto da nota": `prepNota` recorta o papel, amplia e aplica limiar adaptativo; o Tesseract lê no próprio aparelho (`getOcr`, `lerFotos`). "Colar texto da nota": texto copiado pelo Google Lens / Texto ao Vivo do iPhone (`abrirTextoNota`).
- `lerTextoNota(txt)` separa loja, CNPJ, data, total e itens (código, descrição, quantidade, total). Aceita texto em linhas ou por colunas (como o Lens copia). Quando a leitura erra um número, `opcoesValor` dá alternativas e escolhe a combinação que fecha com o total. Itens duvidosos aparecem com "Confira o preço".
- `tamanhoDe` tira o tamanho da descrição (1LT → 1000 ml, 395G → 395 g). Caixa, cake board, base, fita etc. viram `cat: 'embalagem'` (unidade `un`).
- Na conferência (`openRevisao`), o app reconhece o que já foi comprado pelo código da loja (`cods: ['<cnpj>:<cod>']` no ingrediente) ou pela descrição (`descNota`).
- Embalagem por tamanho: o tamanho guarda `embItens: [{ingId, qtd}]`; `custoEmbTam` soma e `calcPedido` usa esse valor como embalagem do pedido (sem embalagem escolhida, usa `embalagemPadrao` dos Ajustes).

## Pagamentos e recibo

- No pedido salvo, "Registrar pagamento" (`formPagamento`): referente a Sinal / Restante / Valor total (valor sugerido pelo `sinalPct` e pelo saldo), forma Pix, cartão de crédito (parcelas), débito, dinheiro ou transferência, data e nome no recibo.
- Fica em `p.pagamentos: [{id, num, data, valor, tipo, forma, parcelas, nome}]`; `p.sinal` guarda a soma (`totalPago`), então saldo e "A receber" continuam iguais. O primeiro pagamento muda o pedido de Orçamento para Confirmado. Pedido antigo com sinal anotado à mão vira um pagamento `antigo: true` (sem recibo).
- Número do recibo: sequência única (`cfg.reciboSeq`, `nRecibo`).
- `verRecibo`: prévia, "Enviar recibo no WhatsApp" (Compartilhar do celular com o PDF e a mensagem; sem isso, salva o PDF e abre a conversa), "Salvar PDF", mensagem editável (`textoRecibo`) e "Desfazer este pagamento". O recibo (`imagemRecibo`/`pdfRecibo`) é desenhado em canvas como o orçamento, com valor por extenso (`extenso`), referente a sinal/restante/total, forma, resumo (valor do pedido, recebido até aquele recibo, falta pagar ou quitado), cidade e data, assinatura e contatos clicáveis.

## Assinatura e avaliações

- Ajustes → "Sua assinatura": quadro para assinar com o dedo (`ligarAssinatura`, ligado em `render()` quando a aba é Ajustes). "Salvar assinatura" recorta o traço e grava PNG em `cfg.assinatura`. Aparece no recibo (acima da linha) e no orçamento (antes do "Obrigada").
- `cfg.linkAvaliar`: link do Google para deixar avaliação ("Pedir avaliações" do Perfil da Empresa). `linkAvaliar()` usa ele ou, em branco, `cfg.avaliacoes`. O recibo tem o cartão clicável "Gostou? Avalie a nossa página" e a mensagem do recibo termina com o link. O orçamento continua com "Veja nossas avaliações" (`cfg.avaliacoes`).
- Pedido entregue: ao salvar mudando a situação para Entregue, abre `pedirAvaliacao` (mensagem editável `textoAvaliacao` + WhatsApp do cliente; grava `avaliacaoPedidaEm`). No pedido entregue há o botão "Pedir avaliação".

## Fotos do bolo pronto e post do Instagram

- Pedido salvo: "Fotos do bolo pronto" (`galeriaPedido`), até 5 fotos em `p.fotos` (ids no bucket `bia-fotos`; sem nuvem, só na memória em `fotosLocais`). Gravam na hora, sem esperar "Salvar pedido". Excluir o pedido apaga as fotos que não estão no cardápio.
- Ao salvar mudando para Entregue abre `pedidoFinalizado`: fotos, "Criar post para o Instagram", "Colocar nas fotos do cardápio" (`paraCardapio`, cria/atualiza um bolo em `cardapio` com `pedidoId`) e "Pedir avaliação".
- Estilo padrão "Logo no canto" (selo pequeno), porque o feed dela (@biamarquesconfeitaria) é de fotos limpas do bolo na mesa de madeira, sem texto por cima. Legenda no tom da bio ("Bolos artesanais e personalizados", "📍 Retirada: Rua Amapá, 227 Araras").
- `criarPost`: escolhe as fotos (ordem do carrossel), formato (`FMT_POST`: Feed 4:5, Quadrado, Stories) e estilo (`ESTILO_POST`: faixa com texto, logo no canto, moldura rosa, só a foto), texto na foto e legenda (`legendaPost`: tema, tamanho e sabores, WhatsApp, cidade, hashtags; sem o nome do cliente). `desenharPost` desenha em canvas com a logo.
- Instagram não aceita publicação por app de fora sem a API oficial: "Publicar no Instagram" copia a legenda e abre o Compartilhar do celular com as imagens (Web Share); sem suporte, salva as fotos e abre o instagram.com. Grava `postEm`.
- Legenda (`legendaPost(p, dados, variação)`) no jeito dos posts dela: emojis do tema (`EMOJI_TEMA`, `emojisTema`), frase carinhosa, "para comemorar os 4 aninhos do Théo" e hashtags em CamelCase (#BoloPersonalizado #Tema #FestaInfantil/#BoloInfantil #ConfeitariaComAmor #Nome4Anos). Sem sabor, WhatsApp nem endereço. `dadosPost` tenta tirar tema, nome e idade dos "Detalhes e tema" do pedido; no post há campos Tema, Aniversariante, Idade e do/da que refazem a legenda (se ela não foi editada à mão) e o botão "Outra legenda" (4 modelos).

## Galeria

- Aba "Galeria" (`vGaleria`, sexta aba da barra). Coleção `galeria` (`S.gal`): `{foto, titulo, categoria, criado}` para fotos adicionadas ali (`galUpload`, bucket `bia-fotos`) e `{foto, oculta:true}` para tirar da galeria uma foto de pedido ou do cardápio sem apagar o arquivo.
- `itensGaleria()` junta, sem repetir, as fotos da galeria, do cardápio (`S.card[].fotos`) e dos pedidos (`S.ped[].fotos`), mais novas primeiro. Filtro por categoria (`gal.cat`).
- Tocar na foto (`verFotoGaleria`): nome/tema e categoria (gravados num registro da galeria), "Enviar para alguém" (`formEnviarFotos`: logo no canto opcional, mensagem, Compartilhar com as imagens), "Publicar no Instagram" (`criarPost(null, {fotos, p})`), "Salvar no celular", "Colocar no cardápio" / "Ver no cardápio" e "Excluir foto" / "Tirar da galeria".
- "Selecionar" (`gal.sel`, até 10): enviar ou publicar várias de uma vez (carrossel).
- `desenharPost` tem o formato `'original'` (proporção da foto, até 1800 px) usado no envio; a logo do estilo "logo" escala com a foto.
- Arquivos só são apagados do bucket quando a foto não está mais em pedido, cardápio nem galeria (`fotoNaGaleriaOuPedido`).

## Cardápio em PDF

- Cardápio → "Enviar cardápio em PDF" (`enviarCardapioPDF` → `pdfCardapio`). `desenharCardapio(pdf)` é o mesmo desenho da imagem ("Gerar imagem"); no PDF entra o bloco "Faça seu pedido" com links clicáveis (jsPDF `doc.link`): botão verde "Fazer meu pedido no WhatsApp" (wa.me com mensagem pronta), Instagram, avaliações (`cfg.avaliacoes`) e rota até a retirada (Google Maps). Enviar abre o Compartilhar com o PDF e a mensagem; sem isso, salva o PDF e copia a mensagem.
