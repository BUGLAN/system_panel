/** 告知与同意（设置里重看 / 撤回）；撤回后回告知页，请求一律不发 */
import { revokeConsent, useServices } from '../../store/services';
import { go } from '../../store/actions/nav';
import { setUi, toast, useUi } from '../../store/uiStore';
import { Btn } from '../kit/Btn';
import { Sheet } from '../kit/Sheet';
import { NoticeList } from '../scenes/Consent';

export function NoticeSheet() {
  const open = useUi((s) => s.sheet === 'notice');
  const consent = useServices((s) => s.consent);
  return (
    <Sheet open={open} onClose={() => setUi({ sheet: null })} title="告知与同意">
      <NoticeList />
      <p className="sheet-note">
        {consent
          ? `你在 ${new Date(consent.at).toLocaleString('zh-CN')} 点过同意。`
          : '你还没同意。'}
        撤回后她不会再发出任何请求，直到你重新同意。
      </p>
      {consent && (
        <Btn
          kind="ghost"
          sm
          onClick={async () => {
            await revokeConsent();
            setUi({ sheet: null });
            toast('已撤回同意。');
            await go('consent', { noHist: true });
          }}
        >
          撤回同意
        </Btn>
      )}
    </Sheet>
  );
}
