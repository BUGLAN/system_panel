#!/usr/bin/env node
/**
 * SYSTEM 宿主 · 游戏背景一键重生成
 * 流程：Qwen-Image 2.1 文生图（768x1664，9:19.5）→ 2x-AnimeSharpV4 放大 2 倍 → 落 1536x3328 母版 + 1080x2340 网页版
 * 用法：
 *   node gen_game_bg.mjs                      # 按 qwen21-game-bg.api.json 原样生成
 *   node gen_game_bg.mjs --seed 42            # 换种子
 *   node gen_game_bg.mjs --out D:\tmp         # 额外把产物拷到指定目录
 *   node gen_game_bg.mjs --wait 20            # 轮询超时（分钟），默认 20
 * 依赖：本机 ComfyUI 已在 http://127.0.0.1:8188 在线（绘世启动器 / _start_comfyui.bat）
 */
import { readFileSync, writeFileSync, copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const HOST = process.env.COMFYUI_HOST ?? "http://127.0.0.1:8188";
const WF = join(HERE, "qwen21-game-bg.api.json");

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : dflt;
};
const seed = opt("seed");
const outDir = opt("out");
const waitMin = Number(opt("wait", 20));

const prompt = JSON.parse(readFileSync(WF, "utf8"));
if (seed !== undefined) prompt["6"].inputs.seed = Number(seed);

const clientId = `system-bg-${Date.now().toString(36)}`;
const post = await fetch(`${HOST}/prompt`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ prompt, client_id: clientId }),
});
const postBodyText = await post.text();
let postBody = null;
try { postBody = JSON.parse(postBodyText); } catch { /* 非 JSON 错误页 */ }
if (!post.ok || !postBody || postBody.error) {
  console.error("提交失败 HTTP", post.status, ":", postBodyText.slice(0, 2000));
  process.exit(1);
}
const promptId = postBody.prompt_id;
console.log("已入队 prompt_id =", promptId, seed !== undefined ? `(seed ${seed})` : "");

const deadline = Date.now() + waitMin * 60_000;
let history = null;
while (Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 5000));
  const res = await fetch(`${HOST}/history/${promptId}`);
  const body = await res.json();
  if (body[promptId]) { history = body[promptId]; break; }
  const q = await (await fetch(`${HOST}/queue`)).json();
  console.log(`排队中 queue_running=${q.queue_running.length} queue_pending=${q.queue_pending.length} ...`);
}
if (!history) { console.error(`超时（${waitMin} 分钟）未完成`); process.exit(2); }

const status = history.status?.status_str;
console.log("执行结束:", status);
if (status !== "success") {
  console.error("执行失败:", JSON.stringify(history.status ?? {}, null, 2));
  process.exit(3);
}

const saved = [];
for (const [nodeId, nodeOut] of Object.entries(history.outputs)) {
  for (const im of nodeOut.images ?? []) {
    const url = `${HOST}/view?filename=${encodeURIComponent(im.filename)}&subfolder=${encodeURIComponent(im.subfolder)}&type=${encodeURIComponent(im.type)}`;
    const buf = Buffer.from(await (await fetch(url)).arrayBuffer());
    const local = join(HERE, ".out", im.subfolder, im.filename);
    mkdirSync(dirname(local), { recursive: true });
    writeFileSync(local, buf);
    saved.push({ nodeId, file: local, bytes: buf.length });
    console.log(`[node ${nodeId}] ${local} (${(buf.length / 1024 / 1024).toFixed(2)} MB)`);
    if (outDir) {
      mkdirSync(outDir, { recursive: true });
      const dst = join(outDir, im.filename);
      copyFileSync(local, dst);
      console.log(`  已拷贝 → ${dst}`);
    }
  }
}
if (!saved.length) { console.error("没有图片产物"); process.exit(4); }
console.log("\n完成。共", saved.length, "张。");
