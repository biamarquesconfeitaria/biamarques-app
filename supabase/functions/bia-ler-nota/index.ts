// Bia Marques Confeitaria: lê a foto da nota fiscal de compra com o Claude e devolve os itens em JSON.
// Usada por "Ler nota fiscal" na aba Ingredientes (nuvemLeitor no index.html).
//
// Publicar: Supabase → Edge Functions → Deploy a new function → Via Editor,
// nome "bia-ler-nota", colar este arquivo inteiro.
// Segredo: usa o mesmo ANTHROPIC_API_KEY que já está em Edge Functions → Secrets (o da DaylinTech).
// A chave fica só no servidor. Nunca colocar no app.
//
// Só atende quem está logado e está na tabela "bia_membros" (função bia_e_membro do schema.sql),
// para ninguém de fora gastar os créditos da API.

import Anthropic from "npm:@anthropic-ai/sdk@0.133.0";
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

const MAX_IMAGENS = 5;
const MAX_PROMPT = 100_000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const responder = (status: number, corpo: unknown) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Formato exato que o app espera (o mesmo descrito no texto do pedido).
const ouNulo = (t: Record<string, unknown>) => ({ anyOf: [t, { type: "null" }] });
const FORMATO = {
  type: "object",
  additionalProperties: false,
  required: ["loja", "data", "total", "erro", "itens"],
  properties: {
    loja: ouNulo({ type: "string" }),
    data: ouNulo({ type: "string" }),
    total: ouNulo({ type: "number" }),
    erro: ouNulo({ type: "string" }),
    itens: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["descricao", "nome", "pacotes", "tamanho", "unidade", "precoTotal", "confeitaria", "ingredienteId"],
        properties: {
          descricao: { type: "string" },
          nome: { type: "string" },
          pacotes: { type: "number" },
          tamanho: { type: "number" },
          unidade: { type: "string", enum: ["g", "ml", "un"] },
          precoTotal: { type: "number" },
          confeitaria: { type: "boolean" },
          ingredienteId: ouNulo({ type: "string" }),
        },
      },
    },
  },
};

const client = new Anthropic(); // lê ANTHROPIC_API_KEY

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return responder(405, { erro: "metodo" });

  const chavePublica = req.headers.get("apikey") || Deno.env.get("SUPABASE_ANON_KEY") || "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, chavePublica, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: membro, error: erroMembro } = await sb.rpc("bia_e_membro");
  if (erroMembro || !membro) return responder(403, { erro: "sem_acesso" });
  if (!Deno.env.get("ANTHROPIC_API_KEY")) return responder(500, { erro: "sem_chave" });

  let corpo: { prompt?: unknown; imagens?: unknown };
  try {
    corpo = await req.json();
  } catch {
    return responder(400, { erro: "corpo" });
  }
  const prompt = String(corpo.prompt ?? "").slice(0, MAX_PROMPT);
  const imagens = (Array.isArray(corpo.imagens) ? corpo.imagens : [])
    .filter((x): x is string => typeof x === "string" && x.length > 0)
    .slice(0, MAX_IMAGENS);
  if (!prompt || !imagens.length) return responder(400, { erro: "corpo" });

  const content: Anthropic.Beta.BetaContentBlockParam[] = [
    ...imagens.map((data) => ({
      type: "image" as const,
      source: { type: "base64" as const, media_type: "image/jpeg" as const, data: data.replace(/^data:[^,]*,/, "") },
    })),
    { type: "text", text: prompt },
  ];

  try {
    const r = await client.beta.messages.create({
      model: "claude-opus-5-5",
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "medium", format: { type: "json_schema", schema: FORMATO } },
      messages: [{ role: "user", content }],
    });
    if (r.stop_reason === "refusal") return responder(422, { erro: "refused" });
    if (r.stop_reason === "max_tokens") return responder(422, { erro: "prompt_too_large" });
    const texto = r.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
    try {
      return responder(200, { dados: JSON.parse(texto) });
    } catch {
      return responder(502, { erro: "invalid_json" });
    }
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return responder(429, { erro: "rate_limited" });
    if (e instanceof Anthropic.AuthenticationError) return responder(500, { erro: "chave_invalida" });
    if (e instanceof Anthropic.PermissionDeniedError) return responder(500, { erro: "chave_invalida" });
    if (e instanceof Anthropic.BadRequestError) return responder(400, { erro: "image_rejected", detalhe: e.message });
    if (e instanceof Anthropic.APIError) return responder(502, { erro: "falha", detalhe: String(e.status) });
    return responder(500, { erro: "falha" });
  }
});
