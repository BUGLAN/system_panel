/**
 * 基础按钮：按下的轻震由它自己负责。
 * 外观沿用参考稿 .btn / .btn.pri / .btn.ghost / .btn.sm。
 */
import type { ButtonHTMLAttributes, ReactNode, Ref } from 'react';
import { haptic } from '../haptics';

export function pressFeedback(): void {
  haptic.tap();
}

export function Btn({
  kind = 'pri',
  sm = false,
  grow = false,
  className = '',
  children,
  onPointerDown,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  kind?: 'pri' | 'ghost';
  sm?: boolean;
  grow?: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      className={`btn ${kind} ${sm ? 'sm' : ''} ${grow ? 'grow' : ''} ${className}`}
      onPointerDown={(e) => {
        if (!rest.disabled) pressFeedback();
        onPointerDown?.(e);
      }}
      {...rest}
    >
      {kind === 'pri' && <span className="sh2" />}
      {children}
    </button>
  );
}

/** 不带外框的小按钮（.link / .xbtn / .iconbtn / .srow 等），同样自带按下轻震（quiet = 不震） */
export function Tap({
  className = '',
  children,
  onPointerDown,
  quiet = false,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  children?: ReactNode;
  quiet?: boolean;
  ref?: Ref<HTMLButtonElement>;
}) {
  return (
    <button
      type="button"
      className={className}
      onPointerDown={(e) => {
        if (!rest.disabled && !quiet) pressFeedback();
        onPointerDown?.(e);
      }}
      {...rest}
    >
      {children}
    </button>
  );
}
