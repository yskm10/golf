// ゴルフ場の予約確認画面のスクショから、コンペの情報を読み取る
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
  name: 'save_booking',
  description: '予約確認画面から読み取った内容を保存する。画面に書かれていない項目は null。',
  input_schema: {
    type: 'object',
    properties: {
      event_date: { type: ['string', 'null'], description: 'プレー日 YYYY-MM-DD' },
      course_name: { type: ['string', 'null'], description: 'ゴルフ場名' },
      includes: { type: ['string', 'null'], description: '料金に含まれるもの（昼食付、セルフ、乗用カートなど）を「・」区切りで。プラン名やアイコンから分かる範囲だけ' },
      fee_per_person: { type: ['integer', 'null'], description: 'お一人様の総額（円）' },
      small_group_fee: { type: ['integer', 'null'], description: '1組2名のときの、お一人様あたりの追加料金（円）' },
      cancel_policy: { type: ['string', 'null'], description: 'キャンセル料の規定を1〜3行で' },
      group_count: { type: ['integer', 'null'], description: '組数' },
      player_count: { type: ['integer', 'null'], description: '人数' },
      slots: {
        type: 'array',
        description: 'スタート枠。重複は1つにまとめる',
        items: {
          type: 'object',
          properties: {
            course: { type: 'string', enum: ['IN', 'OUT'] },
            time: { type: 'string', description: 'HH:MM（24時間）' },
          },
          required: ['course', 'time'],
        },
      },
      notes_admin: { type: ['string', 'null'], description: '注意事項・特記事項を、改行つきの箇条書きで' },
      line_candidates: {
        type: 'array',
        description: '参加者に伝えたほうがよい注意を、短い1行ずつ（最大8個）',
        items: { type: 'string' },
      },
    },
    required: ['slots', 'line_candidates'],
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
    const today = new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10);
    const prompt =
      `今日は${today}。これはゴルフ場の予約確認画面のスクショ（複数枚・順不同・重複あり）。画面に書かれている内容だけを save_booking に入れる。\n` +
      `- 推測しない。書かれていない項目は null。\n- 年が書かれていなければ、今日以降で最も近い日付にする。\n` +
      `- 重複したスタート枠は1つにまとめる。時刻は24時間表記の HH:MM。\n` +
      `- notes_admin: 注意事項・特記事項を読みやすい箇条書きにする。楽天ポイント、チェックイン、スタンプラリー、クーポンの案内は入れない。\n` +
      `- line_candidates: 同伴者に伝えるべき注意（支払い方法、持ち込み禁止、日没、休憩時間など）を短い1行ずつ。\n` +
      `必ず save_booking ツールを1回だけ呼んで結果を返す。文章での返答は不要。`;

    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': Deno.env.get('ANTHROPIC_API_KEY') ?? '',
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 4096,
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
    console.error('read-booking error', e);
    return json({ error: 'server_error' }, 500);
  }
});
