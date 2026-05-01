function logEvent(message) {
    console.log(message)
}

export function createDynamicDialog(options) {
    // Default options
    const defaultOptions = {
        title: 'Dynamic Dialog',
        content: 'This is a dynamically generated dialog.',
        showDropdown: false,
        dropdownItems: [],
        leftCmd: '',
        rightCmd: '',
        upCmd: '',
        downCmd: '',
        applyButtonText: 'Apply',
        closeButtonText: 'Close',
        onApply: null, // Callback function for 'Apply'
        onClose: null,  // Callback function for 'Close'
        onKeyPress: null // Callback function for KeyPress
    };

    // Merge provided options with defaults
    const settings = { ...defaultOptions, ...options };

    // Create the <dialog> element
    const dialog = document.createElement('dialog');
    dialog.id = "mathml-navigator";
    dialog.className = 'dynamic-dialog'; // Add a class for styling

    // --- Create Dialog Content ---
    const dialogContentDiv = document.createElement('div');
    dialogContentDiv.className = 'dialog-inner-content';

    const titleElement = document.createElement('h3');
    titleElement.textContent = settings.title;
    dialogContentDiv.appendChild(titleElement);

    const contentParagraph = document.createElement('p');
    contentParagraph.textContent = settings.content;
    dialogContentDiv.appendChild(contentParagraph);

    let dropdownSelect = null;
    if (settings.showDropdown) {
        const dropdownLabel = document.createElement('label');
        dropdownLabel.textContent = 'Select an option:';
        dropdownLabel.htmlFor = 'dynamic-dropdown-' + Math.random().toString(36).substring(7); // Unique ID
        dialogContentDiv.appendChild(dropdownLabel);

        dropdownSelect = document.createElement('select');
        dropdownSelect.id = dropdownLabel.htmlFor; // Link label to select
        dropdownSelect.className = 'dynamic-dropdown';

        settings.dropdownItems.forEach(item => {
            const option = document.createElement('option');
            option.value = item;
            option.textContent = item;
            dropdownSelect.appendChild(option);
        });
        dialogContentDiv.appendChild(dropdownSelect);
    }

    const resultLabel = document.createElement('p');
    resultLabel.className = 'dialog-result-label';
    resultLabel.setAttribute("aria-live", "polite");
    resultLabel.setAttribute("aria-atomic", "true");
    dialogContentDiv.appendChild(resultLabel);

    dialog.appendChild(dialogContentDiv);

    // --- Create Buttons ---
    const buttonContainer = document.createElement('div');
    buttonContainer.className = 'dialog-buttons';

    const closeButton = document.createElement('button');
    closeButton.textContent = settings.closeButtonText;
    closeButton.className = 'dialog-button dialog-close-button';
    buttonContainer.appendChild(closeButton);

    const applyButton = document.createElement('button');
    applyButton.textContent = settings.applyButtonText;
    applyButton.className = 'dialog-button dialog-apply-button';
    buttonContainer.appendChild(applyButton);

    dialog.appendChild(buttonContainer);

    // --- Event Listeners ---

    closeButton.addEventListener('click', () => {
        dialog.close();
        if (settings.onClose) {
            settings.onClose();
        }
        dialog.remove(); // Remove dialog from DOM after closing
    });

    applyButton.addEventListener('click', () => {
        let selectedValue = null;
        if (dropdownSelect) {
            selectedValue = dropdownSelect.value;
        }

        if (settings.onApply) {
            settings.onApply(selectedValue, resultLabel); // Pass resultLabel to callback
        }
    });

    // Close on backdrop click
    dialog.addEventListener('click', (event) => {
        if (event.target === dialog) {
            dialog.close();
            if (settings.onClose) {
                settings.onClose();
            }
            dialog.remove();
        }
    });

    dropdownSelect.addEventListener('change', (event) => {
        const selectedValue = event.target.value;
        //const selectedText = event.target.options[event.target.selectedIndex].textContent;
        settings.onApply(selectedValue, resultLabel);
    });

    let startX = 0;
    let startY = 0;
    const threshold = 50;

    dialog.addEventListener('touchstart', (e) => {
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        //console.log('Touch started...');
    });

    dialog.addEventListener('touchend', (e) => {
        const endX = e.changedTouches[0].clientX;
        const endY = e.changedTouches[0].clientY;

        const deltaX = endX - startX;
        const deltaY = endY - startY;

        let detectedGesture = 'No clear swipe';

        if (Math.abs(deltaX) > Math.abs(deltaY)) { // Horizontal swipe
            if (Math.abs(deltaX) > threshold) {
                detectedGesture = deltaX > 0 ? 'Swipe Right!' : 'Swipe Left!';
                if(deltaX > 0) {
                    if(settings.rightCmd.length > 0) {
                        settings.onApply(settings.rightCmd, resultLabel);
                    }
                } else {
                    if(settings.leftCmd.length > 0) {
                        settings.onApply(settings.leftCmd, resultLabel);
                    }
                }
            }
        } else { // Vertical swipe
            if (Math.abs(deltaY) > threshold) {
                detectedGesture = deltaY > 0 ? 'Swipe Down!' : 'Swipe Up!';
                if(deltaY > 0) {
                    if(settings.downCmd.length > 0) {
                        settings.onApply(settings.downCmd, resultLabel);
                    }
                } else {
                    if(settings.upCmd.length > 0) {
                        settings.onApply(settings.upCmd, resultLabel);
                    }
                }
            }
        }
        //console.log(detectedGesture);
        // Reset for next gesture
        startX = 0;
        startY = 0;
    });

    
    dialog.addEventListener('keydown', (event) => {
        const key = event.key; // 'a', 'A', 'Shift', 'Control', 'Enter', ' ' (space)
        const code = event.code; // 'KeyA', 'ShiftLeft', 'Space'
        //const which = event.which || event.keyCode; // Deprecated, but often seen for older compatibility        
        //function navigate_by_keypress(key, shift_key, control_key, alt_key, meta_key) 

        let modifiers = [];
        if (event.shiftKey) {
            modifiers.push('Shift');
        }
        if (event.ctrlKey) {
            modifiers.push('Control');
        }
        if (event.altKey) {
            modifiers.push('Alt');
        }
        if (event.metaKey) {
            modifiers.push('Meta (Command/Windows)');
        }
        const modifierString = modifiers.length > 0 ? ` (Modifiers: ${modifiers.join(', ')})` : '';
        logEvent(`KEYDOWN: Key: "${key}" (Code: "${code}")${modifierString}`);
        
        settings.onKeyPress(event.code, event.shiftKey, event.ctrlKey, event.altKey, event.metaKey, resultLabel)

        event.stopPropagation();
        event.preventDefault();
    });

    dialog.addEventListener('keypress', function(event) {
        //console.log(`Input Field (keypress): Key "${event.key}" pressed.`);
        event.stopPropagation();
        event.preventDefault();
    });

    // Append the dialog to the body (or a specific container)
    document.body.appendChild(dialog);

    // Show the dialog
    dialog.showModal();

    return dialog; // Return the dialog element for further manipulation if needed
}

// --- Example Usage ---

// Add some basic dynamic CSS for the dialog
addDynamicStyles(`
    .dynamic-dialog {
        border: 1px solid #007bff;
        border-radius: 8px;
        padding: 25px;
        box-shadow: 0 6px 12px rgba(0, 0, 0, 0.2);
        background-color: #fff;
        max-width: 500px;
        width: 90%;
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    }

    .dynamic-dialog::backdrop {
        background-color: rgba(0, 0, 0, 0.6);
    }

    .dynamic-dialog h3 {
        color: #007bff;
        margin-top: 0;
        margin-bottom: 15px;
    }

    .dialog-inner-content p {
        margin-bottom: 15px;
        line-height: 1.6;
    }

    .dynamic-dropdown {
        width: 100%;
        padding: 8px;
        border: 1px solid #ccc;
        border-radius: 4px;
        margin-top: 5px;
        margin-bottom: 15px;
    }

    .dialog-buttons {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        margin-top: 20px;
    }

    .dialog-button {
        padding: 10px 20px;
        border: none;
        border-radius: 5px;
        cursor: pointer;
        font-size: 1rem;
        transition: background-color 0.2s ease;
    }

    .dialog-close-button {
        background-color: #6c757d;
        color: white;
    }

    .dialog-close-button:hover {
        background-color: #5a6268;
    }

    .dialog-apply-button {
        background-color: #28a745;
        color: white;
    }

    .dialog-apply-button:hover {
        background-color: #218838;
    }

    .dialog-result-label {
        margin-top: 15px;
        font-weight: bold;
        text-align: center;
        color: #007bff; /* Default blue for info */
    }
`);

// Helper function for adding styles (from section 1c)
function addDynamicStyles(rules) {
    const styleTag = document.createElement('style');
    styleTag.textContent = rules;
    document.head.appendChild(styleTag);
}