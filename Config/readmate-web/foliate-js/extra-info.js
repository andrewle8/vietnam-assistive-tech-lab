function checkMediaOverlay(id, smils) {
    return smils ? smils.includes(id) : false
}

function isChildOfNodeWithMediaOverlay(node, smils) {
    //console.log("isChildOfNodeWithMediaOverlay");
    let currentNode = node;
    //console.log("- check smil:", currentNode.outerHTML)

    while(currentNode.nodeType === currentNode.TEXT_NODE) {
        currentNode = currentNode.parentNode;
    }
        
    while (currentNode) {
        if (currentNode.nodeType === Node.ELEMENT_NODE) {
            //console.log("- check smil:", currentNode.outerHTML)
            if(currentNode.id != ""){
                const res = checkMediaOverlay(currentNode.id, smils);
                if(res == true) {
                    //console.log(" -> YES");
                    return currentNode;
                }
            }
        }
        currentNode = currentNode.parentNode;
    }
    //console.log(" -> NO");
    return null;
}

function addInfoSpan(doc, node, info, before, parent) {
    if(!doc || !info || info == '') return

    const span = doc.createElement('span')
    span.setAttribute("parent-tag", parent)
    span.setAttribute("extra-text", info)
    span.classList.add('smr-format-info');
    span.textContent = ''
    span.style.color = 'red';
    span.style.fontWeight = 'bold';
    span.style.fontSize = '0.5rem';

    if(before) {
        if (node.firstChild) {
            node.insertBefore(span, node.firstChild);
        } else {
            node.appendChild(span);
        }
    } else {
        node.appendChild(span);
    }
}

function addTextSpan(doc, node, info, before, parent) {
    if(!doc || !info || info == '') return

    const span = doc.createElement('span')
    span.setAttribute("parent-tag", parent)
    span.setAttribute("extra-text", info)
    span.classList.add('smr-text-info');
    span.textContent = ''
    span.style.color = 'red';
    span.style.fontWeight = 'bold';
    span.style.fontSize = '0.5rem';

    if(before) {
        if (node.firstChild) {
            node.insertBefore(span, node.firstChild);
        } else {
            node.appendChild(span);
        }
    } else {
        node.appendChild(span);
    }
}

function addImgsInfo(doc, smils, elementsText) {
    //console.log('addImgsInfo');
    //console.log(doc.body.innerHTML);
    for (const img of doc.querySelectorAll('img')) {
        if(isChildOfNodeWithMediaOverlay(img, smils) == null) {
            if(img.alt && img.alt.trim() != '') {
                addTextSpan(doc, img, img.alt, true, "img")
                addInfoSpan(doc, img, "Graphic ", true, "img")
            } else if(img.src && img.src.trim() != '') {
                addInfoSpan(doc, img, elementsText["element_graphic"] + " " + img.src, true, "img")
            }
        }
    }
    
    for (const svg of doc.querySelectorAll('svg')) {
        if(isChildOfNodeWithMediaOverlay(svg, smils) == null) {
            addInfoSpan(doc, svg, elementsText["element_graphic"] + " svg", true, "svg")
        }
    }
}
function addHrefsInfo(doc, book, section, smils, elementsText) {
    for (const a of doc.querySelectorAll('a[href]')) {
        if(isChildOfNodeWithMediaOverlay(a, smils) == null) {
            const href_ = a.getAttribute('href')
            const href = section?.resolveHref?.(href_) ?? href_
            
            if (book?.isExternal?.(href)) {
                var type = elementsText["element_link"]
                if(href.startsWith("mailto")) {
                    type = elementsText["element_email_link"]
                } else if(href.startsWith("ftp")) {
                    type = elementsText["element_ftp_link"]
                }
                addInfoSpan(doc, a, type, true, "link")
            } else {
                var noteref = a.getAttribute("role")
                if(noteref && noteref == "doc-noteref") {
                    addInfoSpan(doc, a, "Footnote", true, "link")
                } else {
                    addInfoSpan(doc, a, elementsText["element_same_book_link"], true, "link")
                }
            }
        }
    }
}

function addFootnotesInfo(doc, smils, elementsText) {
    for (const a of doc.querySelectorAll('[role="doc-footnote"]')) {
        if(isChildOfNodeWithMediaOverlay(a, smils) == null) {
            addInfoSpan(doc, a, elementsText["element_footnote"], true, "footnote")
        }
    }
}
function addHeadingsInfo(doc, smils, elementsText) {
    for (const h of doc.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
        if(isChildOfNodeWithMediaOverlay(h, smils) == null) {
            var info = ''
            switch(h.tagName) {
                case "h1":
                    info = "1"
                    break;
                case "h2":
                    info = "2"
                    break;
                case "h3":
                    info = "3"
                    break;
                case "h4":
                    info = "4"
                    break;
                case "h5":
                    info = "5"
                    break;
                case "h6":
                    info = "6"
                    break;
            }
            info = elementsText["element_heading"].replace("[level]", info)
            addInfoSpan(doc, h, info, true, "heading")
        }
    }
}

// number of item <li> in <ul> or <ol> node
function getListElementsNum(node) {
    if(!node) return -1
    if(!node.tagName || (node.tagName.toLowerCase() != "ul" && node.tagName.toLowerCase() != "ol"))
        return -1

    const lis = Array.from(node.children).filter(child => child.nodeName.toLowerCase() === 'li');
    return lis.length
}
// get <ol>, <ul> parent element of the list
function getParentList(node) {
    if(!node) return null
    
    var parent = node.parentNode;
    
    while(parent && parent.tagName != "ol" && parent.tagName != "ul") {
        parent = parent.parentNode;
    }

    return parent
}
// Get level of nested list (node is the list)
function getListLevel(node) {
    if(!node) return 0
    
    var parent = getParentList(node)
    return getListLevel(parent) + 1
}

function addUnorderedListsInfo(doc, smils, elementsText) {
    for (const ul of doc.querySelectorAll('ul')) {
        if(isChildOfNodeWithMediaOverlay(ul, smils) == null) {
            var cnt = getListElementsNum(ul)
            
            if(cnt > 0) {
                var level = getListLevel(ul)
                
                if(level == 1) {
                    var txt = elementsText["element_list"].replace("[count]", cnt.toString())
                    addInfoSpan(doc, ul, txt, true, "list")
                    addInfoSpan(doc, ul, elementsText["element_list_end"], false, "list")
                } else {
                    var txt = elementsText["element_list_level"].replace("[count]", cnt.toString()).replace("[level]", level.toString())
                    addInfoSpan(doc, ul, txt, true, "list")
                    txt = elementsText["element_list_end_level"].replace("[level]", level.toString())
                    addInfoSpan(doc, ul, txt, false, "list")
                }
                
                const lis = Array.from(ul.children).filter(child => child.nodeName.toLowerCase() === 'li');
                lis.forEach((li, index) => {
                        addInfoSpan(doc, li, "bullet", true, "list")
                });
            }
        }
    }
}

function convertIndexByType(index, type) {
    switch(type) {
        case "1":
            return (index + 1).toString()
        case "A":
            return String.fromCharCode(65 + index);
        case "a":
            return String.fromCharCode(97 + index);
        case 'I': case 'i':
            const romanNumerals = [
                { value: 1000, symbol: 'M' },
                { value: 900, symbol: 'CM' },
                { value: 500, symbol: 'D' },
                { value: 400, symbol: 'CD' },
                { value: 100, symbol: 'C' },
                { value: 90, symbol: 'XC' },
                { value: 50, symbol: 'L' },
                { value: 40, symbol: 'XL' },
                { value: 10, symbol: 'X' },
                { value: 9, symbol: 'IX' },
                { value: 5, symbol: 'V' },
                { value: 4, symbol: 'IV' },
                { value: 1, symbol: 'I' }
            ];
            
            index++
            let result = ''
            for (let i = 0; i < romanNumerals.length; i++) {
                const { value, symbol } = romanNumerals[i];

                // While the number is greater than or equal to the current Roman numeral value
                while (index >= value) {
                result += symbol; // Append the Roman numeral symbol
                index -= value;      // Subtract the value from the number
                }
            }
            return type == 'i' ? result.toLowerCase() : result
        default:
            return "bullet"
    }
}

function addOrderedListsInfo(doc, smils, elementsText) {
    for (const ol of doc.querySelectorAll('ol')) {
        if(isChildOfNodeWithMediaOverlay(ol, smils) == null) {
            var cnt = getListElementsNum(ol)
            
            if(cnt > 0) {
                var level = getListLevel(ol)
                var type = ol.getAttribute("type")
                
                if(level == 1) {
                    var txt = elementsText["element_list"].replace("[count]", cnt.toString())
                    addInfoSpan(doc, ol, txt, true, "list")
                    addInfoSpan(doc, ol, elementsText["element_list_end"], false, "list")
                } else {
                    var txt = elementsText["element_list_level"].replace("[count]", cnt.toString()).replace("[level]", level.toString())
                    addInfoSpan(doc, ol, txt, true, "list")
                    txt = elementsText["element_list_end_level"].replace("[level]", level.toString())
                    addInfoSpan(doc, ol, txt, false, "list")
                }
                
                const lis = Array.from(ol.children).filter(child => child.nodeName.toLowerCase() === 'li');
                lis.forEach((li, index) => {
                    addInfoSpan(doc, li, convertIndexByType(index, type), true, "list")
                });
            }
        }
    }
}
function getTableColsNum(tableNode) {
    if (!tableNode || tableNode.tagName.toLowerCase() !== 'table') {
        return 0;
    }

    let maxCols = 0;

    const allRows = tableNode.rows;

    if (allRows.length === 0) {
        return 0; 
    }

    const rowsToCheck = Array.from(allRows).slice(0, Math.min(allRows.length, 5));

    rowsToCheck.forEach(row => {
    let currentRowCols = 0;
    // Iterate through all cells (th and td) in the current row
    const cells = row.querySelectorAll('th, td');

    cells.forEach(cell => {
        const colspan = parseInt(cell.getAttribute('colspan') || '1', 10);
        currentRowCols += colspan;
    });

    if (currentRowCols > maxCols) {
        maxCols = currentRowCols;
    }
    });

    return maxCols;
}

function getTableRowsNum(table) {
    return !table ? 0 : table.rows.length;
}

function addTablesInfo(doc, smils, elementsText) {
    for (const t of doc.querySelectorAll('table')) {
        if(isChildOfNodeWithMediaOverlay(t, smils) == null) {
            var cols = getTableColsNum(t)
            var rows = getTableRowsNum(t)
            
            if(cols != 0 && rows != 0) {
                var txt = elementsText["element_table"].replace("[columns]", cols.toString()).replace("[rows]", rows.toString())
                addInfoSpan(doc, t, txt, true, "table")
                addInfoSpan(doc, t, elementsText["element_table_end"], false, "table")
            }
        }
    }
}

function addFontFormatInfo(doc, smils, elementsText) {
    for (const f of doc.querySelectorAll('u, i, em, b, strong')) {
        if(isChildOfNodeWithMediaOverlay(f, smils) == null) {
            var txtStart = ''
            var txtEnd = ''
            switch(f.tagName.toLowerCase()) {
                case "u":
                    txtStart = elementsText["element_underline_start"]
                    txtEnd = elementsText["element_underline_end"]
                    break;
                case "i": case "em":
                    txtStart = elementsText["element_italic_start"]
                    txtEnd = elementsText["element_italic_end"]
                    break;
                case "b": case "strong":
                    txtStart = elementsText["element_bold_start"]
                    txtEnd = elementsText["element_bold_end"]
                    break;
            }
            if(txtStart != '') {
                addInfoSpan(doc, f, txtStart, true, "font")
                addInfoSpan(doc, f, txtEnd, false, "font")
            }
        }
    }
}
function addPageNumberInfo(doc, elementsText) {
    //console.log('addPageNumberInfo BEFORE:');
    //console.log(doc.body.innerHTML.substring(300));
    var pagebreaks = doc.querySelectorAll('[role="doc-pagebreak"]');
    pagebreaks.forEach(p => {
        let num = p.getAttribute("aria-label")
        num = num.replace(/page/gi, elementsText['element_page']);
        addInfoSpan(doc, p, num, true, 'page')
    });
    //console.log('AFTER');
    //console.log(doc.body.innerHTML.substring(300));
}

export function addExtraInfo(doc, book, section, smils, elementsText) {
    //console.log("addExtraInfo " + elementsText)
    addImgsInfo(doc, smils, elementsText)
    addHrefsInfo(doc, book, section, smils, elementsText)
    addHeadingsInfo(doc, smils, elementsText)
    addOrderedListsInfo(doc, smils, elementsText)
    addUnorderedListsInfo(doc, smils, elementsText)
    addTablesInfo(doc, smils, elementsText)
    addFontFormatInfo(doc, smils, elementsText)
    addFootnotesInfo(doc, smils, elementsText)
    addPageNumberInfo(doc, elementsText)
}
function getAllNodesInRange(doc, range) {
    const nodes = [];
    const startContainer = range.startContainer;
    const endContainer = range.endContainer;
    const commonAncestor = range.commonAncestorContainer;

    // Helper function to collect all nodes between two nodes
    function collectNodesBetween(startNode, endNode, ancestor) {
        let currentNode = startNode;
        while (currentNode && currentNode !== endNode) {
            nodes.push(currentNode);
            currentNode = getNextNode(currentNode, ancestor);
        }
        if (currentNode === endNode) {
            nodes.push(endNode);
        }
    }

    // Helper function to get the next node in tree traversal
    function getNextNode(node, ancestor) {
        if (node.firstChild) {
            return node.firstChild;
        }
        while (node && !node.nextSibling && node !== ancestor) {
            node = node.parentNode;
        }
        return node ? node.nextSibling : null;
    }

    // If start and end containers are the same
    if (startContainer === endContainer) {
        if (startContainer.nodeType === Node.TEXT_NODE) {
            nodes.push(startContainer);
        } else {
            // For element nodes, get all child nodes that intersect with the range
            let currentNode = startContainer.firstChild;
            while (currentNode) {
                const nodeRange = doc.createRange();
                nodeRange.selectNodeContents(currentNode);
                if (range.intersectsNode(currentNode)) {
                    nodes.push(currentNode);
                }
                currentNode = currentNode.nextSibling;
            }
        }
        return nodes;
    }

    // Handle different containers
    // Add start container if it's a text node and partially selected
    if (startContainer.nodeType === Node.TEXT_NODE && range.startOffset < startContainer.length) {
        nodes.push(startContainer);
    }

    // Get all nodes between start and end containers
    let currentNode = startContainer;
    if (startContainer.nodeType !== Node.TEXT_NODE) {
        currentNode = startContainer.childNodes[range.startOffset] || getNextNode(startContainer, commonAncestor);
    }

    collectNodesBetween(currentNode, endContainer, commonAncestor);

    // Handle end container if it's a text node and partially selected
    if (endContainer.nodeType === Node.TEXT_NODE && range.endOffset > 0) {
        if (!nodes.includes(endContainer)) {
            nodes.push(endContainer);
        }
    }

    return nodes.filter(node => {
        // Filter out nodes that don't intersect with the range
        const nodeRange = doc.createRange();
        nodeRange.selectNodeContents(node);
        return range.intersectsNode(node);
    });
}
