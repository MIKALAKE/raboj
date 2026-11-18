import { DEMO_ACCOUNTS } from 'Constants';

import type { ChipOption, ChipsProps } from './types';

const OPTIONS: ChipOption[] = [
  { color: '#8e8e93', id: 'all', label: 'All' },
  ...DEMO_ACCOUNTS.map(account => ({
    color: account.color,
    id: account.id,
    label: account.label,
  })),
];

const HINT_TARGET = 'work';

const renderChip = (
  { hint, onSelect, selection }: ChipsProps,
  option: ChipOption,
  index: number
) => {
  const active = option.id === selection;
  const pulsing = hint && option.id === HINT_TARGET;
  return (
    <button
      aria-pressed={active}
      className={`flex h-[25px] shrink-0 items-center gap-[5px] rounded-[7px] border-0 px-[9px] text-[11.5px] font-semibold whitespace-nowrap ${active ? 'bg-mac-row shadow-[0_1px_2px_rgba(0,0,0,0.12)]' : 'bg-transparent'} ${pulsing ? 'animate-[hint_1.6s_ease-in-out_infinite]' : ''}`}
      key={option.id}
      onClick={onSelect.bind(null, option.id)}
      title={`${option.label} (⌘${index})`}
      type='button'>
      <span className='dot' style={{ background: option.color }} />
      {option.label}
    </button>
  );
};

const Chips = (props: ChipsProps) => (
  <div className='flex [scrollbar-width:none] gap-[3px] overflow-x-auto rounded-[9px] bg-black/6 p-[3px]'>
    {OPTIONS.map(renderChip.bind(null, props))}
  </div>
);

export default Chips;
