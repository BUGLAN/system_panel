/**
 * 补给（参考稿 #sc-shop）：道具卡轮播；购买（等级不够 / 晶核不够说明原因）；
 * 补签券在这里直接用（只补刚断的那一天，docs/01 Q4）。
 */
import { useRef, useState } from 'react';
import { ITEMS } from '../../core/data/items';
import { QuestFlow } from '../../core/flow/questFlow';
import { useGame } from '../../store/gameStore';
import { now } from '../../store/game';
import { back } from '../../store/actions/nav';
import { buyItem, applyPatchTicket } from '../../store/actions/goals';
import { Btn, Tap } from '../kit/Btn';
import { Carousel, type CarouselApi } from '../kit/Carousel';
import { IconBack, ItemIcon } from '../kit/icons';
import { burst, center, ring, shake } from '../fx/fx';
import { useReveal } from '../hooks/useReveal';

export function Shop() {
  const ref = useRef<HTMLElement>(null);
  const car = useRef<CarouselApi>(null);
  const g = useGame((s) => s.game);
  const [i, setI] = useState(0);
  useReveal(ref);
  const it = ITEMS[i] ?? ITEMS[0];
  if (!it) return null;
  const host = g.host;
  const locked = it.lv > 0 && host.lv < it.lv;
  const short = it.price - host.coins;
  const bad = locked || short > 0;
  const patch = new QuestFlow(g).patchStatus(now());
  const buy = () => {
    if (buyItem(it.id)) {
      const el = car.current?.cardEl(i);
      if (el) {
        el.classList.remove('pop');
        void el.offsetWidth;
        el.classList.add('pop');
        const [x, y] = center(el);
        burst(x, y, {
          n: 38,
          colors: [getComputedStyle(el).getPropertyValue('--gc') || '#fff', '#fff'],
          min: 3,
          max: 12,
          life: 36,
        });
        ring(x, y, '#d6ff3d', 160, 4);
        shake(5, 240);
      }
    }
  };
  return (
    <section className="scene on" id="sc-shop" ref={ref}>
      <div className="sh rv">
        <div>
          <div className="eyebrow">SUPPLY · 补给站</div>
          <h1 className="h1">补给</h1>
        </div>
        <Tap className="xbtn" aria-label="返回" onClick={back}>
          <IconBack />
        </Tap>
      </div>
      <p className="shop-q rv">“晶核是你流的汗变的。花吧，别犹豫。”</p>
      <div className="car" id="shopCar">
        <Carousel
          api={car}
          count={ITEMS.length}
          start={0}
          onFocus={setI}
          onTap={() => buy()}
          cardStyle={(k) => ({ ['--gc' as string]: ITEMS[k]?.color ?? '#fff' })}
          render={(k) => {
            const x = ITEMS[k];
            if (!x) return null;
            const lk = x.lv > 0 && host.lv < x.lv;
            return (
              <>
                <div className="deco">{x.code[0]}</div>
                <div className="it-top">
                  ITEM · {x.code}
                  <span>持有 ×{host.items[x.id] ?? 0}</span>
                </div>
                <div className="it-ic">
                  <ItemIcon id={x.id} />
                </div>
                <div className="it-n">{x.name}</div>
                <div className="it-d">{x.desc}</div>
                <div className="it-f">
                  <span className="own">
                    持有 <b>×{host.items[x.id] ?? 0}</b>
                  </span>
                  <span className={`ptag ${lk ? 'lk' : ''}`}>
                    {lk ? `🔒 LV${x.lv}` : `晶核 ${x.price}`}
                  </span>
                </div>
              </>
            );
          }}
        />
      </div>
      <div className="ruler rv" id="shopRuler">
        {ITEMS.map((x, k) => (
          <i key={x.id} className={k === i ? 'on' : ''} onClick={() => car.current?.go(k)} />
        ))}
      </div>
      {it.id === 'patch' && (host.items['patch'] ?? 0) > 0 && !patch.ok && (
        <p className="shop-why rv">补签券现在用不了：{patch.ok ? '' : patch.reason}</p>
      )}
      <div className="shop-foot rv">
        {it.id === 'patch' && (host.items['patch'] ?? 0) > 0 && (
          <Btn kind="ghost" sm disabled={!patch.ok} onClick={() => applyPatchTicket()}>
            使用
          </Btn>
        )}
        <Btn
          kind="pri"
          onClick={buy}
          style={
            bad
              ? { ['--bd' as string]: '#2c2944', ['--bb' as string]: '#2c2944', color: '#8c88aa' }
              : undefined
          }
        >
          {locked ? `LV${it.lv} 解锁` : short > 0 ? `还差晶核 ${short}` : `购买 · 晶核 ${it.price}`}
        </Btn>
      </div>
    </section>
  );
}
