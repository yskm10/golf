// コンペの成績表（順位表）の写真から、氏名・グロス・ネット・順位を読み取る
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-team-token, apikey, authorization',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const DAILY_LIMIT = 30; // 1チームあたり、24時間に読み取れる回数
const MAX_IMAGES = 8;
const MAX_IMAGE_CHARS = 2_000_000; // 1枚あたりのbase64の長さ上限
const MODEL = 'claude-sonnet-5-5';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const TOOL = {
  name: 'save_results',
  description: 'ゴルフコンペの成績表（順位表）から読み取った内容を保存する。画面に書かれていない項目は null。',
  input_schema: {
    type: 'object',
    properties: {
      rows: {
        type: 'array',
        description: '成績表の行。1人1行。複数枚・重複があれば同じ人は1行にまとめる',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string', description: '氏名（表の表記のまま。空白は除いてよい）' },
            gross: { type: ['integer', 'null'], description: 'Gross 列の数字（アウト＋イン）' },
            handicap: { type: ['number', 'null'], description: 'Hdcp 列の数字（小数あり。例 31.2）' },
            net: { type: ['number', 'null'], description: 'Net 列の数字（小数あり。例 73.8）' },
            rank: { type: ['integer', 'null'], description: '表に書かれている順位（ネットの順位）。「優勝」は1、「2位」は2、数字だけの欄はその数字' },
          },
          required: ['name'],
        },
      },
      note: { type: ['string', 'null'], description: '表の注意書き（方式、同スコアの扱いなど）があれば1行で' },
    },
    required: ['rows'],
  },
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    // 1) 幹事チームの確認
    const token = req.headers.get('x-team-token');
    if (!token) return json({ error: 'unauthorized' }, 401);
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: team } = await admin.from('teams').select('id').eq('admin_token', token).maybeSingle();
    if (!team) return json({ error: 'unauthorized' }, 401);

    // 2) 回数制限
    const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const { count } = await admin.from('read_log').select('id', { count: 'exact', head: true })
      .eq('team_id', team.id).gte('used_at', since);
    if ((count ?? 0) >= DAILY_LIMIT) return json({ error: 'rate_limited' }, 429);

    // 3) 画像の検証
    const body = await req.json().catch(() => null);
    const images: string[] = Array.isArray(body?.images) ? body.images : [];
    if (images.length < 1 || images.length > MAX_IMAGES) return json({ error: 'bad_images' }, 400);
    const blocks: unknown[] = [];
    for (const d of images) {
      const m = typeof d === 'string' && d.length <= MAX_IMAGE_CHARS
        ? d.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/) : null;
      if (!m) return json({ error: 'bad_images' }, 400);
      blocks.push({ type: 'image', source: { type: 'base64', media_type: m[1], data: m[2] } });
    }

    // 4) 記録してから読み取る（失敗しても回数に含める）
    await admin.from('read_log').insert({ team_id: team.id });
    const prompt =
      `これはゴルフコンペの成績表（順位表）の写真（複数枚・順不同・重複あり）。表に書かれている内容だけを save_results に入れる。\n` +
      `- 推測しない。書かれていない項目は null。数字は読み取れたとおりに。\n` +
      `- 1人1行。氏名は表のとおり（姓と名の間の空白、末尾の「様」は除く）。順位は表の左端の欄（優勝→1、2位→2）。アウト・インの列は使わない。\n` +
      `- 欠場・失格などで数字がない人も、氏名があれば行に入れる（数字は null）。\n` +
      `必ず save_results ツールを1回だけ呼んで結果を返す。文章での返答は不要。`;

    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': Deno.env.get('ANTHROPIC_API_KEY') ?? '',
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 8192,
        tools: [TOOL],
        tool_choice: { type: 'auto' },
        messages: [{ role: 'user', content: [...blocks, { type: 'text', text: prompt }] }],
      }),
    });
    if (!res.ok) {
      const t = await res.text();
      console.error('anthropic_error', res.status, t.slice(0, 300));
      return json({ error: 'ai_failed', status: res.status }, 502);
    }
    const out = await res.json();
    const tool = (out.content ?? []).find((c: { type: string }) => c.type === 'tool_use');
    if (!tool) {
      console.error('no_tool_use', JSON.stringify(out.content ?? []).slice(0, 300));
      return json({ error: 'ai_no_result' }, 502);
    }
    return json({ ok: true, data: tool.input });
  } catch (e) {
    console.error('read-results error', e);
    return json({ error: 'server_error' }, 500);
  }
});
