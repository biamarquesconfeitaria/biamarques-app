// Banco na nuvem (Supabase). Usa o mesmo projeto do app da DaylinTech, com tabelas próprias
// (bia_docs, bia_membros) e pasta de fotos própria (bia-fotos), sem misturar os dados.
// A chave "publishable" pode ficar aqui: ela é pública, e quem protege os dados são as regras
// do banco (supabase/schema.sql). NUNCA coloque aqui a chave "service_role" / "secret".
// Com os dois vazios, o app funciona só neste navegador (modo local).
window.BIA_CONFIG = {
  supabaseUrl: 'https://pxlftfobcgrmdvbhxunr.supabase.co',
  supabaseKey: 'sb_publishable_c2ssAJpgIstK-1pEZfqMeQ_XOp6FsgP'
};
