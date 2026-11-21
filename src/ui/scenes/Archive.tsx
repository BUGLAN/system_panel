/** 占位：后续步骤实现 */
import { back } from '../../store/actions/nav';
import { Tap } from '../kit/Btn';
import { IconBack } from '../kit/icons';

export function Archive() {
  return (
    <section className="scene on">
      <div className="sh">
        <div>
          <div className="eyebrow">Archive</div>
          <h1 className="h1">建设中</h1>
        </div>
        <Tap className="xbtn" aria-label="返回" onClick={back}>
          <IconBack />
        </Tap>
      </div>
    </section>
  );
}
