/// <reference types="vitest/config" />
import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react, { reactCompilerPreset } from '@vitejs/plugin-react'
import babel from '@rolldown/plugin-babel'

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8')) as {
  version: string
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    babel({ presets: [reactCompilerPreset()] })
  ],
  // Stamped into exported reports and CSVs so every output records the
  // software version that produced it (provenance).
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  test: {
    include: ['src/**/*.test.ts'],
  },
})
