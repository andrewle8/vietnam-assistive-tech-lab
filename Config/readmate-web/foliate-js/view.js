import * as EXTRA_INFO from './extra-info.js'
import * as MathCAT from './mathcat-nav.js'

import * as CFI from './epubcfi.js'
import { TOCProgress, SectionProgress } from './progress.js'
import { Overlayer } from './overlayer.js'
import { textWalker } from './text-walker.js'
const { TTS } = await import('./tts.js')

import init, {init_mathcat, init_nav_mathcat,
                navigate_by_keypress, navigate_by_command,
                set_math, translate_mathcat } from './pkg/libmathcat.js';
await init()

const SEARCH_PREFIX = 'foliate-search:'

class History extends EventTarget {
    #arr = []
    #index = -1
    pushState(x) {
        const last = this.#arr[this.#index]
        if (last === x || last?.fraction && last.fraction === x.fraction) return
        this.#arr[++this.#index] = x
        this.#arr.length = this.#index + 1
        this.dispatchEvent(new Event('index-change'))
        this.dispatchEvent(new CustomEvent('pushstate', { detail: x }))
    }
    replaceState(x) {
        const index = this.#index
        this.#arr[index] = x
    }
    back() {
        const index = this.#index
        if (index <= 0) return
        const detail = { state: this.#arr[index - 1] }
        this.#index = index - 1
        this.dispatchEvent(new CustomEvent('popstate', { detail }))
        this.dispatchEvent(new Event('index-change'))
    }
    forward() {
        const index = this.#index
        if (index >= this.#arr.length - 1) return
        const detail = { state: this.#arr[index + 1] }
        this.#index = index + 1
        this.dispatchEvent(new CustomEvent('popstate', { detail }))
        this.dispatchEvent(new Event('index-change'))
    }
    get canGoBack() {
        return this.#index > 0
    }
    get canGoForward() {
        return this.#index < this.#arr.length - 1
    }
    clear() {
        this.#arr = []
        this.#index = -1
    }
}

const languageInfo = lang => {
    if (!lang) return {}
    try {
        const canonical = Intl.getCanonicalLocales(lang)[0] ?? 'en'
        const locale = new Intl.Locale(canonical)
        const isCJK = ['zh', 'ja', 'kr'].includes(locale.language)
        const direction = (locale.getTextInfo?.() ?? locale.textInfo)?.direction
        return { canonical, locale, isCJK, direction }
    } catch (e) {
        console.warn(e)
        return {}
    }
}

const { SHOW_ELEMENT, SHOW_TEXT, SHOW_CDATA_SECTION,
        FILTER_ACCEPT, FILTER_REJECT, FILTER_SKIP } = NodeFilter
const filter = SHOW_ELEMENT | SHOW_TEXT | SHOW_CDATA_SECTION

async function getMediaOverlay() {
    return await window.flutter_inappwebview.callHandler("getMediaOverlay");
}

async function getElementsText() {
    const res = await window.flutter_inappwebview.callHandler("getElementsText");
    //console.log(res)
    return res;
}

export class View extends HTMLElement {
    #root = this.attachShadow({ mode: 'open' })
    #sectionProgress
    #tocProgress
    #pageProgress
    #searchResults = new Map()
    #index
    #num_of_sections
    #smils
    isFixedLayout = false
    lastLocation
    history = new History()
    headings = []
    pagebreaks = []
    paragraphs = []
    headings1 = []
    headings12 = []
    headingsAny = []

    readElementsFormat
    mathCatSettings

    constructor() {
        super()
        this.history.addEventListener('popstate', ({ detail }) => {
            const resolved = this.resolveNavigation(detail.state)
            this.renderer.goTo(resolved)
        })
    }
    async open(book, mathCatSettings) {
        await this.initMathCat(mathCatSettings)
        //this.#smils = await getMediaOverlay();
        //console.log("SMILS: ", this.#smils)
        
        this.book = book
        this.language = languageInfo(book.metadata?.language)

        if (book.splitTOCHref && book.getTOCFragment) {
            const ids = book.sections.map(s => s.id)
            this.#sectionProgress = new SectionProgress(book.sections, 1500, 1600)
            const splitHref = book.splitTOCHref.bind(book)
            const getFragment = book.getTOCFragment.bind(book)
            this.#tocProgress = new TOCProgress()
            await this.#tocProgress.init({
                toc: book.toc ?? [], ids, splitHref, getFragment
            })
            this.#pageProgress = new TOCProgress()
            await this.#pageProgress.init({
                toc: book.pageList ?? [], ids, splitHref, getFragment
            })
        }

        this.isFixedLayout = this.book.rendition?.layout === 'pre-paginated'
        if (this.isFixedLayout) {
            await import('./fixed-layout.js')
            this.renderer = document.createElement('foliate-fxl')
        } else {
            await import('./paginator.js')
            this.renderer = document.createElement('foliate-paginator')
        }
        
        this.renderer.setAttribute('exportparts', 'head,foot,filter')
        this.renderer.addEventListener('load', e => this.#onLoad(e.detail))
        this.renderer.addEventListener('relocate', e => this.#onRelocate(e.detail))
        this.renderer.addEventListener('create-overlayer', e =>
            e.detail.attach(this.#createOverlayer(e.detail)))
        this.renderer.open(book)
        this.#root.append(this.renderer)

        this.#num_of_sections = book.sections.length

        if (book.sections.some(section => section.mediaOverlay)) {
            book.media.activeClass ||= '-epub-media-overlay-active'
            const activeClass = book.media.activeClass
            this.mediaOverlay = book.getMediaOverlay()
            let lastActive
            this.mediaOverlay.addEventListener('highlight', e => {
                const resolved = this.resolveNavigation(e.detail.text)
                this.renderer.goTo(resolved)
                    .then(() => {
                        const { doc } = this.renderer.getContents()
                            .find(x => x.index = resolved.index)
                        const el = resolved.anchor(doc)
                        el.classList.add(activeClass)
                        lastActive = new WeakRef(el)
                    })
            })
            this.mediaOverlay.addEventListener('unhighlight', () => {
                lastActive?.deref()?.classList?.remove(activeClass)
            })
        }
        
        await this.#searchKeyPoints()
    }
    close() {
        this.renderer?.destroy()
        this.renderer?.remove()
        this.#sectionProgress = null
        this.#tocProgress = null
        this.#pageProgress = null
        this.#searchResults = new Map()
        this.lastLocation = null
        this.history.clear()
        this.tts = null
        this.mediaOverlay = null
    }
    goToTextStart() {
        return this.goTo(this.book.landmarks
            ?.find(m => m.type.includes('bodymatter') || m.type.includes('text'))
            ?.href ?? this.book.sections.findIndex(s => s.linear !== 'no'))
    }
    async init({ lastLocation, showTextStart }) {
        const resolved = lastLocation ? this.resolveNavigation(lastLocation) : null
        if (resolved) {
            await this.renderer.goTo(resolved)
            this.history.pushState(lastLocation)
        } else if (showTextStart) {
            await this.goToTextStart()
        } else {
            this.history.pushState(0)
            await this.next()
        }
    }
    #emit(name, detail, cancelable) {
        return this.dispatchEvent(new CustomEvent(name, { detail, cancelable }))
    }

    #onRelocate({ reason, range, index, fraction, size }) {
        //console.log('#onRelocate: ', reason, "\n", range.toString());
        this.#index = index
        const chapterLocation = {
            current: this.renderer.page,
            total: this.renderer.pages - 2
        }
        const progress = this.#sectionProgress?.getProgress(index, fraction, size) ?? {}
        const tocItem = this.#tocProgress?.getProgress(index, range)
        const pageItem = this.#pageProgress?.getProgress(index, range)
        const cfi = this.getCFI(index, range)
        const numChapters = this.#num_of_sections
        const currentChapter = this.#index
        this.lastLocation = { ...progress, tocItem, pageItem, cfi, range,
                                    chapterLocation, currentChapter, numChapters }
        if (reason === 'snap' || reason === 'page' || reason === 'scroll')
            this.history.replaceState(cfi)
        this.#emit('relocate', this.lastLocation)
        
        if(this.tts)
            this.tts.from(this.lastLocation.range)
    }

    async initMathCat(settings)  {
        //console.log("Init MathCAT")
        if(settings) {
            await init_mathcat(settings['language'], settings['style'],
                                settings['verbosity'], settings['impairment'], settings['chemistry'])
            await init_nav_mathcat(settings['nav_mode'], settings['nav_verbosity'])
        }
        //console.log("Init MathCAT completed")
    }

    resolveMath(doc) {
        //console.log("resolveMath");
        //console.log(doc.documentElement.outerHTML)
        for (const math of doc.querySelectorAll('math')) {
            if (math.getAttribute('display') === 'inline') {
                math.setAttribute('display', 'block');
            }
            const mathML = math.outerHTML
            //console.log(mathML)
            const speech = translate_mathcat(mathML)
            //console.log("MATH: ", speech)
            const lst = math.querySelectorAll("annotation");
            if(lst.length > 0) {
                lst[0].setAttribute("encoding", "text/plain")
                lst[0].textContent = speech
            } else {
                const anno = doc.createElement('annotation')
                anno.setAttribute("encoding", "text/plain")
                anno.textContent = speech
                math.appendChild(anno)
            }

            const parent = math.parentNode
            const divOuter = doc.createElement('div');
            divOuter.setAttribute("role", "button")
            divOuter.setAttribute("aria-label", speech)
            
            const divInner = doc.createElement('div');
            divInner.setAttribute("aria-hidden", "true")
            divOuter.appendChild(divInner);

            parent.insertBefore(divOuter, math);
            divInner.appendChild(math);

        }
    }

    #onLoad({ doc, index }) {
        // set language and dir if not already set
        doc.documentElement.lang ||= this.language.canonical ?? ''
        if (!this.language.isCJK)
            doc.documentElement.dir ||= this.language.direction ?? ''
        const { book } = this
        const section = book.sections[index]
        this.#handleLinks(doc, index)
        this.#handleClick(doc)
        this.#handleImage(doc)
        // VL-WEB-READER - addExtraInfo injects Vietnamese screen-reader hints
        // ("Tiêu đề cấp 2", "danh sách 5 mục", image src URLs, ...) intended
        // for SaoMai's Microsoft An TTS pipeline. NVDA browse mode already
        // announces HTML semantics natively, so this pass is pure noise for
        // our use case. We skip it unconditionally on the readmate-web stack.
        if (false && (!this.#smils || this.#smils.length == 0)) {
            EXTRA_INFO.addExtraInfo(doc, book, section, this.#smils, this.readElementsFormat)
        }
        // stop TTS
        this.#getOverlayer(this.#index)?.overlayer.remove(this.oldValue)

        this.resolveMath(doc)
        this.#handleMath(doc)
        
        getMediaOverlay().then((val) => {
            //console.log("getMediaOverlay")
            this.#smils = val
            this.initTTS()
            this.#emit('load', { doc, index })
        });
    }
    
    #handleLinks(doc, index) {
        const { book } = this
        const section = book.sections[index]
        for (const a of doc.querySelectorAll('div[href]'))
            a.addEventListener('click', e => {
                //console.log("HREF clicked!")
                e.preventDefault()
                e.stopPropagation()
                const href_ = a.getAttribute('href')
                const href = section?.resolveHref?.(href_) ?? href_
                if (book?.isExternal?.(href)) {
                    //console.log("external-link: ", href)
                    Promise.resolve(this.#emit('external-link', { a, href }, true))
                        .then(x => x ? globalThis.open(href, '_blank') : null)
                        .catch(e => console.error(e))
                } else {
                    //console.log("internal-link!")
                    Promise.resolve(this.#emit('link', { a, href }, true))
                    .then(x => x ? this.goTo(href) : null)
                    .catch(e => console.error(e))
                }
            })
    }

    #handleMath(doc) {
        //const { book } = this
        //const section = book.sections[index]
        for (const math of doc.querySelectorAll('div[role="button"]'))
            math.addEventListener('click', e => {
                //console.log("Math clicked!")
                const mathML = math.querySelector("div")
                //console.log(mathML.innerHTML)
                set_math(mathML.innerHTML)
                
                e.preventDefault()
                e.stopPropagation()
                
                const cmd = ["MovePrevious", "MoveNext", "MoveStart", "MoveEnd", "MoveLineStart", "MoveLineEnd",
                            "MoveCellPrevious", "MoveCellNext", "MoveCellUp", "MoveCellDown", "MoveColumnStart", "MoveColumnEnd",
                            "ZoomIn", "ZoomOut", "ZoomOutAll", "ZoomInAll",
                            "MoveLastLocation"];
                MathCAT.createDynamicDialog({
                    title: 'MathCAT Navigator',
                    content: "Please choose a Nav cmd from list.\n Click Apply to repeat cmd as needed.",
                    showDropdown: true,
                    dropdownItems: cmd,
                    leftCmd: 'MovePrevious',
                    rightCmd: 'MoveNext',
                    upCmd: 'MoveStart',
                    downCmd: 'MoveEnd',
                    applyButtonText: 'Apply',
                    onApply: (selectedCmd, resultLabel) => {
                        if (selectedCmd) {
                            //console.log("navigate_by_command: " + selectedCmd);
                            var txt = navigate_by_command(selectedCmd)
                            resultLabel.textContent = txt;
                            resultLabel.style.color = '#28a745'; // Green
                        } else {
                            resultLabel.textContent = 'No cmd selected.';
                            resultLabel.style.color = '#dc3545'; // Red
                        }
                    },
                    
                    onClose: () => {
                        //console.log('Nav dialog closed.');
                    },
                    onKeyPress: (key, shiftKey, ctrlKey, altKey, metaKey, resultLabel) => {
                        //console.log("navigate_by_key: ", key);
                        const validKeys = new Map([
                            ['Enter', 0x0D], [' ', 0x20], ['Home', 0x24], ['End', 0x23], ['Backspace', 0x08],
                            ['Arrow Down', 0x28], ['Arrow Left', 0x25], ['Arrow Right', 0x27], ['Arrow Up', 0x26],
                            ['0', 0x30], ['1', 0x31], ['2', 0x32], ['3', 0x32], ['4', 0x34],
                            ['5', 0x35], ['6', 0x36], ['7', 0x37], ['8', 0x38], ['9', 0x39],
                        ]);
                        
                        if(validKeys.has(key)) {
                            const val = validKeys.get(key);
                            //console.log("val: ", val);
                            var txt = navigate_by_keypress(val, shiftKey, ctrlKey, altKey, metaKey);
                            if(txt) {
                                resultLabel.textContent = txt;
                                resultLabel.style.color = '#28a745'; // Green
                            }
                        }
                    }
                });
            })
    }

    #handleImage(doc) {
        for (const img of doc.querySelectorAll('img')) {
         // disable for a link
            if (img.closest('a[href]')) continue;
            img.addEventListener('click', e => {
                e.preventDefault()
                e.stopPropagation()
                this.#emit('click-image', { img })
            })
        }
    }

    #handleClick(doc) {
        doc.addEventListener('click', e => {
            if (window.isFootNoteOpen()){
                window.closeFootNote()
                return
            }

            if (doc.getSelection().type === "Range")
                return
            let { clientX, clientY } = e
            // add top margin to y, y is relative to the iframe
            const topMargin = this.renderer.getAttribute('top-margin').match(/\d+/)[0]
            clientY += parseInt(topMargin)
            
            this.renderer.scrollProp == 'scrollLeft'
                ? clientX -= (this.renderer.start - this.renderer.size) 
                : clientY -= (this.renderer.start)
                
            this.#emit('click-view', { x: clientX, y: clientY })
        })
        this.renderer.addEventListener('click', e => {
            const { clientX, clientY } = e
            while (clientX > window.innerWidth) {
                clientX -= window.innerWidth
            }
            this.#emit('click-view', { x: clientX, y: clientY })
        })
    }
    async addAnnotation(annotation, remove) {
        const {id, value, readerNote } = annotation
        console.log("addAnnotation: id=", id, " val=", value);
        if (value.startsWith(SEARCH_PREFIX)) {
            const cfi = value.replace(SEARCH_PREFIX, '')
            const { index, anchor } = await this.resolveNavigation(cfi)
            const obj = this.#getOverlayer(index)
            if (obj) {
                const { overlayer, doc } = obj
                if (remove) {
                    overlayer.remove(value)
                    return
                }
                const range = doc ? anchor(doc) : anchor
                overlayer.add(value, range, Overlayer.outline, { color: '#39c5bbaa' });
            }
            return
        }
        const { index, anchor } = await this.resolveNavigation(value)
        const obj = this.#getOverlayer(index)
        if (obj) {
            const { overlayer, doc } = obj
            overlayer.remove(value)
            if (!remove) {
                const range = doc ? anchor(doc) : anchor
                
                const span = doc.createElement('span')
                span.setAttribute("extra-text",
                            this.readElementsFormat['element_note'] + ": " + readerNote)
                span.setAttribute("parent-tag", "note")
                span.id = 'extra-user-note-' + id
                span.classList.add('smr-format-info');
                //span.textContent = readerNote;
                //span.style.color = 'red';
                //span.style.fontWeight = 'bold';
                //span.style.fontSize = '0.5rem';
                range.insertNode(span)                
                //span.appendChild(range.extractContents());
                //range.insertNode(span);

                const draw = (func, opts) => overlayer.add(value, range, func, opts)
                this.#emit('draw-annotation', { draw, annotation, doc, range })
            } else {                
                const span_id = 'extra-user-note-' + id;                                
                const spans = doc.querySelectorAll('span[id="' + span_id + '"]');                
                spans.forEach(span => {                         
                    span.remove();                         
                });                
            }
        }
        const label = this.#tocProgress.getProgress(index)?.label ?? ''
        return { index, label }
    }
    deleteAnnotation(annotation) {
        return this.addAnnotation(annotation, true)
    }
    #getOverlayer(index) {
        return this.renderer.getContents()
            .find(x => x.index === index && x.overlayer)
    }
    #createOverlayer({ doc, index }) {
        const overlayer = new Overlayer()
        doc.addEventListener('click', e => {
            const [value, range] = overlayer.hitTest(e)
            if (value && !value.startsWith(SEARCH_PREFIX)) {
                e.preventDefault()
                e.stopPropagation()
                this.#emit('show-annotation', { value, index, range })
            }
        }, true)

        const list = this.#searchResults.get(index)
        if (list) for (const item of list) this.addAnnotation(item)

        this.#emit('create-overlay', { index })
        return overlayer
    }
    async showAnnotation(annotation) {
        const { value } = annotation
        const resolved = await this.goTo(value)
        if (resolved) {
            const { index, anchor } = resolved
            const { doc } = this.#getOverlayer(index)
            const range = anchor(doc)
            this.#emit('show-annotation', { value, index, range })
        }
    }
    getCFI(index, range) {
        const baseCFI = this.book.sections[index].cfi ?? CFI.fake.fromIndex(index)
        if (!range) return baseCFI
        return CFI.joinIndir(baseCFI, CFI.fromRange(range))
    }
    resolveCFI(cfi) {
        if (this.book.resolveCFI)
            return this.book.resolveCFI(cfi)
        else {
            const parts = CFI.parse(cfi)
            const index = CFI.fake.toIndex((parts.parent ?? parts).shift())
            const anchor = doc => CFI.toRange(doc, parts)
            return { index, anchor }
        }
    }
    resolveNavigation(target) {
        try {
            if (typeof target === 'number') return { index: target }
            if (typeof target.fraction === 'number') {
                const [index, anchor] = this.#sectionProgress.getSection(target.fraction)
                return { index, anchor }
            }
            if (CFI.isCFI.test(target)) return this.resolveCFI(target)
            return this.book.resolveHref(target)
        } catch (e) {
            console.error(e)
            console.error(`Could not resolve target ${target}`)
        }
    }
    async goTo(target) {
        const resolved = this.resolveNavigation(target)
        try {
            await this.renderer.goTo(resolved)
            this.history.pushState(target)
            return resolved
        } catch (e) {
            console.error(e)
            console.error(`Could not go to ${target}`)
        }
    }
    async goToFraction(frac) {
        const [index, anchor] = this.#sectionProgress.getSection(frac)
        await this.renderer.goTo({ index, anchor })
        this.history.pushState({ fraction: frac })
    }
    async select(target) {
        try {
            const obj = await this.resolveNavigation(target)
            await this.renderer.goTo({ ...obj, select: true })
            this.history.pushState(target)
        } catch (e) {
            console.error(e)
            console.error(`Could not go to ${target}`)
        }
    }
    deselect() {
        for (const { doc } of this.renderer.getContents())
            doc.defaultView.getSelection().removeAllRanges()
    }
    getSectionFractions() {
        return (this.#sectionProgress?.sectionFractions ?? [])
            .map(x => x + Number.EPSILON)
    }
    getProgressOf(index, range) {
        const tocItem = this.#tocProgress?.getProgress(index, range)
        const pageItem = this.#pageProgress?.getProgress(index, range)
        return { tocItem, pageItem }
    }
    async getTOCItemOf(target) {
        try {
            const { index, anchor } = await this.resolveNavigation(target)
            const doc = await this.book.sections[index].createDocument()
            const frag = anchor(doc)
            const isRange = frag instanceof Range
            const range = isRange ? frag : doc.createRange()
            if (!isRange) range.selectNodeContents(frag)
            return this.#tocProgress.getProgress(index, range)
        } catch (e) {
            console.error(e)
            console.error(`Could not get ${target}`)
        }
    }
    async prev(distance) {
        await this.renderer.prev(distance)
        return this.tts.from(this.lastLocation.range)
    }
    async next(distance) {
        await this.renderer.next(distance)
        return this.tts.from(this.lastLocation.range)
    }

    async prevTags(tags) {
        if(tags && tags.length > 0) {
            await this.tts.prevTags(tags)
        } else {
            await this.tts.prev(true)
        }
    }

    async nextTags(tags) {
        if(tags && tags.length > 0) {
            await this.tts.nextTags(tags)
        } else {
            await this.tts.next(true)
        }
    }

    goLeft() {
        return this.book.dir === 'rtl' ? this.next() : this.prev()
    }
    goRight() {
        return this.book.dir === 'rtl' ? this.prev() : this.next()
    }
    async * #searchSection(matcher, query, index) {
        const doc = await this.book.sections[index].createDocument()
        for (const { range, excerpt } of matcher(doc, query))
            yield { cfi: this.getCFI(index, range), excerpt }
    }
    async * #searchBook(matcher, query) {
        const { sections } = this.book
        for (const [index, { createDocument }] of sections.entries()) {
            if (!createDocument) continue
            const doc = await createDocument()
            const subitems = Array.from(matcher(doc, query), ({ range, excerpt }) =>
                ({ cfi: this.getCFI(index, range), excerpt }))
            const progress = (index + 1) / sections.length
            yield { progress }
            if (subitems.length) yield { index, subitems }
        }
    }

    async #searchKeyPoints() {
        const { sections } = this.book
        for (const [index, { createDocument }] of sections.entries()) {
            if (!createDocument) continue
            const doc = await createDocument()
            
            var headings = doc.querySelectorAll("h1, h2, h3, h4, h5, h6, p")
            headings.forEach(element => {
                if(element.textContent.trim() == "") return;
                
                var range = doc.createRange();
                range.selectNodeContents(element);
                //range.selectNode(element);
                var cfi = this.getCFI(index, range);

                if(element.tagName == "h1" || element.tagName == "h2" || element.tagName == "h3") {
                    this.headings.push({
                        tag: element.tagName,
                        text: element.textContent.replaceAll('\n', ' ').trim(),
                        cfi: cfi
                    })
                    //console.log(index, ": ", element.tagName, " ", element.textContent.replaceAll('\n', ' ').trim(), " ", cfi);
                }
                
                if(element.tagName == "h1") {
                    this.headings1.push({cfi: cfi})
                    this.headings12.push({cfi: cfi})
                    this.headingsAny.push({cfi: cfi})
                    this.paragraphs.push({cfi: cfi})
                } else if(element.tagName == "h2") {
                    this.headings12.push({ cfi: cfi })
                    this.headingsAny.push({ cfi: cfi})
                    this.paragraphs.push({cfi: cfi})
                } else if(element.tagName != "p"){
                    this.headingsAny.push({cfi: cfi})
                    this.paragraphs.push({cfi: cfi})
                } else {
                    this.paragraphs.push({cfi: cfi})
                }
            });
            
            //var es = doc.querySelectorAll('span');
            //es.forEach(element => {
            //    console.log(element.outerHTML)
            //});

            //var pagebreaks = doc.querySelectorAll('[epub\\:type="pagebreak"]');
            var pagebreaks = doc.querySelectorAll('[role="doc-pagebreak"]');
            /*
            //console.log('1 #searchPages: ', pagebreaks.length)
            if(pagebreaks.length == 0) {
                pagebreaks = doc.querySelectorAll('[style*="page-break-before"]')
            }
            //console.log('2 #searchPages: ', pagebreaks.length)

            if(pagebreaks.length == 0) {
                const elements = document.querySelectorAll('span');
                pagebreaks = Array.from(elements).filter(el =>
                    el.getAttributeNS('http://www.idpf.org/2007/ops', 'type') === 'pagebreak'
                );
            }
            //console.log('3 #searchPages: ', pagebreaks.length)
            */
            pagebreaks.forEach(element => {
                var range = doc.createRange();
                range.selectNode(element);
                this.pagebreaks.push({
                    cfi: this.getCFI(index, range)
                })
            });

            var paragraphs = doc.querySelectorAll('p');
            paragraphs.forEach(element => {
                var range = doc.createRange();
                range.selectNode(element);
                this.paragraphs.push({
                    cfi: this.getCFI(index, range)
                })
            });
        }
    }

    async * search(opts) {
        //console.log('search', opts)
        this.clearSearch()
        const { searchMatcher } = await import('./search.js')
        const { query, index } = opts
        const matcher = searchMatcher(textWalker,
            { defaultLocale: this.language, ...opts })
        const iter = index != null
            ? this.#searchSection(matcher, query, index)
            : this.#searchBook(matcher, query)

        const list = []
        this.#searchResults.set(index, list)

        for await (const result of iter) {
            if (result.subitems) {
                const list = result.subitems
                    .map(({ cfi }) => ({ value: SEARCH_PREFIX + cfi }))
                this.#searchResults.set(result.index, list)
                for (const item of list) this.addAnnotation(item)
                yield {
                    label: this.#tocProgress.getProgress(result.index)?.label ?? '',
                    subitems: result.subitems,
                }
            }
            else {
                if (result.cfi) {
                    const item = { value: SEARCH_PREFIX + result.cfi }
                    list.push(item)
                    this.addAnnotation(item)
                }
                yield result
            }
        }
        yield 'done'
    }
    clearSearch() {
        for (const list of this.#searchResults.values())
            for (const item of list) this.deleteAnnotation(item)
        this.#searchResults.clear()
    }
    oldValue = null
    initTTS(stop) {
        if (stop)
            return this.#getOverlayer(this.#index)?.overlayer.remove(this.oldValue)

        const doc = this.renderer.getContents()[0].doc;

        if (this.tts && this.tts.doc === doc) return;
        
        this.tts = new TTS(doc, this.readElementsFormat, this.#smils, textWalker, (range) => {
            const obj = this.#getOverlayer(this.#index);
            if (obj) {
                const { overlayer } = obj;
                if (this.oldValue) {
                    overlayer.remove(this.oldValue);
                }
                const value = this.getCFI(this.#index, range);
                overlayer.add(value, range, Overlayer.highlight, { color: '#39c5bb' });
                this.oldValue = value;
            }
            this.renderer.scrollToAnchor(range);
        });
    }
    startMediaOverlay() {
        const { index } = this.renderer.getContents()[0]
        return this.mediaOverlay.start(index)
    }

    isLastSection() {
        return this.#index == this.#num_of_sections - 1
    }
}

customElements.define('foliate-view', View)
