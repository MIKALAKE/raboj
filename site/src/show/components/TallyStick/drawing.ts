import type { NotchShape, WoodPalette } from './types';

export const WOOD: WoodPalette = {
  cut: '#4a2a10',
  cutLight: '#f0d3a8',
  dark: '#7a4f27',
  grain: '72,40,14',
  light: '#d6ad78',
  mid: '#b5824a',
};

export const NOTCH_COUNT = 24;
export const STICK_LENGTH = 1400;
const STICK_THICKNESS = 92;

const seeded = (seed: number) => () => {
  seed = (seed * 16807) % 2147483647;
  return (seed - 1) / 2147483646;
};

const shapeRandom = seeded(7);
const NOTCHES: NotchShape[] = Array.from({ length: NOTCH_COUNT }, () => ({
  angle: (shapeRandom() - 0.5) * 0.18,
  depth: 0.6 + shapeRandom() * 0.3,
  width: 12 + shapeRandom() * 5,
}));

export const notchPosition = (index: number) =>
  70 + index * ((STICK_LENGTH - 140) / NOTCH_COUNT) + Math.floor(index / 5) * 6;

const stickOutline = (length: number, thick: number) => {
  const path = new Path2D();
  path.moveTo(10, thick * 0.1);
  path.quadraticCurveTo(length * 0.5, -2, length - 14, thick * 0.14);
  path.quadraticCurveTo(length, thick * 0.5, length - 12, thick * 0.9);
  path.quadraticCurveTo(length * 0.5, thick + 2, 12, thick * 0.88);
  path.quadraticCurveTo(-4, thick * 0.5, 10, thick * 0.1);
  return path;
};

const paintGrain = (context: CanvasRenderingContext2D, length: number, thick: number) => {
  const random = seeded(19);
  for (let line = 0; line < 40; line++) {
    const y = random() * thick;
    const amplitude = 0.5 + random() * 2.2;
    const frequency = 0.003 + random() * 0.008;
    const phase = random() * 6;
    context.strokeStyle = `rgba(${WOOD.grain},${0.06 + random() * 0.12})`;
    context.lineWidth = 0.5 + random() * 1.2;
    context.beginPath();
    for (let x = 0; x <= length; x += 8)
      context.lineTo(x, y + Math.sin(x * frequency + phase) * amplitude);
    context.stroke();
  }
};

const paintEndGrain = (
  context: CanvasRenderingContext2D,
  length: number,
  thick: number
) => {
  context.fillStyle = 'rgba(80,46,18,.55)';
  context.beginPath();
  context.ellipse(length - 8, thick * 0.5, 7, thick * 0.4, 0, 0, Math.PI * 2);
  context.fill();
  for (let ring = 0; ring < 4; ring++) {
    context.strokeStyle = 'rgba(240,200,150,.25)';
    context.beginPath();
    context.ellipse(
      length - 8,
      thick * 0.5,
      5 - ring,
      thick * 0.32 - ring * 3,
      0,
      0,
      Math.PI * 2
    );
    context.stroke();
  }
};

const paintNotch = (context: CanvasRenderingContext2D, thick: number, index: number) => {
  const shape = NOTCHES[index];
  const fifth = index % 5 === 4;
  const bottom = thick * (fifth ? 0.92 : shape.depth);
  context.save();
  context.translate(notchPosition(index), 0);
  context.rotate(shape.angle);
  context.fillStyle = WOOD.cut;
  context.beginPath();
  context.moveTo(-shape.width / 2, -2);
  context.lineTo(shape.width / 2, -2);
  context.lineTo(shape.width * 0.1, bottom);
  context.lineTo(-shape.width * 0.1, bottom);
  context.closePath();
  context.fill();
  context.fillStyle = WOOD.cutLight;
  context.globalAlpha = 0.55;
  context.beginPath();
  context.moveTo(shape.width / 2, -2);
  context.lineTo(shape.width * 0.1, bottom);
  context.lineTo(shape.width * 0.26, -2);
  context.closePath();
  context.fill();
  context.restore();
};

export const drawStick = (context: CanvasRenderingContext2D, notches: number) => {
  const length = STICK_LENGTH;
  const thick = STICK_THICKNESS;
  context.clearRect(0, 0, thick, length);
  context.save();
  context.translate(thick, 0);
  context.rotate(Math.PI / 2);
  const outline = stickOutline(length, thick);
  const body = context.createLinearGradient(0, 0, 0, thick);
  body.addColorStop(0, WOOD.light);
  body.addColorStop(0.5, WOOD.mid);
  body.addColorStop(1, WOOD.dark);
  context.fillStyle = body;
  context.fill(outline);
  context.save();
  context.clip(outline);
  paintGrain(context, length, thick);
  paintEndGrain(context, length, thick);
  const shine = context.createLinearGradient(0, 0, 0, thick);
  shine.addColorStop(0, 'rgba(255,255,255,.3)');
  shine.addColorStop(0.2, 'rgba(255,255,255,0)');
  shine.addColorStop(1, 'rgba(0,0,0,.2)');
  context.fillStyle = shine;
  context.fillRect(0, 0, length, thick);
  for (let index = 0; index < notches; index++) paintNotch(context, thick, index);
  context.restore();
  context.restore();
};
