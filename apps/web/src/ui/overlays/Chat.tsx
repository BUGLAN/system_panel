/**
 * 聊天面板：随时可开。快捷入口（查状态 / 换任务 / 调整计划）、工具回执渲染成卡片（B8）、
 * 「她在组织语言」打字中指示；输入 200 字、组字不计；发送前先过本地自伤闸门。
 */
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { CHAT_MAX_CHARS, type ChatMessage } from '../../agent/chatService';
import type { StatusSummary } from '../../agent/chatTools';
import { EASE } from '../../design/tokens';
import { ensureChatLoaded, quickStatus, sendChat, useChat } from '../../store/actions/chat';
import { setUi, useUi } from '../../store/uiStore';
import { Btn, Tap } from '../kit/Btn';
import { Core } from '../kit/Core';
import { IconClose } from '../kit/icons';
import { LimitedInput, charCount } from '../kit/LimitedInput';

function StatusCard({ s }: { s: StatusSummary }) {
  const ratio = s.expNeed ? Math.min(1, s.exp / s.expNeed) : 0;
  return (
    <div className="tool-card status">
      <div className="tc-h">状态快照 · get_status</div>
      <div className="st-lv">
        <b>LV{s.lv}</b>
        <span>
          EXP {s.exp}/{s.expNeed}
        </span>
      </div>
      <div className="st-bar">
        <i style={{ ['--p' as string]: ratio }} />
      </div>
      <div className="st-grid">
        <div>
          <small>连胜</small>
          <b>{s.streak}</b>
        </div>
        <div>
          <small>晶核</small>
          <b>{s.coins}</b>
        </div>
        <div>
          <small>手里</small>
          <b>{s.queue} 单</b>
        </div>
      </div>
      <div className="st-row">
        <small>主线</small>
        <span>{s.goal ? `「${s.goal}」${s.planDone}/${s.planTotal} 单` : '未立目标'}</span>
      </div>
      <div className="st-row">
        <small>战绩</small>
        <span>
          完成 {s.doneCount} · 战败 {s.failCount} · 最好连胜 {s.bestStreak}
        </span>
      </div>
      <div className="st-row">
        <small>最弱维</small>
        <span>
          {s.weakest} {s.weakestValue}
        </span>
      </div>
    </div>
  );
}

const TOOL_LABEL: Record<string, string> = {
  swap_quest: '换任务',
  adjust_plan: '调整计划',
  remember: '记下了',
  recall: '翻记忆',
  summarize_progress: '近况总结',
};

function Bubble({ m }: { m: ChatMessage }) {
  if (m.tool) {
    if (m.tool.name === 'get_status' && m.tool.data)
      return <StatusCard s={m.tool.data as StatusSummary} />;
    return (
      <div className={`tool-card ${m.tool.ok ? '' : 'bad'}`}>
        <div className="tc-h">系统回执 · {TOOL_LABEL[m.tool.name] ?? m.tool.name}</div>
        <p>{m.tool.message}</p>
      </div>
    );
  }
  return <div className={`msg ${m.from} ${m.kind ?? ''}`}>{m.text}</div>;
}

export function ChatPanel() {
  const open = useUi((s) => s.chatOpen);
  const msgs = useChat((s) => s.messages);
  const sending = useChat((s) => s.sending);
  const [text, setText] = useState('');
  const [composing, setComposing] = useState(false);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (open) void ensureChatLoaded();
  }, [open]);
  useEffect(() => {
    list.current?.scrollTo({ top: list.current.scrollHeight });
  }, [msgs.length, sending, open]);
  const send = () => {
    if (composing || !text.trim() || sending) return;
    const t = text;
    setText('');
    void sendChat(t);
  };
  const close = () => setUi({ chatOpen: false });
  return (
    <AnimatePresence>
      {open && (
        <motion.section
          className="chat-panel"
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 30, transition: { duration: 0.24 } }}
          transition={{ duration: 0.42, ease: EASE.ease }}
        >
          <div className="chat-h">
            <Core className="chat-core" />
            <div>
              <b>小祥</b>
              <small>系统娘 · 在线</small>
            </div>
            <Tap className="xbtn" aria-label="关闭" onClick={close}>
              <IconClose />
            </Tap>
          </div>
          <div className="chat-list" ref={list}>
            {msgs.length === 0 && <div className="msg sys">有事说事。我听着。</div>}
            {msgs.map((m) => (
              <Bubble key={m.id} m={m} />
            ))}
            {sending && (
              <div className="msg sys typing">
                她在组织语言<span className="dots">…</span>
              </div>
            )}
          </div>
          <div className="chat-quick">
            <Tap className="chip-opt" quiet disabled={sending} onClick={() => void quickStatus()}>
              查状态
            </Tap>
            <Tap
              className="chip-opt"
              quiet
              disabled={sending}
              onClick={() => void sendChat('帮我换一个任务')}
            >
              换任务
            </Tap>
            <Tap
              className="chip-opt"
              quiet
              disabled={sending}
              onClick={() => void sendChat('帮我调整一下手上这单的计划')}
            >
              调整计划
            </Tap>
          </div>
          <div className="chat-in kb-dock">
            <LimitedInput
              value={text}
              onChange={setText}
              onComposing={setComposing}
              onSubmit={send}
              max={CHAT_MAX_CHARS}
              placeholder="跟她说点什么"
              enterKeyHint="send"
            />
            <Btn kind="pri" sm disabled={composing || !text.trim() || sending} onClick={send}>
              发送
            </Btn>
            <small className="chat-count">
              {composing ? '输入中…' : `${charCount(text)}/${CHAT_MAX_CHARS}`}
            </small>
          </div>
        </motion.section>
      )}
    </AnimatePresence>
  );
}
