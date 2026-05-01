// VL-WEB-READER - minimal browser entry point for foliate-js, decoupled from
// SaoMai Readmate's Flutter integration (book.js). Used by readmate-web's
// templates/read.html to open an EPUB blob inside <foliate-view> in plain
// Firefox so NVDA browse mode can read the rendered iframe content.
//
// We deliberately do NOT import book.js: that file wires up a Reader class
// that depends on a #footnote-dialog DOM, Flutter callHandler bridges,
// MathCAT key handlers, etc. - all unnecessary for the NVDA reading use
// case. This file mimics only the slice of book.js#getView() that handles
// EPUBs (ZIP -> EPUB), then drives the View custom element manually.

// VL-FLUTTER-STUB - replace SaoMai's Flutter inappwebview bridge with browser-
// safe no-ops. view.js (#onLoad, getMediaOverlay, getElementsText) and the
// vendored book.js both call window.flutter_inappwebview.callHandler at runtime.
// MUST be set BEFORE importing view.js so the stub exists by the time the
// custom-element constructor runs.
if (typeof window !== 'undefined' && !window.flutter_inappwebview) {
  window.flutter_inappwebview = {
    callHandler: async (name) => {
      if (name === 'getElementsText') return ''
      return null
    },
  }
}

// View custom element registration (defines <foliate-view>).
import './view.js'

import { EPUB } from './epub.js'
const { configure, ZipReader, BlobReader, TextWriter, BlobWriter } =
  await import('./vendor/zip.js')

// view.js #handleClick references window.isFootNoteOpen / window.closeFootNote
// (originally provided by book.js). Provide no-op stubs so iframe clicks in
// the rendered EPUB don't throw ReferenceError.
if (typeof window !== 'undefined') {
  window.isFootNoteOpen ??= () => false
  window.closeFootNote ??= () => {}
}

// ZIP -> {loadText, loadBlob, getSize}, the EPUB constructor's input shape.
// Mirrors book.js#makeZipLoader (lines 284-295).
const makeZipLoader = async (file) => {
  configure({ useWebWorkers: false })
  const reader = new ZipReader(new BlobReader(file))
  const entries = await reader.getEntries()
  const map = new Map(entries.map((entry) => [entry.filename, entry]))
  const load = (f) => (name, ...args) =>
    map.has(name) ? f(map.get(name), ...args) : null
  const loadText = load((entry) => entry.getData(new TextWriter()))
  const loadBlob = load((entry, type) => entry.getData(new BlobWriter(type)))
  const getSize = (name) => map.get(name)?.uncompressedSize ?? 0
  return { entries, loadText, loadBlob, getSize }
}

// Permissive defaults for view.readElementsFormat. SaoMai's Readmate sets this
// to a Vietnamese strings table used by extra-info.js (screen-reader hints
// like "tiêu đề cấp [level]") and by tts.js#setReadingFormat. We don't ship
// those strings - NVDA reads HTML semantics natively. A Proxy that returns ''
// for any property access keeps the constructors happy without injecting any
// extra text into the document.
const SILENT_FORMAT = new Proxy({}, { get: () => '' })

// VL-WEB-READER - keydown forwarder injected into each rendered chapter's
// iframe document. Reason: when NVDA browse mode's virtual cursor is inside
// the iframe (which is where it lives once the user is actually reading),
// keypresses are dispatched to the iframe's window first, NOT the parent
// document. A document-level listener on the outer page never sees them. The
// iframe is sandbox="allow-same-origin allow-scripts" so the parent CAN
// reach into iframe.contentDocument and attach handlers.
//
// Two-tier nav (matches the document-level handler in read.html):
//   - Alt+N / Alt+P  -> goNextChapter / goPrevChapter (jump spine sections)
//   - PageDown / PgUp -> goNextPage / goPrevPage     (advance one screenful)
// We attach to each section's contentDocument on every 'load' event.
const installIframeKeyForwarder = (view, goPrevPage, goNextPage, goPrevChapter, goNextChapter) => {
  view.addEventListener('load', (e) => {
    const doc = e.detail?.doc
    if (!doc) return
    if (doc.__readmateKeysBound) return
    doc.__readmateKeysBound = true
    doc.addEventListener('keydown', (ev) => {
      const tag = (ev.target?.tagName || '').toLowerCase()
      if (tag === 'input' || tag === 'textarea' || tag === 'select') return

      // PageDown / PageUp = page-by-page (for laptops that have these keys).
      if (ev.key === 'PageDown' && !ev.ctrlKey && !ev.shiftKey && !ev.altKey && !ev.metaKey) {
        ev.preventDefault(); goNextPage(); return
      }
      if (ev.key === 'PageUp' && !ev.ctrlKey && !ev.shiftKey && !ev.altKey && !ev.metaKey) {
        ev.preventDefault(); goPrevPage(); return
      }
      // Alt+N / Alt+P = chapter-by-chapter (works on laptops without Page
      // keys). Buttons in the parent doc handle page-by-page via click.
      if (ev.altKey && !ev.ctrlKey && !ev.shiftKey && !ev.metaKey) {
        if (ev.code === 'KeyN') { ev.preventDefault(); goNextChapter(); return }
        if (ev.code === 'KeyP') { ev.preventDefault(); goPrevChapter(); return }
      }
    }, true)
  })
}

// Open an EPUB Blob inside an existing <foliate-view> element.
// Returns the parsed book object so callers can read .metadata / .toc later.
export const openEpubInView = async (view, blob, options = {}) => {
  const loader = await makeZipLoader(blob)
  const book = await new EPUB(loader).init()
  // Provide the silent format BEFORE view.open() so #onLoad's load callback
  // can construct TTS without throwing (and so extra-info.js receives a
  // truthy object even though our view.js patch normally bypasses it).
  view.readElementsFormat = SILENT_FORMAT
  // Wire the iframe-level keydown forwarder BEFORE view.open() so we don't
  // miss the first 'load' event. Defaults route directly to the renderer:
  // - page    = renderer.next() / .prev()           (one screenful)
  // - chapter = renderer.nextSection() / .prevSection() (spine entry jump)
  const goPrevPage    = options.goPrevPage    ?? (() => view.renderer?.prev())
  const goNextPage    = options.goNextPage    ?? (() => view.renderer?.next())
  const goPrevChapter = options.goPrevChapter ?? (() => view.renderer?.prevSection())
  const goNextChapter = options.goNextChapter ?? (() => view.renderer?.nextSection())
  installIframeKeyForwarder(view, goPrevPage, goNextPage, goPrevChapter, goNextChapter)
  // Mirror Patch-Readmate-Prefs.ps1 Stage 2 / book.js#setStyle: paginated +
  // no animation. Set BEFORE view.open() so the renderer reads the attribute
  // when it instantiates the paginator.
  await view.open(book, null)
  // VL-WEB-READER - flow=paginated matches the page-by-page mental model
  // students bring from physical textbooks: each Alt+N advances one screenful,
  // and foliate auto-rolls into the next chapter section at the end of the
  // last page. NVDA+A reads what's on the current page, then Alt+N to advance.
  // (Scrolled mode = one tall chapter at a time was tested and felt too
  // unfamiliar for the textbook-reading workflow.)
  view.renderer.setAttribute('flow', 'paginated')
  view.renderer.removeAttribute('animated')
  // Reasonable defaults; book.js builds a much fancier CSS string but we
  // intentionally let the EPUB's own stylesheet through and just constrain
  // the gutter so text isn't flush with the viewport edges.
  view.renderer.setAttribute('gap', '6%')
  view.renderer.setAttribute('top-margin', '20px')
  view.renderer.setAttribute('bottom-margin', '20px')
  view.renderer.setAttribute('max-column-count', '1')
  // Advance to the first page of content. We can't call view.next(): the
  // upstream View.next() (view.js line 614) calls this.tts.from() which
  // throws because TTS is only initialised by initTTS(). The renderer's
  // own next() is what Reader.open() (book.js line 616) uses.
  await view.renderer.next()
  return book
}
