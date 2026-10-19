window.bbShare = {
  lineUrl: function (url, text) {
    return 'https://line.me/R/msg/text/?' + encodeURIComponent(text + ' ' + url);
  },
  hide: function () {
    var old = document.getElementById('bb-share');
    if (old && old.parentNode) { old.parentNode.removeChild(old); }
  },
  show: function (url, labels) {
    var self = this;
    self.hide();
    var box = document.createElement('div');
    box.id = 'bb-share';
    box.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:99999;background:#1b2230;color:#fff;padding:16px;font-family:sans-serif;border-top:2px solid #6cf;text-align:center;';
    var title = document.createElement('div');
    title.textContent = labels.title;
    title.style.cssText = 'font-size:18px;margin-bottom:8px;';
    var field = document.createElement('input');
    field.type = 'text';
    field.readOnly = true;
    field.value = url;
    field.style.cssText = 'width:92%;font-size:16px;padding:8px;margin-bottom:10px;';
    var row = document.createElement('div');
    var style = 'font-size:18px;padding:12px 16px;margin:4px;border:0;border-radius:8px;color:#fff;text-decoration:none;display:inline-block;';
    var line = document.createElement('a');
    line.href = self.lineUrl(url, labels.message);
    line.target = '_blank';
    line.rel = 'noopener';
    line.textContent = labels.line;
    line.style.cssText = style + 'background:#06c755;';
    row.appendChild(line);
    if (navigator.share) {
      var share = document.createElement('button');
      share.textContent = labels.share;
      share.style.cssText = style + 'background:#3366cc;';
      share.onclick = function () { navigator.share({ title: labels.title, text: labels.message, url: url }).catch(function () {}); };
      row.appendChild(share);
    }
    var copy = document.createElement('button');
    copy.textContent = labels.copy;
    copy.style.cssText = style + 'background:#555;';
    copy.onclick = function () {
      field.select();
      field.setSelectionRange(0, url.length);
      var done = function () { copy.textContent = labels.copied; };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(done, function () { try { document.execCommand('copy'); done(); } catch (e) {} });
      } else {
        try { document.execCommand('copy'); done(); } catch (e) {}
      }
    };
    row.appendChild(copy);
    var close = document.createElement('button');
    close.textContent = labels.close;
    close.style.cssText = style + 'background:#222;';
    close.onclick = function () { self.hide(); };
    row.appendChild(close);
    box.appendChild(title);
    box.appendChild(field);
    box.appendChild(row);
    document.body.appendChild(box);
  },
};
