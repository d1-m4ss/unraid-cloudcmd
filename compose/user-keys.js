// Loaded by the patched dist/index.html (see README).
//  - Right arrow = enter the folder under the cursor, Left arrow = go to the parent folder.
//  - Inside the Unraid Main page (as its frame, or as the window it opened), F5/F6 start server-side copy/move jobs
//    (rsync, persistent progress) through that page instead of Cloud Commander's own in-tab copy.
(function () {
    var LEFT = 37, RIGHT = 39, ENTER = 13, BACKSPACE = 8, F5 = 116, F6 = 117;
    // The Unraid page that embeds this page (frame) or opened it (window.opener over https).
    var hostWin = window.parent !== window ? window.parent : (window.opener || null);
    var inFrame = !!hostWin;
    var pOrigin = null;      // learned from the first cc-ready sent by hostWin; null = F5/F6 hand-off disabled
    var jobsReady = false;

    function fire(code, key) {
        var target = document.activeElement || document.body;
        var e = new KeyboardEvent('keydown', {key: key, keyCode: code, which: code, bubbles: true, cancelable: true});
        target.dispatchEvent(e);
    }

    function modalOpen() {
        return !!document.querySelector('[class*="smalltalk"], [class*="modal"], [data-name="js-view"], [data-name="js-edit"], [data-name="js-config"]');
    }

    function typing(t) {
        return !!t && (/^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) || t.isContentEditable);
    }

    function startJob(op) {
        var names = DOM.getFilenames(DOM.getActiveFiles()).filter(function (n) { return n !== '..'; });
        if (!names.length) return;
        hostWin.postMessage({
            type: 'cc-job', op: op, src: DOM.getCurrentDirPath(), dst: DOM.getNotCurrentDirPath(), names: names
        }, pOrigin);
        var sel = DOM.getSelectedFiles();
        if (sel && sel.length) DOM.unselectFiles(sel);
    }

    if (inFrame) {
        window.addEventListener('message', function (e) {
            if (e.source !== hostWin || !e.data) return;
            if (e.data.type === 'cc-ready') {
                pOrigin = e.origin;
                jobsReady = true;
            } else if (e.data.type === 'cc-refresh' && window.CloudCmd && CloudCmd.refresh) {
                try { CloudCmd.refresh(); } catch (err) { /* ignore */ }
            }
        });
        hostWin.postMessage({type: 'cc-hello'}, '*');

        document.addEventListener('click', function (e) {
            var b = jobsReady && e.isTrusted && e.target.closest && e.target.closest('#f5, #f6');
            if (!b || typeof DOM === 'undefined' || modalOpen()) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            startJob(b.id === 'f5' ? 'copy' : 'move');
        }, true);
    }

    window.addEventListener('keydown', function (e) {
        if (!e.isTrusted) return;
        if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
        if (typing(e.target)) return;
        if (typeof DOM === 'undefined' || !DOM.CurrentInfo || modalOpen()) return;

        if ((e.keyCode === F5 || e.keyCode === F6) && inFrame && jobsReady) {
            e.preventDefault();
            e.stopImmediatePropagation();
            startJob(e.keyCode === F5 ? 'copy' : 'move');
            return;
        }
        if (e.keyCode !== LEFT && e.keyCode !== RIGHT) return;

        var cur = DOM.CurrentInfo;
        if (e.keyCode === RIGHT) {
            if (cur.isDir && cur.name !== '..') fire(ENTER, 'Enter');
        } else if (cur.dirPath && cur.dirPath !== '/') {
            fire(BACKSPACE, 'Backspace');
        }
        e.preventDefault();
        e.stopImmediatePropagation();
    }, true);
}());
