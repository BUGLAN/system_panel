/**
 * 限长输入框：只数已上屏的字（拼音组字时不计、不截），组字期间对外报 composing，
 * CTA 据此置灰（compositionstart / compositionend 判断，docs/50 E2.6）；
 * 超长粘贴截尾并提示（G2.2）。
 */
import { forwardRef, useRef, type KeyboardEvent } from 'react';
import { toast } from '../../store/uiStore';

export function charCount(s: string): number {
  return [...s].length;
}

export function clipChars(s: string, max: number): string {
  const cs = [...s];
  return cs.length <= max ? s : cs.slice(0, max).join('');
}

export interface LimitedInputProps {
  value: string;
  onChange: (v: string) => void;
  onComposing?: (c: boolean) => void;
  onSubmit?: () => void;
  max: number;
  placeholder?: string;
  className?: string;
  multiline?: boolean;
  autoFocus?: boolean;
  enterKeyHint?: 'done' | 'send' | 'go' | 'next';
}

export const LimitedInput = forwardRef<HTMLInputElement & HTMLTextAreaElement, LimitedInputProps>(
  function LimitedInput(
    {
      value,
      onChange,
      onComposing,
      onSubmit,
      max,
      placeholder,
      className = '',
      multiline = false,
      autoFocus,
      enterKeyHint,
    },
    ref,
  ) {
    const composing = useRef(false);
    const commit = (raw: string) => {
      if (composing.current) {
        onChange(raw);
        return;
      }
      if (charCount(raw) > max) {
        toast(`最多 ${max} 个字，超出的部分截掉了。`, 'err');
        onChange(clipChars(raw, max));
        return;
      }
      onChange(raw);
    };
    const common = {
      value,
      placeholder,
      className: `lim-input ${className}`,
      autoFocus,
      enterKeyHint,
      onCompositionStart: () => {
        composing.current = true;
        onComposing?.(true);
      },
      onCompositionEnd: (e: { currentTarget: { value: string } }) => {
        composing.current = false;
        onComposing?.(false);
        commit(e.currentTarget.value);
      },
      onChange: (e: { currentTarget: { value: string } }) => commit(e.currentTarget.value),
      onKeyDown: (e: KeyboardEvent) => {
        if (e.key === 'Enter' && !e.shiftKey && !composing.current && !e.nativeEvent.isComposing) {
          e.preventDefault();
          onSubmit?.();
        }
      },
    };
    return multiline ? (
      <textarea ref={ref} rows={2} {...common} />
    ) : (
      <input ref={ref} type="text" {...common} />
    );
  },
);
