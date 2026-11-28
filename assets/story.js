/* The Instagram story image (1080x1920) a signer can post: "I signed", their signer number in large gold
   figures, the ask, and "Add your voice / ourfuturesfirst.org", over one of three backgrounds.
   Drawn on a canvas in the site's own fonts (EB Garamond, Nunito Sans) and colours, so it needs no server.
   storyImage(n, k, base) resolves to a PNG Blob: n is the signer number (left out if unknown), k picks the
   background (STORY_BACKGROUNDS[k], wrapping round), base is the path to assets/ ("assets/" by default).
   Each background says where its dark, quiet area is, and the main text sits there; the address always sits
   along the bottom, above the gold line. Preview: tools/story.html?n=412&k=0.
   Browsers keep this file for 4 hours: after changing it, bump ?v= on its <script> tag in index.html. */
(function () {
  var W = 1080, H = 1920, PAD = 110,
      BG = "#0C0C0E", INK = "#ECEAE0", GOLD = "#D3993C",
      HEAD = '"EB Garamond", Garamond, Georgia, serif', SANS = '"Nunito Sans", system-ui, -apple-system, sans-serif';

  /* top: the baseline of "I signed"; gap: from the number down to the ask; width: the ask's line length;
     hush: [x, y, radius] of a soft dark pool behind the text where the picture is bright; shade: darken from this height down, so text over a busy part stays readable */
  var BACKS = window.STORY_BACKGROUNDS = [
    { file: "story-bg-arcs.jpg", top: 380, gap: 118, width: 700, hush: [400, 560, 700] },
    { file: "story-bg-ribbons.jpg", top: 900, shade: 700 },
    { file: "story-bg-paper.jpg", top: 960, shade: 640 }
  ];

  function picture(src) {
    return new Promise(function (done) {
      var i = new Image(); i.onload = function () { done(i); }; i.onerror = function () { done(null); }; i.src = src;
    });
  }
  /* wrap words to a width; returns the lines */
  function wrap(c, text, width) {
    var words = text.split(" "), lines = [], line = "";
    words.forEach(function (w) {
      var t = line ? line + " " + w : w;
      if (c.measureText(t).width > width && line) { lines.push(line); line = w; } else line = t;
    });
    if (line) lines.push(line);
    return lines;
  }

  window.storyImage = function (n, k, base) {
    var back = BACKS[((k || 0) % BACKS.length + BACKS.length) % BACKS.length];
    var fonts = document.fonts ? Promise.all([
      document.fonts.load('500 200px "EB Garamond"'), document.fonts.load('400 60px "EB Garamond"'),
      document.fonts.load('600 40px "Nunito Sans"'), document.fonts.load('700 40px "Nunito Sans"')
    ]).catch(function () {}) : Promise.resolve();
    return Promise.all([fonts, picture((base || "assets/") + back.file)]).then(function (got) {
      var bg = got[1], cv = document.createElement("canvas"); cv.width = W; cv.height = H;
      var c = cv.getContext("2d"); c.textBaseline = "alphabetic";
      c.fillStyle = BG; c.fillRect(0, 0, W, H);
      if (bg) c.drawImage(bg, 0, 0, W, H);
      if (back.shade != null) {
        var g = c.createLinearGradient(0, back.shade, 0, back.shade + 420);
        g.addColorStop(0, "rgba(8,8,10,0)"); g.addColorStop(1, "rgba(8,8,10,.62)");
        c.fillStyle = g; c.fillRect(0, back.shade, W, H - back.shade);
      }
      if (back.hush) {
        var h = back.hush, r = c.createRadialGradient(h[0], h[1], 0, h[0], h[1], h[2]);
        r.addColorStop(0, "rgba(8,8,10,.82)"); r.addColorStop(.6, "rgba(8,8,10,.6)"); r.addColorStop(1, "rgba(8,8,10,0)");
        c.fillStyle = r; c.fillRect(0, 0, W, H);
      }
      /* a soft shadow under every letter keeps it clear of the gold lines behind */
      c.shadowColor = "rgba(0,0,0,.65)"; c.shadowBlur = 28;

      /* I signed */
      var y = back.top;
      c.fillStyle = INK; c.font = "500 190px " + HEAD;
      c.fillText("I signed", PAD - 6, y);

      /* the signer number, large, in gold */
      if (n) {
        y += 230;
        c.fillStyle = GOLD; c.font = "500 240px " + HEAD;
        c.fillText("#" + Number(n).toLocaleString("en-US"), PAD - 10, y);
      }

      /* the ask, with the last phrase in gold */
      y += back.gap || 135;
      c.font = "400 62px " + HEAD;
      /* the gold phrase never breaks across lines: its spaces are no-break spaces, which wrap() does not split on */
      var tail = "our\u00a0futures\u00a0first.", ask = "I ask the U.S. government and AI companies to put " + tail;
      var lines = wrap(c, ask, back.width || W - PAD * 2), at = ask.length - tail.length, pos = 0;
      lines.forEach(function (line) {
        var x = PAD;
        for (var j = 0; j < line.length; j++) {
          c.fillStyle = pos + j >= at ? GOLD : INK; c.fillText(line[j], x, y); x += c.measureText(line[j]).width;
        }
        pos += line.length + 1; y += 80;
      });

      /* where to sign, along the bottom above the gold line */
      y = H - 300;
      c.font = "600 44px " + SANS; c.fillStyle = INK; c.fillText("Add your voice", PAD, y);
      c.font = "700 56px " + SANS; c.fillStyle = GOLD; c.fillText("ourfuturesfirst.org", PAD, y + 76);

      return new Promise(function (done) { cv.toBlob(done, "image/png"); });
    });
  };
})();
