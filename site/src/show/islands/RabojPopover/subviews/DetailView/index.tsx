import { WEEKDAYS } from 'Constants';
import type { DemoWindow } from 'Constants/types';

import UsageRow from '../UsageRow';
import type { DetailViewProps } from './types';

const CHART_HEIGHT = 40;

const renderWindow = (color: string, window: DemoWindow) => (
  <UsageRow
    color={color}
    fraction={window.used / 100}
    key={window.title}
    note={window.note}
    title={window.title}
    value={`${window.used}%`}
  />
);

const renderDay = (color: string, height: number, index: number) => (
  <div
    className='flex h-full flex-1 flex-col items-center justify-end gap-[3px]'
    key={WEEKDAYS[index]}>
    <span
      className='w-full rounded-[3px]'
      style={{
        background: color,
        height: height * CHART_HEIGHT,
        opacity: index === 6 ? 1 : 0.5,
      }}
    />
    <small className='text-[8.5px] text-mac-muted'>{WEEKDAYS[index]}</small>
  </div>
);

const DetailView = ({ account }: DetailViewProps) => (
  <>
    <div className='my-2.5 flex justify-between text-[11.5px]'>
      <b className='font-semibold'>
        {account.label} · {account.provider}
      </b>
      <span className='text-mac-muted'>today</span>
    </div>
    <div className='grid gap-[7px]'>
      {account.windows.map(renderWindow.bind(null, account.color))}
      <div className='rounded-[10px] bg-mac-row px-[11px] py-[9px] shadow-[0_1px_2px_rgba(0,0,0,0.06)]'>
        <div className='flex items-center'>
          <b className='flex-1 text-[12.5px]'>
            {account.cost ? 'Billed today' : 'Tokens today'}
          </b>
          <strong className='text-sm tabular-nums'>
            {account.cost ?? account.tokens}
          </strong>
        </div>
        <div className='mt-2 flex h-[54px] items-end gap-1'>
          {account.week.map(renderDay.bind(null, account.color))}
        </div>
      </div>
    </div>
  </>
);

export default DetailView;
