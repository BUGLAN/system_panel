/**
 * 证据照片压缩：长边不超过 1024px、JPEG。入库前就压，库里只存压缩后的版本，
 * 发给视觉模型、导出文件都用这一份。
 */
export const EVIDENCE_MAX_EDGE = 1024;
export const EVIDENCE_QUALITY = 0.82;

async function decode(
  file: Blob,
): Promise<{ draw: CanvasImageSource; w: number; h: number; close?: () => void }> {
  if (typeof createImageBitmap === 'function') {
    try {
      const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' });
      return { draw: bmp, w: bmp.width, h: bmp.height, close: () => bmp.close() };
    } catch {
      /* 有的格式（或老 Safari）不支持，退回 <img> */
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.decoding = 'async';
    img.src = url;
    await img.decode();
    return { draw: img, w: img.naturalWidth, h: img.naturalHeight };
  } finally {
    URL.revokeObjectURL(url);
  }
}

/** 压成 JPEG Blob；读不出来就抛 */
export async function compressImage(file: Blob): Promise<Blob> {
  const src = await decode(file);
  try {
    const k = Math.min(1, EVIDENCE_MAX_EDGE / Math.max(src.w, src.h));
    const w = Math.max(1, Math.round(src.w * k));
    const h = Math.max(1, Math.round(src.h * k));
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const cx = canvas.getContext('2d');
    if (!cx) throw new Error('canvas 不可用');
    cx.drawImage(src.draw, 0, 0, w, h);
    const blob = await new Promise<Blob | null>((r) =>
      canvas.toBlob(r, 'image/jpeg', EVIDENCE_QUALITY),
    );
    if (!blob) throw new Error('压缩失败');
    return blob;
  } finally {
    src.close?.();
  }
}

export function blobToDataUrl(b: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result));
    fr.onerror = () => reject(fr.error ?? new Error('读取失败'));
    fr.readAsDataURL(b);
  });
}

/** 开发环境用的演示截图（不送校验，按未校验照收，D3.1） */
export async function demoShot(title: string, proof: string): Promise<Blob> {
  const c = document.createElement('canvas');
  c.width = 480;
  c.height = 320;
  const x = c.getContext('2d');
  if (!x) throw new Error('canvas 不可用');
  const g = x.createLinearGradient(0, 0, 0, 320);
  g.addColorStop(0, '#121a33');
  g.addColorStop(1, '#05070f');
  x.fillStyle = g;
  x.fillRect(0, 0, 480, 320);
  x.fillStyle = '#8a93b8';
  x.font = '16px sans-serif';
  x.fillText(`证据快照 · ${proof}`, 24, 38);
  x.font = 'bold 26px sans-serif';
  x.fillStyle = '#fff';
  x.fillText(title.slice(0, 16), 24, 90);
  x.strokeStyle = '#d6ff3d';
  x.lineWidth = 3;
  x.beginPath();
  let v = 0.5;
  for (let i = 0; i <= 40; i++) {
    v = Math.min(0.95, Math.max(0.1, v + (Math.random() - 0.5) * 0.26));
    const px = 24 + i * 10.8;
    const py = 295 - v * 115;
    if (i) x.lineTo(px, py);
    else x.moveTo(px, py);
  }
  x.stroke();
  return new Promise((r, rej) =>
    c.toBlob((b) => (b ? r(b) : rej(new Error('生成失败'))), 'image/jpeg', 0.82),
  );
}
