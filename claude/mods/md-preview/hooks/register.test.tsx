import { expect, test } from 'claude-code/testing'

const FILE = '/proj/docs/05 - Implementation/2026-11-23 - X - Design.md'

function engine(on: any, opened: string[]) {
  on('env.get', () => ({ value: '/home/u' }))
  on('session.cwd', () => ({ value: '/proj' }))
  on('session.root', () => ({ value: '/proj' }))
  on('fs.exists', (_: unknown, e: { path: string }) => ({ value: e.path === FILE }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 5, mtimeMs: 1, isLink: false } }))
  on('fs.read', () => ({ value: '# Hello' }))
  on('ui.open', (_: unknown, e: { id: string }) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

test('a backticked .md path becomes a link that opens the pane', async ($, on) => {
  const opened: string[] = []
  engine(on, opened)

  const ui = await $.ui.mount({
    plugin: 'md-preview',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: {
      text: 'Escrevi em `docs/05 - Implementation/2026-11-23 - X - Design.md`. E `missing.md`.',
      isFirstOfReply: true,
    },
  } as any)

  const md = await ui.find({ type: 'Markdown' })
  expect(md?.text).toContain('(file:///proj/docs/05%20-%20Implementation/')
  expect(md?.text).toContain('`missing.md`.')
  expect(md?.text).not.toContain('[`missing.md`]')

  await ui.press({ key: 'reply', link: { href: 'file:///proj/docs/05%20-%20Implementation/2026-11-23%20-%20X%20-%20Design.md' } } as any)
  expect(opened).toEqual(['md-preview'])
  await ui.unmount()
})

test('a reply without .md paths is left to the engine', async ($, on) => {
  engine(on, [])
  const ui = await $.ui.mount({
    plugin: 'md-preview',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: 'nothing here', isFirstOfReply: true },
  } as any)
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})
