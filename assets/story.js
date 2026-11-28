/* The Instagram story image (1080x1920) a signer can post: the star and "Our Futures First" with each word's
   first letter in the star's gold, "I signed.", their signer number, the ask, and the site's address.
   Drawn on a canvas in the site's own fonts (EB Garamond, Nunito Sans) and colours, so it needs no server.
   storyImage(n) resolves to a PNG Blob; n is the signer number (left out if unknown).
   Instagram covers about the top and bottom 250 px of a story with its own buttons, so nothing sits there.
   Preview: tools/story.html. */
(function () {
  var W = 1080, H = 1920, PAD = 110,
      BG = "#0C0C0E", INK = "#ECEAE0", MUTE = "rgba(236,234,224,.62)", LINE = "rgba(236,234,224,.16)",
      INSET = "rgba(236,234,224,.05)", GOLD = "#D3993C",
      HEAD = '"EB Garamond", Garamond, Georgia, serif', SANS = '"Nunito Sans", system-ui, -apple-system, sans-serif';

  function star(src) {
    return new Promise(function (done) {
      var i = new Image(); i.onload = function () { done(i); }; i.onerror = function () { done(null); }; i.src = src;
    });
  }
  /* text with letter spacing, drawn letter by letter so it works in every browser; returns the width */
  function spaced(c, text, x, y, gap, colorOf) {
    for (var k = 0; k < text.length; k++) {
      c.fillStyle = colorOf ? colorOf(k) : c.fillStyle;
      c.fillText(text[k], x, y); x += c.measureText(text[k]).width + gap;
    }
    return x;
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

  window.storyImage = function (n, starSrc) {
    var fonts = document.fonts ? Promise.all([
      document.fonts.load('500 200px "EB Garamond"'), document.fonts.load('400 60px "EB Garamond"'),
      document.fonts.load('600 40px "Nunito Sans"'), document.fonts.load('700 40px "Nunito Sans"'), document.fonts.load('400 40px "Nunito Sans"')
    ]).catch(function () {}) : Promise.resolve();
    return Promise.all([fonts, star(starSrc || "assets/star.svg")]).then(function (got) {
      var img = got[1], cv = document.createElement("canvas"); cv.width = W; cv.height = H;
      var c = cv.getContext("2d"); c.textBaseline = "alphabetic";
      c.fillStyle = BG; c.fillRect(0, 0, W, H);

      /* the star and the name, first letters in gold */
      var y = 330;
      if (img) c.drawImage(img, PAD, y - 64, 84, 84);
      c.font = "600 40px " + SANS;
      var name = "OUR FUTURES FIRST";
      spaced(c, name, PAD + (img ? 112 : 0), y - 6, 6, function (k) { return k === 0 || name[k - 1] === " " ? GOLD : INK; });

      /* I signed. */
      y = 690;
      c.fillStyle = INK; c.font = "500 210px " + HEAD;
      c.fillText("I signed.", PAD - 6, y);

      /* the ask, with the last phrase in gold */
      y += 175;
      c.font = "400 64px " + HEAD;
      var ask = "I ask the U.S. government and AI companies to put our futures first.", tail = "our futures first.";
      var lines = wrap(c, ask, W - PAD * 2), at = ask.length - tail.length, pos = 0;
      lines.forEach(function (line) {
        var x = PAD;
        for (var k = 0; k < line.length; k++) {
          c.fillStyle = pos + k >= at ? GOLD : INK; c.fillText(line[k], x, y); x += c.measureText(line[k]).width;
        }
        pos += line.length + 1; y += 82;
      });

      /* the signer number */
      if (n) {
        y += 70;
        c.strokeStyle = LINE; c.lineWidth = 2; c.beginPath(); c.moveTo(PAD, y); c.lineTo(W - PAD, y); c.stroke();
        y += 70;
        var bw = W - PAD * 2, bh = 230;
        c.fillStyle = INSET;
        if (c.roundRect) { c.beginPath(); c.roundRect(PAD, y, bw, bh, 28); c.fill(); } else c.fillRect(PAD, y, bw, bh);
        c.font = "600 30px " + SANS; c.fillStyle = MUTE;
        spaced(c, "SIGNER", PAD + 48, y + 72, 5);
        c.font = "500 118px " + HEAD; c.fillStyle = GOLD;
        c.fillText("#" + Number(n).toLocaleString("en-US"), PAD + 44, y + 190);
      }

      /* where to sign */
      y = H - 330;
      c.font = "400 40px " + SANS; c.fillStyle = MUTE; c.fillText("Add your voice", PAD, y);
      c.font = "700 56px " + SANS; c.fillStyle = INK; c.fillText("ourfuturesfirst.org", PAD, y + 74);

      return new Promise(function (done) { cv.toBlob(done, "image/png"); });
    });
  };
})();
