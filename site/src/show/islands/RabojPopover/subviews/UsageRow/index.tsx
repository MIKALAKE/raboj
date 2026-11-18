import type { UsageRowProps } from './types';

const UsageRow = ({
  color,
  dot,
  fraction,
  note,
  subtitle,
  title,
  value,
}: UsageRowProps) => (
  <div className='rounded-[10px] bg-mac-row px-[11px] py-[9px] shadow-[0_1px_2px_rgba(0,0,0,0.06)]'>
    <div className='flex items-center gap-[7px]'>
      {dot && <span className='dot' style={{ background: dot }} />}
      <b className='text-[12.5px]'>{title}</b>
      <span className='flex-1 text-[10.5px] text-mac-muted'>{subtitle}</span>
      <strong className='text-sm tabular-nums'>{value}</strong>
    </div>
    {fraction === null ? (
      <div className='h-1.5' />
    ) : (
      <div className='my-[7px] mb-[5px] h-[5px] overflow-hidden rounded-[3px] bg-mac-track'>
        <span
          className='block h-full rounded-[3px] transition-[width] duration-500'
          style={{ background: color, width: `${fraction * 100}%` }}
        />
      </div>
    )}
    <div className='text-[10.5px] text-mac-muted'>{note}</div>
  </div>
);

export default UsageRow;
