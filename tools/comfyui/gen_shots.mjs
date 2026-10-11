#!/usr/bin/env node
/**
 * SYSTEM 宿主 · ComfyUI 重设计提示词批量出图
 *
 * 提示词真源：tools/comfyui/prompts/shots.json（每镜 = style_lock + character_lock + variation）
 * 工作流真源：tools/comfyui/qwen21-game-bg.api.json（Qwen-Image 2.1 + 2x-AnimeSharpV4）
 *
 * 用法：
 *   node tools/comfyui/gen_shots.mjs --list                     # 列出全部镜头
 *   node tools/comfyui/gen_shots.mjs --print S10-settle         # 打印拼装好的完整提示词（手动粘进 GUI 用）
 *   node tools/comfyui/gen_shots.mjs --shot S10-settle          # 只出一张
 *   node tools/comfyui/gen_shots.mjs --group 整屏时刻           # 出一个分组
 *   node tools/comfyui/gen_shots.mjs --all                      # 全出（29 张，注意显存与时间）
 *   node tools/comfyui/gen_shots.mjs --shot S10-settle --seed 42 --out E:\tmp
 *   node tools/comfyui/gen_shots.mjs --shot A1-fx-burst --no-upscale
 *
 * 依赖：本机 ComfyUI 已在 http://127.0.0.1:8188 在线（绘世启动器 / _start_comfyui.bat）
 * 环境变量：COMFYUI_HOST 覆盖端点
 */
import { readFileSync, writeFileSync, copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const HOST = process.env.COMFYUI_HOST ?? "http://127.0.0.1:8188";
const SHOTS = join(HERE, "prompts", "shots.json");
const WF = join(HERE, "qwen21-game-bg.api.json");

/* ── 参数 ── */
const argv = process.argv.slice(2);
const has = (f) => argv.includes(`--${f}`);
const opt = (name, dflt) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : dflt;
};
const multi = (name) => {
  const out = [];
  argv.forEach((a, i) => { if (a === `--${name}` && argv[i + 1]) out.push(...argv[i + 1].split(",")); });
  return out;
};

const book = JSON.parse(readFileSync(SHOTS, "utf8"));
const base = book.base;
const all = book.shots;

const shotOf = (id) => all.find((s) => s.id === id);
const assemble = (s) => {
  const parts = [base.style_lock];
  if (s.use_character) parts.push(base.character_lock);
  parts.push(s.variation);
  const neg = s.negative_extra ? `${base.negative_base}, ${s.negative_extra}` : base.negative_base;
  return { positive: parts.join(" "), negative: neg };
};

/* ── --list ── */
if (has("list") || argv.length === 0) {
  console.log(`\n${book.version} · ${all.length} 镜 · 提示词真源 ${SHOTS}\n`);
  let g = "";
  for (const s of all) {
    if (s.group !== g) { g = s.group; console.log(`【${g}】`); }
    console.log(`  ${s.id.padEnd(18)} ${s.title.padEnd(22, "　")} ${s.width}x${s.height}  ${s.use_character ? "有她" : "无人物"}`);
  }
  console.log(`\n单出：node tools/comfyui/gen_shots.mjs --shot <id>`);
  console.log(`看词：node tools/comfyui/gen_shots.mjs --print <id>\n`);
  process.exit(0);
}

/* ── --print ── */
const printId = opt("print");
if (printId) {
  const s = shotOf(printId);
  if (!s) { console.error(`没有这个镜头：${printId}（先跑 --list）`); process.exit(1); }
  const { positive, negative } = assemble(s);
  console.log(`\n# ${s.id} · ${s.title}  (${s.width}x${s.height})`);
  console.log(`# ${s.desc}\n`);
  console.log(`--- POSITIVE (${positive.length} 字符) ---\n${positive}\n`);
  console.log(`--- NEGATIVE ---\n${negative}\n`);
  process.exit(0);
}

/* ── 选片 ── */
const ids = multi("shot");
const groups = multi("group");
let picked = [];
if (has("all")) picked = all.slice();
else if (ids.length) picked = ids.map((id) => shotOf(id)).filter(Boolean);
else if (groups.length) picked = all.filter((s) => groups.includes(s.group));
else {
  console.error("没说要出哪几张。用 --all / --shot <id> / --group <名字>，或 --list 看清单。");
  process.exit(1);
}
if (!picked.length) { console.error("没有匹配到任何镜头。"); process.exit(1); }

const seedArg = opt("seed");
const outDir = opt("out");
const waitMin = Number(opt("wait", 20));
const noUpscale = has("no-upscale");

/* ── 探活 ── */
try {
  const r = await fetch(`${HOST}/system_stats`, { signal: AbortSignal.timeout(4000) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
} catch (e) {
  console.error(`ComfyUI 不在线（${HOST}）：${e.message}`);
  console.error(`先用绘世启动器把 ComfyUI 起起来（默认 127.0.0.1:8188），再跑这个脚本。`);
  console.error(`只想看提示词的话：node tools/comfyui/gen_shots.mjs --print ${picked[0].id}`);
  process.exit(5);
}

/* ── 逐张生成 ── */
const stamp = Date.now().toString(36);
let done = 0, failed = 0;

for (const s of picked) {
  const { positive, negative } = assemble(s);
  const wf = JSON.parse(readFileSync(WF, "utf8"));
  wf["4"].inputs.prompt = positive;
  wf["4"].inputs.negative_prompt = negative;
  wf["5"].inputs.width = s.width;
  wf["5"].inputs.height = s.height;
  wf["6"].inputs.seed = seedArg !== undefined ? Number(seedArg) : Math.floor(Math.random() * 1e9);
  wf["11"].inputs.filename_prefix = `SystemShots/${s.id}`;
  if (wf["13"]) wf["13"].inputs.filename_prefix = `SystemShots/${s.id}_web`;
  if (noUpscale) { wf["11"].inputs.images = ["8", 0]; delete wf["12"]; delete wf["13"]; }

  console.log(`\n── ${s.id} · ${s.title} ── seed ${wf["6"].inputs.seed} · ${s.width}x${s.height}${noUpscale ? " · 不放大" : ""}`);

  const clientId = `sysshot-${stamp}-${s.id}`;
  const post = await fetch(`${HOST}/prompt`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ prompt: wf, client_id: clientId }),
  });
  const text = await post.text();
  let body = null;
  try { body = JSON.parse(text); } catch { /* 非 JSON 错误页 */ }
  if (!post.ok || !body || body.error) {
    console.error(`  提交失败 HTTP ${post.status}: ${text.slice(0, 800)}`);
    failed++; continue;
  }
  const pid = body.prompt_id;

  const deadline = Date.now() + waitMin * 60_000;
  let history = null;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 5000));
    const h = await (await fetch(`${HOST}/history/${pid}`)).json();
    if (h[pid]) { history = h[pid]; break; }
    const q = await (await fetch(`${HOST}/queue`)).json().catch(() => null);
    if (q) process.stdout.write(`  排队中 running=${q.queue_running.length} pending=${q.queue_pending.length}\r`);
  }
  if (!history) { console.error(`  超时（${waitMin} 分钟）`); failed++; continue; }
  if (history.status?.status_str !== "success") {
    console.error(`  执行失败: ${JSON.stringify(history.status ?? {}).slice(0, 600)}`);
    failed++; continue;
  }

  for (const [nodeId, nodeOut] of Object.entries(history.outputs)) {
    for (const im of nodeOut.images ?? []) {
      const url = `${HOST}/view?filename=${encodeURIComponent(im.filename)}&subfolder=${encodeURIComponent(im.subfolder)}&type=${encodeURIComponent(im.type)}`;
      const buf = Buffer.from(await (await fetch(url)).arrayBuffer());
      const local = join(HERE, ".out", im.subfolder, im.filename);
      mkdirSync(dirname(local), { recursive: true });
      writeFileSync(local, buf);
      console.log(`  [node ${nodeId}] ${local} (${(buf.length / 1024 / 1024).toFixed(2)} MB)`);
      if (outDir) { mkdirSync(outDir, { recursive: true }); copyFileSync(local, join(outDir, im.filename)); }
    }
  }
  done++;
}

console.log(`\n完成：成功 ${done} 张，失败 ${failed} 张。产物在 tools/comfyui/.out/SystemShots/，PNG 母版不入库。`);
if (failed) process.exit(3);
