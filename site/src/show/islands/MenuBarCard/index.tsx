import { DEMO_ACCOUNTS } from 'Constants';
import TallyIcon from 'Components/TallyIcon';
import type { DemoAccount } from 'Constants/types';

import type { ModeOption } from './types';
import { MODE_OPTIONS, useMenuBarCard } from './state';

const headline = (account: DemoAccount) =>
  account.limit === null ? (account.cost ?? '') : `${account.limit}%`;

const renderMode = (
  current: string,
  setMode: (mode: ModeOption['id']) => void,
  option: ModeOption
) => (
  <button
    aria-pressed={option.id === current}
    key={option.id}
    onClick={setMode.bind(null, option.id)}
    type='button'>
    {option.label}
  </button>
);

const renderPinned = (account: DemoAccount) => (
  <span className='inline-flex items-center gap-[5px]' key={account.id}>
    <span className='dot' style={{ background: account.color }} />
    {headline(account)}
  </span>
);

const renderToggle = (
  isOn: (id: string) => boolean,
  toggle: (id: string) => void,
  account: DemoAccount
) => (
  <button
    aria-pressed={isOn(account.id)}
    className='inline-flex items-center gap-1.5 border-[1.5px] border-ink/35 bg-transparent px-[9px] py-[3px] text-[13px] aria-pressed:border-ink aria-pressed:bg-ink/8 aria-pressed:font-bold'
    key={account.id}
    onClick={toggle.bind(null, account.id)}
    type='button'>
    <span className='dot' style={{ background: account.color }} />
    {account.label}
  </button>
);

const MenuBarCard = () => {
  const { mode, pinned, selected, setMode, toggleAccount } = useMenuBarCard();
  const selectedAccount = DEMO_ACCOUNTS.find(account => account.id === selected);
  const note = MODE_OPTIONS.find(option => option.id === mode)?.note;
  const isOn = (id: string) =>
    mode === 'pinned' ? pinned.includes(id) : id === selected;

  return (
    <div>
      <div aria-label='Menu bar mode' className='seg mt-4' role='group'>
        {MODE_OPTIONS.map(renderMode.bind(null, mode, setMode))}
      </div>
      <div
        aria-live='polite'
        className='mt-[18px] flex h-[30px] items-center justify-end gap-3.5 overflow-hidden rounded-md bg-[#20242f] px-3 font-mac text-[12.5px] whitespace-nowrap text-[#f2f2f4] tabular-nums'>
        <span className='inline-flex items-center gap-[5px]'>
          <TallyIcon size={15} />
          {mode === 'selection' && selectedAccount && headline(selectedAccount)}
        </span>
        {mode === 'pinned' &&
          DEMO_ACCOUNTS.filter(account => pinned.includes(account.id)).map(renderPinned)}
        <span className='text-[#f2f2f4]/70'>Wed 11:24</span>
      </div>
      <div className='mt-3 flex min-h-7 flex-wrap gap-1.5'>
        {mode !== 'icon' &&
          DEMO_ACCOUNTS.map(renderToggle.bind(null, isOn, toggleAccount))}
      </div>
      <p className='card-foot mt-1'>{note}</p>
    </div>
  );
};

export default MenuBarCard;
