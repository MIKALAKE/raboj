import type { ChangeEvent } from 'react';

import type { WindowOption } from './types';
import { usePaceCard, WINDOW_OPTIONS } from './state';

const fromSlider = (
  setter: (value: number) => void,
  event: ChangeEvent<HTMLInputElement>
) => setter(Number(event.target.value));

const renderWindow = (
  current: string,
  onWindow: (id: string) => void,
  option: WindowOption
) => (
  <button
    aria-pressed={option.id === current}
    key={option.id}
    onClick={onWindow.bind(null, option.id)}
    type='button'>
    {option.label}
  </button>
);

const PaceCard = () => {
  const { elapsed, onElapsed, onUsed, onWindow, projected, text, used, warn, windowId } =
    usePaceCard();

  return (
    <div>
      <div aria-label='Limit window' className='seg mt-4' role='group'>
        {WINDOW_OPTIONS.map(renderWindow.bind(null, windowId, onWindow))}
      </div>
      <label
        className='mt-4 grid grid-cols-[1fr_auto] gap-x-2.5 text-sm'
        htmlFor='pace-used'>
        Used
        <output className='font-bold tabular-nums'>{used}%</output>
        <input
          className='col-span-2 w-full accent-margin'
          id='pace-used'
          max={100}
          min={0}
          onChange={fromSlider.bind(null, onUsed)}
          type='range'
          value={used}
        />
      </label>
      <label
        className='mt-3 grid grid-cols-[1fr_auto] gap-x-2.5 text-sm'
        htmlFor='pace-elapsed'>
        Window gone
        <output className='font-bold tabular-nums'>{elapsed}%</output>
        <input
          className='col-span-2 w-full accent-margin'
          id='pace-elapsed'
          max={99}
          min={1}
          onChange={fromSlider.bind(null, onElapsed)}
          type='range'
          value={elapsed}
        />
      </label>
      <div aria-hidden className='relative mt-4 h-2.5 overflow-hidden bg-ink/10'>
        <span
          className='absolute inset-y-0 left-0 bg-[repeating-linear-gradient(-45deg,rgba(194,66,58,0.55)_0_4px,transparent_4px_8px)] transition-[width]'
          style={{ width: `${Math.min(100, projected)}%` }}
        />
        <span
          className='absolute inset-y-0 left-0 bg-ink transition-[width]'
          style={{ width: `${Math.min(100, used)}%` }}
        />
      </div>
      <p
        aria-live='polite'
        className={`mt-3 mb-1 min-h-7 font-print text-[22px] font-bold ${warn ? 'text-margin' : ''}`}>
        {text}
      </p>
      <p className='card-foot'>The same projection Răboj shows under each limit.</p>
    </div>
  );
};

export default PaceCard;
