const NS = {
    XML: 'http://www.w3.org/XML/1998/namespace',
    SSML: 'http://www.w3.org/2001/10/synthesis',
}

const blockTags = new Set([
    'article', 'aside', 'audio', 'blockquote', 'caption',
    'details', 'dialog', 'div', 'dl', 'dt', 'dd',
    'figure', 'footer', 'form', 'figcaption',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'li',
    'main', 'math', 'nav', 'ol', 'p', 'pre', 'section', 'tr',
])

const getLang = el => {
    const x = el.lang || el?.getAttributeNS?.(NS.XML, 'lang')
    return x ? x : el.parentElement ? getLang(el.parentElement) : null
}

function rangeIsEmpty(range) {
    return range.collapsed || range.toString().trim() === ''
}

const sentenseEndRegex = (lang) => {
    switch (lang) {
        case 'zh':
            return 
        case 'en':
            return /[.!?]["']?/g
        default:
            return /[.!?]["']?/g
    }
}

function checkNodeFunction(node, functionName) {
    if (!(node instanceof Node)) {
        return false;
    }
    return typeof node[functionName] === 'function';
}

function hasProperty(node, propertyName) {
    if (!(node instanceof Node)) {
        return false;
    }
    return propertyName in node;
}

function isChildOfMathML(node) {
    let currentNode = node;

    while(currentNode.nodeType === currentNode.TEXT_NODE) {
        currentNode = currentNode.parentNode;
    }
    
    let isAnn = false
    while (currentNode) {
        // For element nodes, check if it's a MathML element
        if (currentNode.nodeType === Node.ELEMENT_NODE) {
            if(currentNode.tagName.toLowerCase() == "annotation") {
                isAnn = true
            }
            if (currentNode.namespaceURI === "http://www.w3.org/1998/Math/MathML") {
                return isAnn ? false : true; // Found a MathML ancestor
            }
        }
        // Move to the next parent
        currentNode = currentNode.parentNode;
    }

    return false; // No MathML ancestor found
}


//async function checkMediaOverlay(id) {
//    return await window.flutter_inappwebview.callHandler("CheckMediaOverlay", id);
//}

function checkMediaOverlay(id, smils) {
    return smils ? smils.includes(id) : false
}


function isChildOfNodeWithMediaOverlay(node, smils) {
    let currentNode = node;

    while(currentNode.nodeType === currentNode.TEXT_NODE) {
        currentNode = currentNode.parentNode;
    }
        
    while (currentNode) {
        if (currentNode.nodeType === Node.ELEMENT_NODE) {
            if(currentNode.id != ""){
                const res = checkMediaOverlay(currentNode.id, smils);
                if(res == true) {
                    //console.log(currentNode.tagName, " ", currentNode.id, ": ", res)
                    return currentNode;
                }
            }
        }
        currentNode = currentNode.parentNode;
    }
    return null;
}

function isNodeWithMediaOverlay(currentNode, smils) {
    while(currentNode.nodeType === currentNode.TEXT_NODE) 
        return false;
        
    if (currentNode.nodeType === Node.ELEMENT_NODE) {
        if(currentNode.id != ""){
            return checkMediaOverlay(currentNode.id, smils);
        }
    }
    return false;
}

function setUpBlocks(doc, tts, smils) {
    //console.log("setUpBlocks:");
    const filter = {
        acceptNode: function(node) {
            if(isChildOfMathML(node)) return NodeFilter.FILTER_SKIP;

            if (node.nodeType === Node.TEXT_NODE) {
                return node.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                //if(node.textContent.trim().length > 0 ||
                //    isChildOfNodeWithMediaOverlay(node, smils) != null) {
                //    return NodeFilter.FILTER_ACCEPT
                //} else {
                //    return NodeFilter.FILTER_SKIP
                //}
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                //console.log(" -check ", node.outerHTML)
                if(node.tagName.toLowerCase() == "span" &&
                    (node.classList.contains("smr-format-info") || node.classList.contains("smr-text-info"))) {
                        var parent = node.getAttribute('parent-tag')
                        //console.log("parent-tag", parent)
                        switch(parent) {
                            case "heading":
                                return tts.readingHeading ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "img": case "svg":
                                return tts.readingImg ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "list":
                                return tts.readingList ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "link":
                                return tts.readingLink ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "font":
                                return tts.readingFont ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "table":
                                return tts.readingTable ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "note":
                                return tts.readingNote ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "footnote":
                                return tts.readingFootnote ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "page":
                                return tts.readingPageNumber ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                            case "math":
                                return NodeFilter.FILTER_ACCEPT
                        }
                        if(node.getAttribute("aria-label")) {
                            return node.getAttribute("aria-label").trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP
                        } else {
                            return NodeFilter.FILTER_SKIP
                        }
                } else if(node.textContent.trim() == "" && isNodeWithMediaOverlay(node, smils)){
                    //console.log("*** ", node.outerHTML);
                    return NodeFilter.FILTER_ACCEPT
                }
            }
            return NodeFilter.FILTER_SKIP;
        }
    };
    //const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, filter);
    
    const textNodes = [];
    let node;
    while (node = walker.nextNode()) {
        textNodes.push(node);
    }
    
    for (const textNode of textNodes) {
        let first = true;
        
        if(textNode.nodeType === textNode.TEXT_NODE ) {
            var text =  textNode.nodeValue ? textNode.nodeValue.trim() : "";

            var href = false;
            var e = textNode;
            while(e) {
                if(e.tagName && e.tagName.toLowerCase() == 'a') {
                    href = true
                    break
                }
                if(e.parentElement) {
                    e = e.parentElement
                } else {
                    break;
                }
            }
            
            
            const spanWithID = isChildOfNodeWithMediaOverlay(textNode, smils)
            if(spanWithID == null) {
                // Split text by sentences (basic regex for periods, question marks, exclamation marks)
                //const sentences = text.match(/[^.!?;]+[.!?;]+(?:\s|$)/g) || [text];
                const sentences = text.match(/[^.!?;\n]+(?:[.!?;\n]|$)/g) || [text];

                const parent = textNode.parentNode;
                //console.log(" -", textNode.parentNode.tagName);

                const fragment = doc.createDocumentFragment();

                for (const sentence of sentences) {
                    const subs = sentence.match(/[^,]+(?:[,]+\s*|\s+|$)/g) || [sentence];
                    
                    const pieces = [];
                    let i = 0;
                    let piece = '';
                    while(i < subs.length) {
                        if(piece.length + subs[i].length < 64) {
                            piece += ' ' + subs[i];
                        } else {
                            pieces.push(piece);
                            piece = subs[i];
                        }
                        i++;
                    }
                    pieces.push(piece);
                    
                    for (const piece of pieces) {
                        const span = doc.createElement('span');
                        span.textContent = piece.trim() + ' ';
                        span.className = 'tts';
                        span.className = 'tts-span';

                        if(first) {
                            span.setAttribute("parent-tag", parent.tagName)
                            first = false;
                        }
                        
                        if(!href) {
                            span.addEventListener('click-old', () => {
                                tts.moveTo(span)

                                const range = doc.createRange();
                                //range.selectNodeContents(span)
                                if (span.firstChild) {
                                    const firstChild = span.firstChild;
                                    const lastChild = span.lastChild;
                                    range.setStart(firstChild, 0);
                                    const endOffset = lastChild.nodeType === Node.TEXT_NODE ?
                                        lastChild.length :
                                        lastChild.childNodes.length;
                                    range.setEnd(lastChild, endOffset);
                                } else {
                                    range.setStart(span, 0);
                                    range.setEnd(span, 0);
                                }

                                const selection = doc.defaultView.getSelection();
                                selection.removeAllRanges();
                                selection.addRange(range);

                                const contextMenuEvent = new CustomEvent('contextmenu');
                                doc.dispatchEvent(contextMenuEvent);
                            });
                        }
                        fragment.appendChild(span);
                    };
                };
                parent.replaceChild(fragment, textNode);
            } else {
                spanWithID.classList.add("tts")
                spanWithID.classList.add("span-with-id")
                spanWithID.addEventListener('click-old', () => {
                    tts.moveTo(spanWithID)

                    const range = doc.createRange();
                    ////range.selectNodeContents(spanWithID)
                    if (spanWithID.firstChild) {
                        const firstChild = spanWithID.firstChild;
                        const lastChild = spanWithID.lastChild;
                        range.setStart(firstChild, 0);
                        const endOffset = lastChild.nodeType === Node.TEXT_NODE ?
                            lastChild.length :
                            lastChild.childNodes.length;
                        range.setEnd(lastChild, endOffset);
                    } else {
                        range.setStart(span, 0);
                        range.setEnd(span, 0);
                    }

                    const selection = doc.defaultView.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(range);

                    const contextMenuEvent = new CustomEvent('contextmenu');
                    doc.dispatchEvent(contextMenuEvent);
                });
            }
        } else {
            textNode.classList.add("tts")
            const spanWithID = isChildOfNodeWithMediaOverlay(textNode, smils)
            if(spanWithID != null) {
                spanWithID.classList.add("span-with-id")
            }
        }
    };
    //console.log("FINISHED!");
}
function* getBlocks(doc, tts, no_text) {
    //console.log("getBlocks");
    let spans = doc.querySelectorAll('.tts, .tts-span');
    //console.log("spans: ", spans.length);

    let lastRange = null;
    if(spans.length == 0){
        const span = doc.createElement('span');
        span.setAttribute("extra-text", no_text)
        span.classList.add('smr-format-info');
        span.textContent = ''
        span.className = 'tts-span';
        doc.body.appendChild(span);

        lastRange = doc.createRange();
        lastRange.selectNodeContents(span)

        yield lastRange
    } else {
        for(const span of spans) {
            //console.log("- ", span.outerHTML)
            if(!span.classList.contains("tts-span") || span.textContent.trim() != "") {
                lastRange = doc.createRange();
                lastRange.selectNode(span);
                yield lastRange
            }
        }
    }
}

class ListIterator {
    #arr = []
    #iter
    #index = -1
    #f
    constructor(iter, f = x => x) {
        this.#iter = iter
        this.#f = f
    }
    current() {
        if (!this.#arr[this.#index]) {
            this.first();
        }
        if (this.#arr[this.#index]) {
            return this.#f(this.#arr[this.#index])
        } 
    }
    first() {
        const newIndex = 0
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    last() {
        for (const value of this.#iter) this.#arr.push(value)
        const newIndex = this.#arr.length - 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    prev() {
        const newIndex = this.#index - 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    next() {
        const newIndex = this.#index + 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr[newIndex]) {
                this.#index = newIndex
                return this.#f(this.#arr[newIndex])
            }
        }
    }
    prepare() {
        //console.log("prepare: ", this.#index)
        const newIndex = this.#index + 1
        if (this.#arr[newIndex]) return this.#f(this.#arr[newIndex])
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr[newIndex]) return this.#f(this.#arr[newIndex])
        }
    }
    find(f) {
        const index = this.#arr.findIndex(x => f(x))
        if (index > -1) {
            this.#index = index
            return this.#f(this.#arr[index])
        }
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (f(value)) {
                this.#index = this.#arr.length - 1
                return this.#f(value)
            }
        }
    }
    index() {
        return this.#index
    }
    range() {
        return this.#arr[this.#index]
    }
}

function checkRangeTagName(doc, range, xtags) {
    //console.log("checkRangeTagName: ", xtags);
    const fragment = range.cloneContents();
    
    const elements = fragment.querySelectorAll('*');
    const tagNames = new Set();

    for(const element of elements) {
        if(element.getAttribute("parent-tag")) {
            //console.log(" parent: ", element.getAttribute("parent-tag"));
            tagNames.add(element.getAttribute("parent-tag").toLowerCase());
        }
    }
    //console.log(Array.from(tagNames))
    const tags = xtags.split(' ');

    for(const tag of tagNames)
        if(tags.includes(tag)) return true

    return false;
}

function getRangeTextContent(range) {
    //console.log("getRangeTextContent")
    let textContent = '';
    const fragment = range.cloneContents(); // Clone contents to avoid modifying the live DOM

    /**
     * Recursive helper function to traverse nodes and extract text.
     * @param {Node} node The current node to process.
     */
    function traverseNodes(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            textContent += node.textContent;
        } else if (node.nodeType === Node.ELEMENT_NODE) {
            if(node.classList.contains("smr-format-info")) {
                const text = node.getAttribute("extra-text")
                textContent += '[format]' + text;
            } else if(node.classList.contains("smr-text-info")) {
                const text = node.getAttribute("extra-text")
                textContent += text;
            } else {
                const ariaLabel = node.getAttribute('aria-label');
                //console.log("ariaLabel: ", ariaLabel)
                if (ariaLabel) {
                    textContent += ariaLabel;
                } else {
                    // Handle elements that might represent spacing or have children
                    if (node.nodeName === 'BR') {
                        textContent += '\n'; // Add newline for <br>
                    } else if (['P', 'DIV', 'LI', 'BLOCKQUOTE'].includes(node.nodeName)) {
                        // Add a space or newline around block-level elements for better readability
                        // This helps in preserving the visual structure if the text is extracted
                        if (textContent.length > 0 && !textContent.endsWith(' ') && !textContent.endsWith('\n')) {
                            textContent += ' '; // Add space before block content
                        }
                        for (let i = 0; i < node.childNodes.length; i++) {
                        traverseNodes(node.childNodes[i]);
                        }
                        if (textContent.length > 0 && !textContent.endsWith('\n')) {
                            textContent += '\n'; // Add newline after block content
                        }
                    } else if (node.childNodes.length === 0 && node.textContent.trim() === '') {
                        // For truly "blank" elements (no children, no text), consider adding a space
                        // if it visually separates other content. This is a heuristic.
                        textContent += ' ';
                    } else {
                        // For other elements, recursively process their children
                        for (let i = 0; i < node.childNodes.length; i++) {
                        traverseNodes(node.childNodes[i]);
                        }
                    }
                }
            }
            if(node.classList.contains("span-with-id")) {
                textContent = '[id=' + node.id + ']' + textContent;
            }
        }
        // Ignore other node types (comments, processing instructions, etc.)
    }

    // Start traversal from the cloned fragment
    for (let i = 0; i < fragment.childNodes.length; i++) {
        traverseNodes(fragment.childNodes[i]);
    }

    // Clean up extra spaces that might accumulate, especially at the beginning or end
    //console.log(" ", textContent)
    return textContent.replace(/\s+/g, ' ').trim();
}

export class TTS {
    #index
    #list
    #lastMark
    #disableScroll = false
    
    readingFormat = true
    readingHeading = true
    readingImg = true
    readingList = true
    readingLink = true
    readingTable = true
    readingNote = true
    readingFont = true
    readingFootnote = true
    readingPageNumber = true

    constructor(doc, readingFormat, smils, textWalker, highlight) {        
        this.doc = doc
        this.#setReadingFormat(readingFormat)
        this.highlight = highlight
        
        setUpBlocks(doc, this, smils);
        this.#list = new ListIterator(getBlocks(doc, this, readingFormat['section_no_text']), range => {
                return [getRangeTextContent(range), range]
        });        
    }


    #setReadingFormat(readElementsFormat) {
        //console.log("setReadingFormat");
        const {main, heading, img, list, link, table, note, font, footnote, page } = readElementsFormat

        if(main) {
            this.readingFormat = true
            this.readingHeading = heading
            this.readingImg = img
            this.readingList = list
            this.readingLink = link
            this.readingTable = table
            this.readingNote = note
            this.readingFont = font
            this.readingFootnote = footnote
            this.readingPageNumber = page
        } else {
            this.readingFormat = false
            this.readingHeading = false
            this.readingImg = false
            this.readingList = false
            this.readingLink = false
            this.readingTable = false
            this.readingNote = false
            this.readingFont = false
            this.readingFootnote = false
            this.readingPageNumber = false
        }
    }
    #getText(text, getNode) {
        if (!text) return ''
        if (!getNode) return text
        const tempElement = doc.createElement('div')
        tempElement.innerHTML = text
        let node = getNode(tempElement)?.previousSibling
        while (node) {
            const next = node.previousSibling ?? node.parentNode?.previousSibling
            node.parentNode.removeChild(node)
            node = next
        }
        return tempElement.textContent
    }

    start() {
        //console.log("start");
        this.#lastMark = null
        const [text, range] = this.#list.first() ?? []
        if (!text) {
            //console.log("*1");
            return this.next()
        }
        
        this.#disableScroll = true
        this.highlight(range.cloneRange())
        this.#disableScroll = false
        //console.log("*2");
        return this.#getText(text)
    }

    end() {
        //console.log("end");
        this.#lastMark = null
        const [text, range] = this.#list.last() ?? []
        if (!text) return this.next()
        
        this.#disableScroll = true
        this.highlight(range.cloneRange())
        this.#disableScroll = false
        
        return this.#getText(text)
    }

    resume() {
        //console.log("resume");
        const [text] = this.#list.current() ?? []
        if (!text) return this.next()
        return this.#getText(text)
    }

    prev(paused) {
        //console.log("prev");
        this.#lastMark = null
        let i = this.#list.index()
        const [text, range] = this.#list.prev() ?? []
        if (paused && range) {
            this.#disableScroll = true
            this.highlight(range.cloneRange())
            this.#disableScroll = false
        }
        //console.log("prev ", i, " -> ", this.#list.index());
        return this.#getText(text)
    }

    next(paused) {
        //console.log("next");
        this.#lastMark = null
        const [text, range] = this.#list.next() ?? []
        //console.log("-text: ", text);
        if (paused && range) {
            this.#disableScroll = true
            this.highlight(range.cloneRange())
            this.#disableScroll = false
        }
        return this.#getText(text)
    }
    nextTags(tags) {
        //console.log("nextTags");
        this.#lastMark = null
        while(true) {
            const [text, range] = this.#list.next() ?? []
            if (range) {
                if(checkRangeTagName(this.doc, range, tags)) {
                    this.#disableScroll = true
                    this.highlight(range.cloneRange())
                    this.#disableScroll = false
                    break;
                }
            } else break;
        }
    }
    prevTags(tags) {
        //console.log("prevTags");
        this.#lastMark = null
        while(true) {
            const [text, range] = this.#list.prev() ?? []
            if (range) {
                if(checkRangeTagName(this.doc, range, tags)) {
                    this.#disableScroll = true
                    this.highlight(range.cloneRange())
                    this.#disableScroll = false
                    break;
                }
            } else break;
        }
    }
    // get next text without moving the iterator
    prepare() {
        //console.log("prepare");
        const [text] = this.#list.prepare() ?? []
        return this.#getText(text)
    }

    from(range) {
        if(this.#disableScroll) return
        //console.log("from");
        this.#lastMark = null

        const [ctext, crange] = this.#list.current() ?? []

        if(crange) {
            //const doc1 = crange.commonAncestorContainer.ownerDocument;
            //const doc2 = range.commonAncestorContainer.ownerDocument;
            //if(doc1 != doc2) return this.#getText(ctext)

            if(range.compareBoundaryPoints(Range.START_TO_START, crange) <= 0 &&
                range.compareBoundaryPoints(Range.END_TO_END, crange) >= 0)
                    return this.#getText(ctext)
        }

        const [text, newRange] = this.#list.find(range_ =>
            range.compareBoundaryPoints(Range.END_TO_START, range_) <= 0)
        if (newRange) {
            this.#disableScroll = true
            this.highlight(newRange.cloneRange())
            this.#disableScroll = false
        }
        return this.#getText(text)
    }

    // select current range
    select() {
        const [text, range] = this.#list.current() ?? []
        if (!text) return        
              
        if(range) {
            try {
                const selection = this.doc.defaultView.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                //const contextMenuEvent = new CustomEvent('contextmenu');
                //this.doc.dispatchEvent(contextMenuEvent);
            } catch (error) {
                console.error("An error occurred:", error.message);
            }
        }
    }
    
    moveTo(span) {
        //console.log("moveTo");
        let range = this.doc.createRange();
        range.selectNode(span)

        this.#lastMark = null
        const [text, newRange] = this.#list.find(range_ =>
            range.compareBoundaryPoints(Range.START_TO_START, range_) == 0 &&
            range.compareBoundaryPoints(Range.END_TO_END, range_) == 0)
        if (newRange) {
            this.#disableScroll = true
            this.highlight(newRange.cloneRange())
            this.#disableScroll = false
        }
        return this.#getText(text)

    }
}