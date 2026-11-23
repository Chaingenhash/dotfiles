import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Preview } from '../types'

const PANE = 'md-preview'
const current = atom({ plugin: 'md-preview', key: 'current' } as const, null, {
  shape: 'preview-1',
})

// `docs/x y.md` in backticks (spaces allowed), or a bare path with no spaces.
const TICKED = /(^|[^[])`([^`\n]+?\.md)`/g
const BARE = /(^|[\s])((?:~\/|\/|\.\.?\/)?(?:[\w.@+-]+\/)*[\w.@+-]+\.md)(?=$|[\s),;:!?]|\.(?:\s|$))/gm

function toHref(abs: string): string {
  return (
    'file://' +
    encodeURI(abs).replace(/#/g, '%23').replace(/\?/g, '%3F').replace(/\(/g, '%28').replace(/\)/g, '%29')
  )
}

function fromHref(href: string): string {
  return decodeURIComponent(href.replace(/^file:\/\//, ''))
}

function join(dir: string, rel: string): string {
  const parts = (dir.replace(/\/+$/, '') + '/' + rel).split('/')
  const out: string[] = []
  for (const p of parts) {
    if (p === '' || p === '.') continue
    if (p === '..') out.pop()
    else out.push(p)
  }
  return '/' + out.join('/')
}

type Dirs = { home?: string; cwd: string; root: string }

async function resolvePath($: EngineInterface, dirs: Dirs, raw: string): Promise<string | undefined> {
  let candidates: string[]
  if (raw.startsWith('~/')) candidates = dirs.home ? [join(dirs.home, raw.slice(2))] : []
  else if (raw.startsWith('/')) candidates = [raw]
  else candidates = [join(dirs.cwd, raw), join(dirs.root, raw)]
  for (const c of candidates) {
    try {
      if (await $.fs.exists(c)) return c
    } catch {}
  }
  return undefined
}

// Rewrites .md paths outside code fences into file:// links. Returns the new
// text and the hrefs it made, or undefined when nothing resolved.
async function linkify($: EngineInterface, dirs: Dirs, text: string) {
  const hrefs: string[] = []
  const chunks = text.split(/(^```[\s\S]*?^```)/m)
  const out: string[] = []
  for (const chunk of chunks) {
    if (chunk.startsWith('```')) {
      out.push(chunk)
      continue
    }
    const found = new Map<string, string | undefined>()
    for (const m of chunk.matchAll(TICKED)) found.set(m[2] ?? "", undefined)
    for (const m of chunk.matchAll(BARE)) found.set(m[2] ?? "", undefined)
    for (const raw of found.keys()) found.set(raw, await resolvePath($, dirs, raw))
    let next = chunk.replace(TICKED, (all, pre: string, raw: string) => {
      const abs = found.get(raw)
      if (!abs) return all
      const href = toHref(abs)
      hrefs.push(href)
      return `${pre}[\`${raw}\`](${href})`
    })
    // Bare paths only outside the links just made and outside inline code.
    next = next
      .split(/(\[`[^`]*`\]\([^)]*\)|`[^`\n]*`)/)
      .map(part =>
        part.startsWith('[`') || part.startsWith('`')
          ? part
          : part.replace(BARE, (all, pre: string, raw: string) => {
              const abs = found.get(raw)
              if (!abs) return all
              const href = toHref(abs)
              hrefs.push(href)
              return `${pre}[${raw}](${href})`
            }),
      )
      .join('')
    out.push(next)
  }
  return hrefs.length ? { text: out.join(''), hrefs } : undefined
}

async function dirsOf($: EngineInterface): Promise<Dirs> {
  return {
    home: await $.env.get('HOME'),
    cwd: await $.session.cwd(),
    root: await $.session.root(),
  }
}

async function load($: EngineInterface, path: string) {
  let next: Preview
  try {
    const st = await $.fs.stat(path)
    const text = await $.fs.read(path)
    next = { path, text, mtimeMs: st.mtimeMs }
  } catch (err) {
    next = { path, text: '', mtimeMs: 0, error: String(err) }
  }
  await update($, current, () => next)
}

async function show($: EngineInterface, path: string) {
  await load($, path)
  const name = path.split('/').pop() ?? path
  await $.ui.open({ id: PANE, title: name.length > 40 ? name.slice(0, 39) + '…' : name })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'md-preview',
      description: 'Preview a markdown file in the side pane',
      argumentHint: '<path.md>',
    })
    // Live refresh: re-read the open file when it changes on disk.
    $.clock.every(1500, async () => {
      const cur = await read($, current)
      if (!cur || cur.error) return
      try {
        const st = await $.fs.stat(cur.path)
        if (st.mtimeMs !== cur.mtimeMs) await load($, cur.path)
      } catch {}
    })
    return next(e)
  })

  on('command.run', { command: 'md-preview' }, async ($, e) => {
    const raw = e.args.trim().replace(/^["'`]|["'`]$/g, '')
    if (!raw) {
      const cur = await read($, current)
      if (!cur) return { text: 'Usage: /md-preview <path.md>' }
      await show($, cur.path)
      return { text: `Previewing ${cur.path}` }
    }
    const abs = await resolvePath($, await dirsOf($), raw)
    if (!abs) return { text: `Not found: ${raw}` }
    await show($, abs)
    return { text: `Previewing ${abs}` }
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    if (e.props.isSummary || !/\.md\b/.test(e.props.text)) return next(e)
    const made = await linkify($, await dirsOf($), e.props.text)
    if (!made) return next(e)
    const { Box, Text, Markdown } = $.ui.resolve(e)
    return (
      <Box flexDirection="row">
        <Box width={2} flexShrink={0}>
          <Text>{e.props.isFirstOfReply ? '●' : ' '}</Text>
        </Box>
        <Box flexGrow={1} flexShrink={1}>
          <Markdown
            key="reply"
            text={made.text}
            pressableLinks={made.hrefs.slice(0, 256)}
            onLinkPress={link => show($, fromHref(link.href))}
          />
        </Box>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Markdown } = $.ui.resolve(e)
    const cur = await read($, current)
    if (!cur) return <Text dimColor>Click a .md path in a reply, or /md-preview &lt;path&gt;.</Text>
    return (
      <Box flexDirection="column">
        <Text dimColor>{cur.path}</Text>
        <Text> </Text>
        {cur.error ? (
          <Text color="red">{cur.error}</Text>
        ) : (
          <Markdown text={cur.text || '_(empty file)_'} />
        )}
      </Box>
    )
  })
}
