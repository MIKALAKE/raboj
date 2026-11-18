import type { TallyIconProps } from './types';

const NOTCHES = [3, 6.5, 10, 13.5];

const renderNotch = (x: number) => <line key={x} x1={x} x2={x} y1={2.2} y2={11.8} />;

const TallyIcon = ({ className, size = 16, title }: TallyIconProps) => (
  <svg
    aria-hidden={title ? undefined : true}
    className={className}
    fill='none'
    height={size * 0.875}
    role={title ? 'img' : undefined}
    stroke='currentColor'
    strokeLinecap='round'
    strokeWidth={1.6}
    viewBox='0 0 16 14'
    width={size}>
    {title && <title>{title}</title>}
    <g transform='translate(0 14) scale(1 -1)'>
      {NOTCHES.map(renderNotch)}
      <line x1={1.3} x2={15.2} y1={3.6} y2={10.4} />
    </g>
  </svg>
);

export default TallyIcon;
