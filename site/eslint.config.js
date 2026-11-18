import js from '@eslint/js';
import globals from 'globals';
import astro from 'eslint-plugin-astro';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';
import reactHooks from 'eslint-plugin-react-hooks';
import { defineConfig, globalIgnores } from 'eslint/config';

import sortImportsByLength from './eslint-rules/import-rules.js';

const localPlugin = {
  rules: {
    'sort-imports-by-length': sortImportsByLength,
  },
};

const sharedRules = {
  '@typescript-eslint/no-explicit-any': 'off',
  '@typescript-eslint/no-unused-vars': [
    'error',
    {
      argsIgnorePattern: '^_',
      ignoreRestSiblings: true,
      varsIgnorePattern: '^_',
    },
  ],
  'comma-spacing': ['error', { after: true, before: false }],
  'local/sort-imports-by-length': 'error',
  'no-console': ['error', { allow: ['warn', 'error'] }],
};

export default defineConfig([
  globalIgnores(['dist', '.astro', 'src/process/constants/provider-logos.ts']),
  {
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
    ],
    files: ['**/*.{ts,tsx}'],
    languageOptions: { ecmaVersion: 2023, globals: globals.browser },
    plugins: { local: localPlugin },
    rules: sharedRules,
  },
  ...astro.configs.recommended,
  {
    files: ['**/*.astro'],
    plugins: { '@typescript-eslint': tseslint.plugin, local: localPlugin },
    rules: sharedRules,
  },
  {
    files: ['scripts/**/*.mjs', 'eslint-rules/**/*.js', '*.config.{js,mjs}'],
    languageOptions: { globals: globals.node },
  },
  prettier,
]);
