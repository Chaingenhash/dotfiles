export type Preview = { path: string; text: string; mtimeMs: number; error?: string }

declare module 'claude-code' {
  interface PluginState {
    'md-preview': { current: Shaped<Preview | null> }
  }
}
