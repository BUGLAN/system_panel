/**
 * 打字机：每字 34ms，[[高亮]] 或 [高亮] 用强调色，打字时末尾闪烁光标。
 * 减弱动态效果时直接整句显示。
 */
import { useEffect, useRef, useState } from 'react';
import { MOTION } from '../../design/tokens';
import { sfx } from '../../audio/sfx';
import { reducedMotion } from '../fx/fx';

interface Ch {
  c: string;
  hl: boolean;
}

/** 解析高亮：[[x]] 与 [x] 都算 */
export function parseHighlight(text: string): Ch[] {
  const out: Ch[] = [];
  let hl = false;
  const t = text.replaceAll('[[', '[').replaceAll(']]', ']');
  for (const c of t) {
    if (c === '[') {
      hl = true;
      continue;
    }
    if (c === ']') {
      hl = false;
      continue;
    }
    out.push({ c, hl });
  }
  return out;
}

export function Typewriter({
  text,
  as: Tag = 'p',
  className = '',
  speed = MOTION.typeMsPerChar,
  sound = true,
  id,
}: {
  text: string;
  as?: 'p' | 'span' | 'em' | 'div';
  className?: string;
  speed?: number;
  sound?: boolean;
  id?: string;
}) {
  const chars = parseHighlight(text);
  const instant = reducedMotion() || !text;
  const [state, setState] = useState({ text, shown: instant ? chars.length : 0 });
  if (state.text !== text) setState({ text, shown: instant ? chars.length : 0 });
  const shown = instant ? chars.length : state.text === text ? state.shown : 0;
  const timer = useRef<number | null>(null);

  useEffect(() => {
    const n = parseHighlight(text).length;
    if (timer.current) clearInterval(timer.current);
    if (reducedMotion() || !text) return;
    let i = 0;
    timer.current = window.setInterval(() => {
      i++;
      if (sound && i % 2 === 0) sfx.play('type');
      setState({ text, shown: i });
      if (i >= n && timer.current) {
        clearInterval(timer.current);
        timer.current = null;
      }
    }, speed);
    return () => {
      if (timer.current) clearInterval(timer.current);
    };
  }, [text, speed, sound]);

  const typing = shown < chars.length;
  return (
    <Tag className={`tw ${typing ? 'typing' : ''} ${className}`} id={id}>
      {chars.map((ch, i) => (
        <span key={i} className={`c${ch.hl ? ' hl' : ''}${i < shown ? ' v' : ''}`}>
          {ch.c}
        </span>
      ))}
    </Tag>
  );
}
