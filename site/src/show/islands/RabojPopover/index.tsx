import { DEMO_ACCOUNTS } from 'Constants';
import TallyIcon from 'Components/TallyIcon';

import Chips from './subviews/Chips';
import AllView from './subviews/AllView';
import { useRabojPopover } from './state';
import DetailView from './subviews/DetailView';
import type { RabojPopoverProps } from './types';

const RabojPopover = ({ hint = false }: RabojPopoverProps) => {
  const { metric, select, selection, setMetric, showHint } = useRabojPopover(hint);
  const account = DEMO_ACCOUNTS.find(item => item.id === selection);

  return (
    <div
      aria-label='Răboj popover with demo data'
      className='w-[340px] max-w-full rounded-[14px] border border-black/10 bg-mac-bg p-[13px] font-mac text-xs text-mac-fg shadow-[0_30px_60px_-24px_rgba(29,43,79,0.45)]'
      role='region'>
      <div className='mb-2.5 flex items-center gap-[7px] text-sm font-semibold'>
        <TallyIcon size={17} />
        Răboj
      </div>
      <Chips hint={showHint} onSelect={select} selection={selection} />
      {account ? (
        <DetailView account={account} />
      ) : (
        <AllView metric={metric} onMetric={setMetric} />
      )}
      <p className='mt-2 mb-0 text-center text-[10px] text-mac-muted'>
        ⌘0 – ⌘4 switch accounts
      </p>
      <div className='mt-2.5 flex gap-3 border-t border-mac-track pt-2 text-[10.5px] text-mac-muted'>
        <span className='flex-1'>Updated 11:24</span>
        <span>Refresh</span>
        <span>Quit</span>
      </div>
    </div>
  );
};

export default RabojPopover;
