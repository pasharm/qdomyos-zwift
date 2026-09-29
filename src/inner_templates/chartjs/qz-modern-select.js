// Modern look of the app: drop-down lists of the web pages as a menu of the page itself.
// Android draws the list of a <select> as a system dialog in the theme of the activity - a
// white full-screen list, whatever the page looks like. Under html.modern the selects take no
// taps (qz-modern.css); a tap on one opens this menu under it in the colours of the page, like
// the combo boxes of the QML pages. The choice goes into the select with a change event, so
// the page code does not change. The classic look keeps the system list.
(function () {
    'use strict';

    var backdrop = null;

    function close() {
        if (backdrop) {
            backdrop.remove();
            backdrop = null;
        }
    }

    // The select under the point: it takes no taps itself, so the event lands on its parent
    function selectAt(x, y) {
        var selects = document.querySelectorAll('select');
        for (var i = 0; i < selects.length; i++) {
            var sel = selects[i];
            if (sel.disabled || sel.offsetParent === null)
                continue;
            var r = sel.getBoundingClientRect();
            if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom)
                return sel;
        }
        return null;
    }

    function open(sel) {
        close();
        backdrop = document.createElement('div');
        backdrop.className = 'qz-menu-backdrop';
        var menu = document.createElement('div');
        menu.className = 'qz-menu';
        menu.setAttribute('role', 'listbox');

        Array.prototype.forEach.call(sel.options, function (opt) {
            if (opt.hidden)
                return;
            var item = document.createElement('div');
            item.className = 'qz-menu-item' + (opt.selected ? ' selected' : '') + (opt.disabled ? ' disabled' : '');
            item.setAttribute('role', 'option');
            item.textContent = opt.textContent;
            if (!opt.disabled) {
                item.addEventListener('click', function (e) {
                    e.stopPropagation();
                    close();
                    if (sel.value !== opt.value) {
                        sel.value = opt.value;
                        sel.dispatchEvent(new Event('input', { bubbles: true }));
                        sel.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                });
            }
            menu.appendChild(item);
        });

        backdrop.addEventListener('click', close);
        backdrop.appendChild(menu);
        document.body.appendChild(backdrop);

        // Under the field, or above it when the room below is short; as wide as the field
        var r = sel.getBoundingClientRect();
        var margin = 12;
        var width = Math.max(r.width, 160);
        var left = Math.min(Math.max(margin, r.left), window.innerWidth - width - margin);
        menu.style.left = left + 'px';
        menu.style.width = width + 'px';
        var below = window.innerHeight - r.bottom - margin;
        var above = r.top - margin;
        var height = menu.offsetHeight;
        if (height <= below || below >= above) {
            menu.style.top = (r.bottom + 4) + 'px';
            menu.style.maxHeight = (below - 4) + 'px';
        } else {
            menu.style.maxHeight = (above - 4) + 'px';
            menu.style.top = (r.top - 4 - Math.min(height, above - 4)) + 'px';
        }
        var current = menu.querySelector('.selected');
        if (current)
            current.scrollIntoView({ block: 'nearest' });
    }

    document.addEventListener('click', function (e) {
        if (!document.documentElement.classList.contains('modern') || backdrop)
            return;
        var sel = selectAt(e.clientX, e.clientY);
        if (!sel)
            return;
        // A label around the select would focus it: the menu takes its place
        e.preventDefault();
        e.stopPropagation();
        open(sel);
    }, true);

    window.addEventListener('resize', close);
    // The menu stays where it opened: the page moving under it closes it
    // (the menu's own scroll of a long list excepted)
    window.addEventListener('scroll', function (e) {
        if (backdrop && !(e.target instanceof Node && backdrop.contains(e.target)))
            close();
    }, true);
})();
