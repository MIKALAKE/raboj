import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const aliases = {
  Root: path.resolve(__dirname, '..'),

  Components: path.resolve(__dirname, '../src/show/components'),
  Docs: path.resolve(__dirname, '../../docs/images'),
  Islands: path.resolve(__dirname, '../src/show/islands'),
  Layouts: path.resolve(__dirname, '../src/show/layouts'),
  Sections: path.resolve(__dirname, '../src/show/sections'),
  Styles: path.resolve(__dirname, '../src/show/styles'),

  Constants: path.resolve(__dirname, '../src/process/constants'),
  Helpers: path.resolve(__dirname, '../src/process/helpers'),
  Hooks: path.resolve(__dirname, '../src/process/hooks'),
};
