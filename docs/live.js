// The DOM substrate's live driver, browser half.
//
// It owns four things and nothing else: which element the reader meant,
// where in a field they meant it, the bytes going into the document,
// and the address bar. The second of those is the browser's because the
// browser lays the page out — a real `<input>` holds the reader's own
// selection, and core's rects describe a picture nobody is looking at.
// Every question of *meaning* — what a press does, what a key does to a
// field, which subtree a route rebuilds — is answered in wasm by the
// same core every other nokre platform runs. The one thing that looks
// like meaning and is not is the chord table: which modifier spells
// "delete the word behind the caret" is a fact about a platform, so it
// is a shell's everywhere, this one included (core/event.zig's `Key`).
//
// There is no framework here and no dependency. What it does depend on
// is the shell hooks a linked service calls out through — the clipboard
// write, the compute-worker ferry, the fetch leg — and those are
// services.js, shared with the compute instance that live-worker.js
// runs.
//
//   import { mount } from "./live.js";
//   await mount({ wasm: "/app.wasm", into: document.body });
//
// The other shape it mounts in is a page the *static* driver already
// wrote (dom-substrate.md). There the document is not this driver's to
// invent: it has its own <main>, it is already showing the screen, it
// is already in a language, and every route on the site is a file with
// a URL of its own. So five options say which page this is and who owns
// what —
//
//   await mount({
//     wasm: "/app.wasm",
//     into: document.getElementById("chrome"),   // the framework's layers
//     content: document.getElementById("content"), // the host's own <main>
//     route: "routing",                          // the screen this file is
//     locale: "fa",                              // the language it is in
//     seed: "/md/routing.md",                    // what it was built from
//     addressing: "documents",                   // a screen is a file here
//   });
//
// — and everything below them is the same driver, doing the same thing.

import { appHooks, registerServiceWorker, reportAuthToOpener, seedStores } from "./services.js";

// core/event.zig's `Key`, in that enum's order. Anything not here is
// not a key nokre has — the set is closed there too, so this table is
// the whole map, and the ordinals are the wire that enum's comptime
// block pins.
//
// The two halves are keyed differently because only one half has a
// browser name. A key the reader can press has one and it is what
// `e.key` reports; the editing commands are *semantic* — "delete the
// word behind the caret" is ⌥⌫ here and Ctrl+Backspace elsewhere — so
// no `e.key` names them and they are keyed by nokre's own spelling, for
// `chordKey` to reach. The two cannot collide: `e.key` is either one
// character or a name in HeadCase, and nothing below is either.
const KEY_BY_CODE = {
  Tab: 0, Enter: 1, " ": 2, Escape: 3, Backspace: 4, Delete: 5,
  ArrowLeft: 6, ArrowRight: 7, ArrowUp: 8, ArrowDown: 9,
  Home: 10, End: 11, PageUp: 12, PageDown: 13,
  word_left: 14, word_right: 15,
  delete_word_backward: 16, delete_word_forward: 17,
  select_all: 18, copy: 19, cut: 20, undo: 21, redo: 22,
  delete_to_line_start: 23, delete_to_line_end: 24,
};

// The elements this driver treats as text: a real field the reader
// types into, which is not every `<input>` the serializer writes (a
// checkbox and a radio are inputs and hold no selection at all).
const EDITABLE = "input[type=text], input[type=password], textarea";

// Which modifier spells an editing command, decided from the platform
// **here**. That is the arrangement on all five native shells and it is
// deliberate: a chord never travels, so core carries no per-platform
// table and never asks what platform it is on (core/event.zig's `Key`).
// This is the browser's copy of `key_from_ctrl_chord` on Windows and
// `chord_key` on Linux; macOS gets its own column because ⌥ moves by
// word there and ⌘ commands.
const APPLE = /mac|iphone|ipad|ipod/i.test(
  navigator.userAgentData?.platform ?? navigator.platform ?? "",
);

// The letter under the finger. `key` is what the reader's layout
// prints, which is the answer their fingers expect on any Latin
// layout; `code` is the physical key it is printed on, which is the
// only answer left on a layout that prints no Latin letter at all —
// the same two-step the Linux shell's `latin_letter` makes against the
// keymap, so ⌘A selects all on a Cyrillic layout here too.
function letterOf(e) {
  const key = e.key ?? "";
  if (/^[a-zA-Z]$/.test(key)) return key.toLowerCase();
  return /^Key([A-Z])$/.exec(e.code ?? "")?.[1].toLowerCase();
}

// One chord, as the semantic key it means, or undefined for a chord
// this driver does not claim — which then travels as its plain key with
// the modifier bits set, exactly as Ctrl+Tab does on every shell.
//
// **Copy and cut are deliberately absent**, and they are the one pair
// whose absence is a decision rather than a gap: the clipboard write of
// a real `<input>` is the browser's own, and intercepting it would
// hand core a job it can only do worse (no user gesture, no
// `text/plain` flavour, no permission). So ⌘C/⌘X stay uncancelled and
// only the *deletion* half of a cut comes back, as `deleteByCut` on the
// beforeinput lane.
function chordKey(e) {
  const command = APPLE ? e.metaKey : e.ctrlKey;
  const word = APPLE ? e.altKey && !e.metaKey : e.ctrlKey;
  if (word) {
    switch (e.key) {
      case "ArrowLeft": return KEY_BY_CODE.word_left;
      case "ArrowRight": return KEY_BY_CODE.word_right;
      case "Backspace": return KEY_BY_CODE.delete_word_backward;
      case "Delete": return KEY_BY_CODE.delete_word_forward;
    }
  }
  if (command) {
    // ⌘⌫ is macOS' delete-to-line-start; the same command is Ctrl+U in
    // every readline binding, which is the `else` column's own row
    // below rather than a Ctrl+Backspace that already means the word.
    if (APPLE && e.key === "Backspace") return KEY_BY_CODE.delete_to_line_start;
    switch (letterOf(e)) {
      case "a": return KEY_BY_CODE.select_all;
      // Shift picks the branch here rather than travelling as "undo,
      // extending a selection", which is not a thing. Ctrl+Y is the
      // second redo chord every Windows and GTK user brings with them,
      // and is nothing on a Mac.
      case "z": return e.shiftKey ? KEY_BY_CODE.redo : KEY_BY_CODE.undo;
      case "y": return APPLE ? undefined : KEY_BY_CODE.redo;
      default: break;
    }
  }
  // Emacs' pair, and **only on a Mac**, where macOS binds ⌃U and ⌃K in
  // every text field and no browser wants either. Elsewhere they are
  // the browser's own — Ctrl+K opens the omnibox in Chrome and cannot
  // be cancelled at all, Ctrl+U is view-source — so the Windows and
  // Linux column reaches these two commands through no chord rather
  // than through one the reader will not get.
  if (APPLE && e.ctrlKey && !e.metaKey && !e.altKey) {
    switch (letterOf(e)) {
      case "k": return KEY_BY_CODE.delete_to_line_end;
      case "u": return KEY_BY_CODE.delete_to_line_start;
      default: break;
    }
  }
  return undefined;
}

// The inputTypes a composition session emits: the first pair during it
// (every engine), the second at its edges (WebKit). None are this
// driver's to forward — the composition events are the one lane — but
// the WebKit pair *is* cancelable and must be refused, because core
// applies the commit itself and the browser inserting it too would
// type it twice. preventDefault on the non-cancelable pair is inert.
const COMPOSITION_INPUTS = new Set([
  "insertCompositionText", "deleteCompositionText",
  "insertFromComposition", "deleteByComposition",
]);

export async function mount({ wasm, into, worker, content, route, locale, seed, addressing }) {
  // The oauth popup lands on the app's own page (services.js states
  // the design): a popup carrying an auth response reports its URL to
  // its opener and closes, instead of booting a second app nobody will
  // ever see.
  if (reportAuthToOpener()) return null;
  const utf8 = new TextDecoder();
  const bytes = new TextEncoder();
  let nk = null;

  // Where a screen is a document, the browser is already the router.
  // It owns every link — the reader's middle click, their copy, their
  // Back — and it owns the address bar, because the address bar is
  // *the file being served*. What is left for this driver is the half
  // a file cannot do: measuring, folding, focus, and every control that
  // is not a link.
  const documents = addressing === "documents";
  // The screen goes where the host put it, or into a <main> of the
  // driver's own beside the chrome. One walk writes both halves either
  // way; only the seam moves.
  const screen = content ?? into;
  const wrap = content ? 0 : 1;

  // Started before the module is fetched, awaited just before boot: a
  // seed is read *inside* the first build, so it has to be in hand by
  // then, and two round trips in sequence would be one too many.
  const seeding = seed === undefined ? null : fetch(seed).then((r) => r.text());
  // Re-read, never cached: a wasm call may grow the heap and detach
  // whatever view was taken before it (services.js says it at length).
  const memory = () => new Uint8Array(nk.memory.buffer);
  const read = (ptr, len) => utf8.decode(memory().subarray(ptr, ptr + len));

  // A driver is a shell here as much as AppKit is one there, and it
  // owes the same free functions. `onWork` is how anything that lands
  // asynchronously — a worker reply, a response — gets a frame: core
  // invalidates on its own, and this is the signal that it may have.
  // The module's own address: a stage's recording is a file published
  // beside it, whatever page the reader is on.
  const wasmUrl = new URL(wasm, location.href);
  const env = appHooks({
    nk: () => nk,
    memory,
    wasmUrl: wasmUrl.href,
    onPlayAsked: (ticket, file) => plays.set(ticket, file),
    onPictureShown: (ticket, got) => showPicture(ticket, got),
    onPictureDropped: (ticket) => dropPicture(ticket),
    workerUrl: worker ? new URL(worker, location.href) : new URL("./live-worker.js", import.meta.url),
    onWork: () => frame(),
    // A width core was told is a width core decided from, so answers
    // that changed are not repainted, they are re-asked. `setViewport`
    // is the way in: it reshapes the nav and marks layout dirty, which
    // is the whole of what a new set of advances can affect.
    onMetrics: () => remeasure(),
  });

  const source = await WebAssembly.instantiateStreaming(fetch(wasm), { env });
  nk = source.instance.exports;

  // ---- the selection, both ways ------------------------------------
  //
  // A real `<input>` is the reader's own selection surface: they drag
  // in it, double-click a word in it and ⌘A it, and none of that passes
  // through core. So the browser is the one that knows where the
  // selection is, and core is the one that decides what an edit does to
  // it — which only works while the two agree. They are made to agree
  // in both directions and nowhere else: `sendSelection` before every
  // edit that acts on a range and on every `selectionchange`, and
  // `restoreFocus` writing core's answer back after a frame.
  //
  // The offsets cross as **bytes**. Core counts UTF-8 and a field
  // counts UTF-16 units, and the conversion is the glue's here for the
  // reason it is each native shell's (platform/shell.h's
  // `nokre_editable_snapshot`): core carrying a second index space for
  // every string it owns would charge the platforms that never asked.
  const byteAt = (value, units) => bytes.encode(value.slice(0, units)).length;
  const unitAt = (value, byte) => utf8.decode(bytes.encode(value).subarray(0, byte)).length;

  // `anchor` is the fixed end and `cursor` the live one — where the
  // caret is, and where a following Shift+motion extends from. A
  // browser states which is which as `selectionDirection`, so the order
  // survives the crossing instead of being guessed at.
  function sendSelection(el) {
    // Not mid-composition: the preedit is in the field's value and not
    // in core's, so every offset in it names a different string.
    if (composing || el.selectionStart === null || el.selectionStart === undefined) return;
    const back = el.selectionDirection === "backward";
    nk.nokre_dom_select_range(
      byteAt(el.value, back ? el.selectionEnd : el.selectionStart),
      byteAt(el.value, back ? el.selectionStart : el.selectionEnd),
    );
  }

  // This element if it is a field, and null for anything else — a
  // press target, a document's `activeElement`, a pointer's target.
  function editableOf(el) {
    return el && el.matches?.(EDITABLE) ? el : null;
  }

  // A selection the reader is still drawing. Anything that lands a
  // frame mid-drag — a worker reply, a resize, a response — would
  // otherwise write core's copy of the range back into the field the
  // pointer is inside, and a `setSelectionRange` under a held button is
  // the end of the drag in every engine.
  let dragging = false;
  const doc = into.ownerDocument;
  doc.addEventListener("pointerdown", (e) => {
    dragging = editableOf(e.target) !== null;
  });
  // Both endings, because only one of them is the reader letting go
  // where they meant to: a button released outside the window still
  // ends the drag on this document, and a recognizer that loses the
  // pointer sends `pointercancel` and nothing else. A flag that stayed
  // true would stop restoring the caret for the rest of the session.
  for (const ending of ["pointerup", "pointercancel"]) {
    doc.addEventListener(ending, () => {
      dragging = false;
    });
  }

  // The browser moved the selection: a drag, a double-click on a word,
  // a ⌘A this driver left to it, a caret placed by a click. Every
  // engine ends up firing this at the document, so that is where it is
  // heard and `activeElement` is what says whose selection moved.
  //
  // No frame. Nothing in the markup carries a selection — the field
  // is the browser's own and already shows it — so a frame here would
  // repaint nothing and hand `restoreFocus` a chance to fight the drag
  // that is still in progress. What core is owed is the *fact*, and it
  // is owed it before the next edit rather than at a paint.
  doc.addEventListener("selectionchange", () => {
    const field = editableOf(doc.activeElement);
    if (field) sendSelection(field);
  });

  // Strings in: one scratch buffer, filled then consumed by the export
  // that was waiting for it.
  function put(text) {
    const encoded = bytes.encode(text);
    const ptr = nk.nokre_dom_scratch(encoded.length);
    // Null is wasm-side OOM (the locale scratch's contract): hand over
    // the empty string rather than writing at address 0.
    if (!ptr) return 0;
    memory().set(encoded, ptr);
    return encoded.length;
  }

  // ---- frame ------------------------------------------------------

  // A frame renders when state changes, and otherwise nothing runs: the
  // one ticker is a playing stage's, below, and it runs only while one
  // plays. The string compare is what makes an event that changed
  // nothing cost nothing.
  let painted = "";
  let painted_screen = "";
  const staging = document.createElement("template");

  function paint(target, html, last) {
    if (html === last) return last;
    staging.innerHTML = html;
    patch(target, staging.content);
    return html;
  }

  function frame() {
    reportScreen();
    const ptr = nk.nokre_dom_render(wrap);
    const len = nk.nokre_dom_render_len();
    // Two regions, one walk. The host document decided where the
    // framework's layers sit and where the screen sits — the nav leads
    // the focus order, and the <main> is what the skip link names — so
    // the split is read at the seam wasm wrote it at. In *bytes*: a
    // string index would put the cut somewhere else the moment a screen
    // holds a character that is not ASCII, which most of them do.
    const cut = content ? nk.nokre_dom_chrome_len() : len;
    const [was, wasScreen] = [painted, painted_screen];
    painted = paint(into, read(ptr, cut), painted);
    if (content) {
      painted_screen = paint(content, read(ptr + cut, len - cut), painted_screen);
      // The class is layout's answer and not the page's: whether a
      // screen owes the clear space bottom chrome needs depends on what
      // chrome it has, which the pass that just ran decided. `toggle`,
      // not an assignment — the rest of that class list is the
      // document's own.
      content.classList.toggle("has-chrome", !!nk.nokre_dom_chromed());
    }
    // Both mounts have met the tree once now, so whatever the host page
    // arrived carrying has been reconciled with it and every `data-n` in
    // the document is this app's. Cleared here rather than at the top of
    // the function because the two mounts are two hydrations of one
    // frame, and the chrome's would otherwise be the only one.
    hydrating = false;
    syncBigScreen();
    fetchPlays();
    syncPictures();
    syncTables();
    restoreFocus();
    syncAddressBar();
    syncRoot();
    syncBanner();
    // `paint` hands back what it was given when nothing moved, so an
    // unchanged frame compares a reference and measures nothing.
    framed = true;
    placeHands();
    syncLamp(painted !== was || painted_screen !== wasScreen);
    playOn();
    if (find(`.stage[${BIG}]`) && reportScreen()) frame();
  }

  // ---- a stage's recording ---------------------------------------
  //
  // A stage asks for its recording once it is laid out, under a ticket
  // its figure carries; the fetch waits until the figure is on screen,
  // so a stage below the fold costs nothing until the reader reaches
  // it, and a page with no stage fetches none. Until the answer the
  // window keeps what the document holds (a written page's first scene)
  // or stands as the stand-in; a failure is handed back, and the stage
  // says so and offers Retry, which asks again under a new ticket.
  const plays = new Map(); // ticket -> file, asked and not yet watched
  const ASK = "data-ask";
  function fetchPlays() {
    for (const [ticket, file] of plays) {
      plays.delete(ticket);
      const figure = find(`figure[${ASK}="${ticket}"]`);
      if (!figure || typeof IntersectionObserver !== "function") {
        fetchPlay(ticket, file);
        continue;
      }
      const watch = new IntersectionObserver((entries) => {
        if (!entries.some((e) => e.isIntersecting)) return;
        watch.disconnect();
        fetchPlay(ticket, file);
      });
      watch.observe(figure);
    }
  }
  async function fetchPlay(ticket, file) {
    let got;
    try {
      const response = await fetch(new URL(file, wasmUrl));
      if (!response.ok) throw new Error(`${response.status}`);
      got = new Uint8Array(await response.arrayBuffer());
    } catch {
      nk.nokre_dom_play_failed(ticket);
      frame();
      return;
    }
    const ptr = nk.nokre_dom_play_scratch(got.length);
    if (!ptr) {
      nk.nokre_dom_play_failed(ticket);
    } else {
      memory().set(got, ptr);
      nk.nokre_dom_play_arrived(ticket, got.length);
    }
    frame();
  }

  // ---- a picture from data ----------------------------------------
  //
  // Its bytes cross once per entry, when wasm hands them over under a
  // ticket (live.zig's `handOverPictures`): the browser gets a blob URL
  // of them, which every `<img>` naming that ticket takes as its `src`,
  // and the URL is revoked when the entry is swept. The browser
  // decodes; an image it cannot decode is reported, and the picture
  // stands its could-not-show box from the next frame. The `src` is
  // this driver's and not the markup's, so a patch leaves it standing
  // (`pictureOwns`).
  const pictureUrls = new Map(); // ticket -> blob URL
  const PICTURE = "data-picture";
  // A u32 crosses into JavaScript as a signed i32; the markup writes it
  // unsigned, so every key here is the unsigned reading.
  function showPicture(ticket, got) {
    pictureUrls.set(ticket >>> 0, URL.createObjectURL(new Blob([got], { type: "image/png" })));
  }
  function dropPicture(ticket) {
    const url = pictureUrls.get(ticket >>> 0);
    if (url === undefined) return;
    pictureUrls.delete(ticket >>> 0);
    URL.revokeObjectURL(url);
  }
  function pictureOwns(next, name) {
    return name === "src" && next.nodeName === "IMG" && next.hasAttribute(PICTURE);
  }
  function syncPictures() {
    for (const host of roots) {
      for (const img of host.querySelectorAll(`img[${PICTURE}]`)) {
        const ticket = Number(img.getAttribute(PICTURE));
        const url = pictureUrls.get(ticket);
        if (url === undefined || img.getAttribute("src") === url) continue;
        img.onerror = () => {
          nk.nokre_dom_picture_failed(ticket);
          frame();
        };
        img.setAttribute("src", url);
      }
    }
  }

  // ---- the big screen ----------------------------------------------
  //
  // A stage on the big screen covers the browser's window, and core lays
  // it out on the window's size (live.zig's `screen`), where the
  // viewport it holds is the page's column. The size is the box the
  // sheet's fixed pane takes, read off the pane while one stands; before
  // one does, the root's client width, which a classic scrollbar is
  // outside of, and `innerHeight`, which the dynamic viewport moves. Not
  // the root's width while one stands: Chrome then answers it without the
  // gutter the pane keeps. Read before every frame, because a page that
  // grows a scrollbar changes the width with no resize, and after one
  // that put a pane up, which is laid out again where the guess was off.
  let reportedScreen = "";
  function reportScreen() {
    const pane = find(`.stage[${BIG}] > .stage-pane`);
    const w = pane ? pane.clientWidth : root.clientWidth || innerWidth;
    const h = pane ? pane.clientHeight : innerHeight;
    if (`${w}x${h}` === reportedScreen) return false;
    reportedScreen = `${w}x${h}`;
    nk.nokre_dom_screen(w, h);
    return true;
  }

  // The figure keeps its place in the page while its pane stands over
  // the window: at the height the browser gave it, measured as the
  // attribute arrives and released as it goes, since core's own page
  // height can differ from the browser's by a pixel and then everything
  // beneath would move. It rides the figure's `style` beside the lamp's
  // numbers (`writeStyle`).
  //
  // The page beneath is held still by the sheet (`overflow: hidden` on
  // the root). Where it had a classic scrollbar, taking it away would
  // widen the window under the pane by its gutter, so the gutter is kept
  // while the stage is big; where it had none, keeping one would narrow it.
  const BIG = "data-big";
  const heldPlace = new WeakMap(); // figure -> its page height as a declaration
  let bigGutter = false;
  let gutterKept = false;
  function holdPlace(figure, big) {
    if (!big) {
      heldPlace.delete(figure);
      return;
    }
    heldPlace.set(figure, `;--stage-held:${figure.getBoundingClientRect().height}px`);
    bigGutter = innerWidth > root.clientWidth;
  }
  function syncBigScreen() {
    const keep = bigGutter && find(`.stage[${BIG}]`) !== null;
    if (keep === gutterKept) return;
    gutterKept = keep;
    if (keep) root.style.setProperty("scrollbar-gutter", "stable");
    else root.style.removeProperty("scrollbar-gutter");
  }

  // ---- a stage's hand ----------------------------------------------
  //
  // The browser lays a scene out in its own idiom — its own line breaks
  // and faces, and its nav the shape the window's width says — so a
  // point core worked out on its own layout can stand beside the node the
  // browser drew. The scene marks what the hand is on instead (`HAND`:
  // a node, a ranking's stop, or the window, and where on its box in
  // thousandths), and after each frame, and whenever a window changes
  // size, the hand is put there on the box the browser drew. The scene
  // moves first if that box is not wholly in the band no chrome floats
  // over: by the least amount from the scroll the recording left, and no
  // further than a real scroll could (core's `act_reveal_margin`, which
  // keeps no clearance beyond that band, so none here either). A box
  // taller than the band brings its top in. What rides a fixed layer —
  // the band, a sheet — stands where its window puts it, and moves no
  // scene. The move is the scene's `margin-top`, its scroll in the
  // markup, rather than a scroll of the window: the window clips with
  // `overflow: hidden`, and a scroll offset there would be one more
  // thing a patch had to carry across frames. Under a zoom
  // (`sceneZoom`) the boxes the browser hands back are the host's
  // pixels, as the mark is, which stands outside the zoom so its finger
  // is the reader's size; the margin is the scene's own pixels, so the
  // move is worked out in the host's and written in the scene's. A
  // step's rest draws no hand but marks what the step acted on (`AIM`),
  // and the scene moves to it by the same rule.
  const HAND = "data-hand";
  const AIM = "data-aim";
  const STAGE_WINDOW = ".stage-window";
  const handOwn = new WeakMap(); // element -> the declarations placing it
  const handWindows = new Set();
  const handWatch = typeof ResizeObserver === "function"
    ? new ResizeObserver(() => {
      placeHands();
      lampAgain();
    })
    : null;

  function setHand(el, own) {
    if (handOwn.get(el) === own) return;
    const markup = markupStyle(el);
    if (own === undefined) handOwn.delete(el);
    else handOwn.set(el, own);
    writeStyle(el, markup);
  }

  function placeHands() {
    const now = new Set();
    for (const host of roots) for (const win of host.querySelectorAll(STAGE_WINDOW)) now.add(win);
    for (const win of handWindows) {
      if (now.has(win)) continue;
      handWindows.delete(win);
      handWatch?.unobserve(win);
    }
    for (const win of now) {
      if (!handWindows.has(win)) {
        handWindows.add(win);
        handWatch?.observe(win);
      }
      placeHand(win);
    }
  }

  const childOf = (el, cls) => [...el.childNodes].find((n) => n.nodeType === Node.ELEMENT_NODE && n.classList.contains(cls)) ?? null;
  const isFixedLayer = (el) => typeof getComputedStyle === "function" && getComputedStyle(el).position === "fixed";

  // A scene's zoom over its window, as the viewport's markup writes it
  // (`serialize.sceneZoom`): `[num, den]`, `[1, 1]` at 1:1.
  function sceneZoom(viewport) {
    const m = /zoom:(?:calc\((\d+)\/(\d+)\)|(\d+))/.exec((viewport && markupStyle(viewport)) ?? "");
    return !m ? [1, 1] : m[3] ? [Number(m[3]), 1] : [Number(m[1]), Number(m[2])];
  }

  function placeHand(win) {
    const viewport = childOf(win, "stage-viewport");
    const scene = viewport && childOf(viewport, "stage-scene");
    const mark = childOf(win, "stage-mark");
    const hand = win.hasAttribute(HAND) ? win : win.querySelector(`[${HAND}]`);
    const on = mark ? hand : win.querySelector(`[${AIM}]`);
    if (!scene) return;
    if (!on) {
      setHand(scene, undefined);
      if (mark) setHand(mark, undefined);
      return;
    }
    const w = win.getBoundingClientRect();
    const box = on.getBoundingClientRect();
    if (!(box.width > 0 && box.height > 0)) {
      setHand(scene, undefined);
      if (mark) setHand(mark, undefined);
      return;
    }
    // The scroll the recording left, and the one standing now, in the
    // scene's pixels; `toHost` and `toScene` take a length across.
    const [num, den] = sceneZoom(viewport);
    const toHost = (v) => (v * num) / den;
    const toScene = (v) => (v * den) / num;
    const at = /margin-top:\s*(-?[\d.]+)px/.exec(markupStyle(scene) ?? "");
    const rest = at ? -Number(at[1]) : 0;
    const nowAt = /margin-top:\s*(-?[\d.]+)px/.exec(handOwn.get(scene) ?? "");
    const standing = nowAt ? -Number(nowAt[1]) : rest;
    let moves = on !== win;
    let band = [w.top, w.bottom];
    for (let el = on; moves && el && el !== scene; el = parentOf(el)) if (isFixedLayer(el)) moves = false;
    if (moves) {
      for (const layer of scene.childNodes) {
        if (layer.nodeType !== Node.ELEMENT_NODE || !isFixedLayer(layer)) continue;
        const r = layer.getBoundingClientRect();
        if (!(r.width > 0 && r.height > 0)) continue;
        if (r.top + r.bottom > w.top + w.bottom) band[1] = Math.min(band[1], r.top);
        else band[0] = Math.max(band[0], r.bottom);
      }
    }
    // Where the box stands at the recording's scroll, and at the one it
    // is brought in by.
    const top = moves ? box.top + toHost(standing - rest) : box.top;
    let scroll = rest;
    if (moves) {
      const most = Math.max(rest, toScene(scene.getBoundingClientRect().height - w.height));
      if (top < band[0] || box.height > band[1] - band[0]) scroll = Math.max(0, rest + toScene(top - band[0]));
      else if (top + box.height > band[1]) scroll = Math.min(most, rest + toScene(top + box.height - band[1]));
    }
    setHand(scene, scroll === rest ? undefined : `;margin-top:${-scroll}px`);
    if (!mark) return;
    const [ax, ay] = on.getAttribute(HAND).split(",").map(Number);
    const x = box.left - w.left + (box.width * ax) / 1000;
    const y = top - toHost(scroll - rest) - w.top + (box.height * ay) / 1000;
    setHand(mark, `;--x:${Math.round(x)}px;--y:${Math.round(y)}px`);
  }

  // A playing stage's clock (shell.h's `wants_ticks`): the browser's
  // animation frames, asked for only while one plays, each one's time
  // handed to core before the frame that shows it. A hidden tab gets no
  // animation frames, so a stage in one waits.
  let playFrame = 0;
  let playLast = 0;
  function playOn() {
    if (playFrame || !nk.nokre_dom_wants_ticks() || typeof requestAnimationFrame !== "function") return;
    playLast = 0;
    playFrame = requestAnimationFrame(playTick);
  }
  function playTick(now) {
    playFrame = 0;
    if (!nk.nokre_dom_wants_ticks()) return;
    const since = playLast ? now - playLast : 16;
    playLast = now;
    nk.nokre_dom_tick(Math.min(1000, Math.round(since)));
    frame();
    if (!playFrame && nk.nokre_dom_wants_ticks()) playFrame = requestAnimationFrame(playTick);
  }

  // The page-level facts core owns and no markup carries: which ramp
  // the page paints in (appearance and theme), which way its chrome is
  // mirrored, and how the screen is arranged. The arrangement is the
  // route's *and* the window's, so it is the only one of them that can
  // change without the reader touching anything — a navigation is
  // enough, and so is a drag of the window's edge.
  //
  // Neither is a media query's to answer. `App.scheme` may pin light or
  // dark and only `auto` defers to the desktop — so the OS preference
  // goes *in*, the same report a native shell makes, and what comes
  // back out is the resolved appearance. Direction is `setDirection`,
  // which a localized app pairs with its locale.
  //
  // They land as attributes on the document root, where the generated
  // sheet already puts the palette, and that sheet spends them on
  // nokre's own surfaces only — a substrate mounted in someone else's
  // document has no business restyling the page around it. Without the
  // appearance attribute the sheet falls back to the media query, which
  // is all a page with no app behind it has.
  const root = doc.documentElement;
  const dark = matchMedia("(prefers-color-scheme: dark)");
  const moreContrast = matchMedia("(prefers-contrast: more)");
  const lessTransparency = matchMedia("(prefers-reduced-transparency: reduce)");
  const lessMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const SHAPE = ["", "desk", "desk-narrow"];
  const THEME = ["", "depth", "lamp"];
  let chromePair = null;

  function syncRoot() {
    const appearance = nk.nokre_dom_appearance() ? "dark" : "light";
    if (root.getAttribute("data-nokre-appearance") !== appearance) root.setAttribute("data-nokre-appearance", appearance);
    const direction = nk.nokre_dom_direction() ? "rtl" : "ltr";
    if (root.getAttribute("data-nokre-direction") !== direction) root.setAttribute("data-nokre-direction", direction);
    // The third fact, written by taking the attribute *away* for the
    // default, which is what absence means in the sheet's unkeyed rules
    // and in a generated file alike. `setAttribute`/`removeAttribute`
    // rather than `dataset` because absence is one of the three states,
    // and because the name is then one literal the build reads
    // (class_names.zig).
    const shape = SHAPE[nk.nokre_dom_shape()];
    if (shape === "") root.removeAttribute("data-nokre-shape");
    else if (root.getAttribute("data-nokre-shape") !== shape) root.setAttribute("data-nokre-shape", shape);
    // The fourth, the look, by the same absence: no attribute is eink.
    const theme = THEME[nk.nokre_dom_theme()];
    if (theme === "") root.removeAttribute("data-nokre-theme");
    else if (root.getAttribute("data-nokre-theme") !== theme) root.setAttribute("data-nokre-theme", theme);
    syncThemeColor();
  }

  // The browser's chrome meets the page: each `theme-color` meta the
  // page carries gets the byte core answers for its `media` scheme
  // (live.zig's `themeColor`), which moves with the theme and with a
  // pinned or released scheme alike. Keyed on the answer rather than on
  // either input, so a new input cannot be missed; written only when it
  // changes.
  function syncThemeColor() {
    const hex = (dark) => "#" + nk.nokre_dom_theme_color(dark).toString(16).padStart(2, "0").repeat(3);
    const pair = [hex(0), hex(1)];
    if (pair.join() === chromePair) return;
    chromePair = pair.join();
    for (const meta of doc.querySelectorAll('meta[name="theme-color"]')) {
      meta.setAttribute("content", pair[/dark/.test(meta.getAttribute("media") ?? "") ? 1 : 0]);
    }
  }

  // A table whose columns' longest words do not fit scrolls sideways in
  // its `.table-wrap` and breaks no word (docs/elements.md, `table`).
  // Whether it does is the real widths' answer, so it is read here —
  // after every frame, and whenever a wrap changes size without one: a
  // font arriving, a zoom. While it overflows the wrap is a tab stop
  // and a scrollable region named by the words core derived for it
  // (`data-name`, `semantics.tableName`) — the name the native snapshot
  // gives the same table; a wrap that fits again drops all three. They are this driver's attributes and not
  // the markup's, so a patch leaves them standing (`tableOwns`) — one
  // stripped and put back every frame would blur a focused wrap.
  const TABLE_OWN = ["tabindex", "role", "aria-label"];
  const tableWatch = typeof ResizeObserver === "function"
    ? new ResizeObserver((entries) => {
      for (const entry of entries) syncTable(entry.target);
    })
    : null;
  const watchedTables = new WeakSet();

  function tableOwns(el, name) {
    return TABLE_OWN.includes(name) && !!el.classList?.contains("table-wrap");
  }

  function syncTables() {
    for (const host of roots) {
      for (const wrap of host.querySelectorAll(".table-wrap")) {
        syncTable(wrap);
        if (tableWatch && !watchedTables.has(wrap)) {
          watchedTables.add(wrap);
          tableWatch.observe(wrap);
        }
      }
    }
  }

  function syncTable(wrap) {
    if (!(wrap.scrollWidth > wrap.clientWidth)) {
      for (const name of TABLE_OWN) if (wrap.hasAttribute(name)) wrap.removeAttribute(name);
      return;
    }
    const name = wrap.getAttribute("data-name") ?? "";
    // A region with no name is no landmark, so a table whose row has no
    // words is a stop and nothing more — and the audit's finding.
    const own = { tabindex: "0", role: name ? "region" : "", "aria-label": name };
    for (const name of TABLE_OWN) {
      if (own[name] === "") {
        if (wrap.hasAttribute(name)) wrap.removeAttribute(name);
      } else if (wrap.getAttribute(name) !== own[name]) wrap.setAttribute(name, own[name]);
    }
  }

  // Focus put on a control inside a scrolled table brings it into the
  // wrap's view, as core's reveal walk does for the raster — the one
  // scroll this driver makes, because `restoreFocus` focuses without
  // letting the browser scroll the page. The leading end wins when the
  // control is wider than the box.
  function revealInTable(el) {
    const wrap = el.closest?.(".table-wrap");
    if (!wrap || wrap === el || !(wrap.scrollWidth > wrap.clientWidth)) return;
    const box = wrap.getBoundingClientRect();
    const at = el.getBoundingClientRect();
    const before = at.left - box.left;
    const after = at.right - box.right;
    const rtl = root.getAttribute("data-nokre-direction") === "rtl";
    let dx = 0;
    if (rtl) dx = after > 0 ? after : before < 0 ? Math.max(before, after) : 0;
    else dx = before < 0 ? before : after > 0 ? Math.min(after, before) : 0;
    if (dx !== 0) wrap.scrollLeft += dx;
  }

  // The banner's height, which is the one length on the page the sheet
  // needs and cannot read. Beside a banner core reserves the banner
  // itself plus the bar's top pad (`layout.contentArea`); here the
  // banner is a fixed layer that wraps to the reader's width, text size
  // and language, so the driver measures it and the sheet's
  // `--chrome-reserve` spends the answer (stylesheet.zig, `write`).
  //
  // An observer rather than a read per frame, because a banner rewraps
  // on things that are not frames — a font arriving, a zoom, a text-size
  // change. It reports after layout and before paint, so a banner that
  // appears or rewraps is never painted beside the old reserve, and
  // the reserve grows at the end of the screen, where the reader's
  // scroll offset does not move what they are looking at.
  const bannerWatch = typeof ResizeObserver === "function"
    ? new ResizeObserver((entries) => {
      for (const entry of entries) {
        root.style.setProperty("--notice-banner-height", `${entry.borderBoxSize[0].blockSize}px`);
      }
      // The reserve moved the page's plates without a frame.
      lampAgain();
    })
    : null;
  let watchedBanner = null;

  function syncBanner() {
    if (!bannerWatch) return;
    // The banner is a direct child of the chrome's mount; a notice row
    // inside the pane is not one.
    let banner = null;
    for (const el of into.childNodes) {
      if (el.nodeType === Node.ELEMENT_NODE && el.classList.contains("notice")) banner = el;
    }
    if (banner === watchedBanner) return;
    if (watchedBanner) bannerWatch.unobserve(watchedBanner);
    watchedBanner = banner;
    if (banner) bannerWatch.observe(banner, { box: "border-box" });
    else root.style.removeProperty("--notice-banner-height");
  }

  // ---- the lamp's numbers -----------------------------------------
  //
  // Lamp's light is a function of where each plate stands in its window,
  // and CSS cannot read an element's own box as numbers. So under lamp
  // this driver measures and publishes them as custom properties the
  // sheet spends (class_names.zig, `lamp_plate` and the groups after it;
  // lamp_plates.zig names the boxes). A page with no runtime publishes
  // nothing, and its plates draw unlit.
  //
  // Measured after a frame that changed the document, on a resize, when
  // the faces finish loading and when the banner's reserve moves — never
  // on a scroll: every number is the box *at rest*, and the sheet places
  // it under a scroll itself.
  const LAMP_PLATE = ["--lamp-plate-left", "--lamp-plate-top", "--lamp-plate-width", "--lamp-plate-height"];
  const LAMP_WINDOW_SIZE = ["--lamp-window-width", "--lamp-window-height"];
  const LAMP_SCROLLPORT = ["--lamp-scrollport-top", "--lamp-scrollport-height"];
  const LAMP_SIDEWAYS = ["--lamp-sideways-top"];
  const LAMP_EDGE_BAR = ["--lamp-edge-bar-left", "--lamp-edge-bar-top", "--lamp-edge-bar-width"];
  const LAMP_EDGE_CHOSEN = ["--lamp-edge-chosen-left", "--lamp-edge-chosen-top", "--lamp-edge-chosen-width"];
  const LAMP_EDGE_SHEET = ["--lamp-edge-sheet-left", "--lamp-edge-sheet-top", "--lamp-edge-sheet-width"];
  const LAMP_PLATES = '.box:not(.bare), .tiles, .stage-frame, .box.bare[style*="background:"], .picker.above-nav, .tile > .square, .badge, .meter-track, .meter-fill, .diverging-track, .diverging-arm, .ctl:not(.busy) input.toggle, .ctl:not(.busy) input.check, .radios input[type="radio"], .seg-track, .seg input:checked + span, .dial-plates, .dial-plate.now, .dial-step, .plate:not(.cut, .pool), .field-box, .picker-item[aria-selected="true"], .btn:not(.secondary, .icon-only, .pending-label), .btn.pending-label, .btn:not(.secondary) .btn-track, .btn:not(.secondary) .btn-fill, .notices-pane .notice, .chip:not(.current), .chip.current, .nav.stacked, .nav-row > .icon-button, .nav-indicator .icon-button, .notice:not(.notices-pane .notice), .sheet, .notices-pane, .picker:not(.above-nav), .chip:not(.current) > .icon, .chip.current > .icon, .nav.stacked .slot > .icon, .nav-row > .icon-button > .icon, .nav-indicator .icon-button > .icon, .notice:not(.notices-pane .notice) > .icon-button > .icon, .notices-pane .notice > .icon-button > .icon, .sheet > .icon-button > .icon, .notices-pane > .icon-button > .icon, .icon-button:is(.back, .header-action) > .icon, .tile > .square.icon, .tile > .square.app-mark, .tiles .tile > .icon:not(.square), .stage-frame > .stage-header > .icon, .stage-frame > .stage-header > button > .icon, .field-box.select > .icon, .dial-step > .icon';
  const LAMP_SCROLLPORTS = '.scroll, .region, .sheet, .notices-pane, .picker';
  const LAMP_SIDEWAYS_SCROLLERS = '.seg-track, .table-wrap, .nav-row, pre.code';
  const LAMP_WINDOW = '.stage-window';
  const SCENE_VIEWPORT = '.stage-viewport';
  const LAMP_EDGE_BAR_PLATES = '.chip:not(.current), .chip.current, .nav.stacked, .nav-row > .icon-button, .nav-indicator .icon-button, .notice:not(.notices-pane .notice)';
  const LAMP_EDGE_CHOSEN_PLATES = '.chip.current, .nav.stacked';
  const LAMP_EDGE_SHEET_PLATES = '.sheet, .notices-pane, .picker:not(.above-nav)';

  // A plate's numbers ride its `style` attribute *behind* the markup's
  // own declarations, written as text: the patcher makes every other
  // attribute the frame's, and gives this one the frame's text with
  // these appended (`writeStyle`), so a frame that moved nothing writes
  // nothing. Not the CSSOM: a CSSOM write re-spells the whole attribute,
  // and the sheet reads a box's fill out of the markup's spelling of it
  // (`[style*="background:"]`, stylesheet.zig).
  const lampOwn = new WeakMap(); // element -> the declarations it carries
  let lampOwners = new Set();
  let lampRoot = new Map(); // property -> value, on the document root
  let lampDirty = true;
  let framed = false;

  // What this driver appends to an element's style: a big stage's held
  // place, a stage's hand and its scene's scroll, and the lamp's numbers.
  function owned(el) {
    const place = heldPlace.get(el);
    const hand = handOwn.get(el);
    const lamp = lampOwn.get(el);
    return place === undefined && hand === undefined && lamp === undefined ? undefined : (place ?? "") + (hand ?? "") + (lamp ?? "");
  }

  function writeStyle(el, markup) {
    const own = owned(el);
    const want = own === undefined ? markup : (markup ?? "") + own;
    if (want === null) {
      if (el.hasAttribute("style")) el.removeAttribute("style");
    } else if (el.getAttribute("style") !== want) el.setAttribute("style", want);
  }

  // The markup's part of an element's style: what it carries without
  // the declarations appended here, and null for no attribute.
  function markupStyle(el) {
    const style = el.getAttribute("style");
    const own = owned(el);
    if (own === undefined || style === null || !style.endsWith(own)) return style;
    return style === own ? null : style.slice(0, style.length - own.length);
  }

  function setOwn(el, own) {
    if (lampOwn.get(el) === own) return;
    const markup = markupStyle(el);
    if (own === undefined) lampOwn.delete(el);
    else lampOwn.set(el, own);
    writeStyle(el, markup);
  }

  function lampAgain() {
    lampDirty = true;
    if (framed) syncLamp(false);
  }

  function syncLamp(committed) {
    if (root.getAttribute("data-nokre-theme") !== "lamp") {
      if (lampOwners.size || lampRoot.size) publishLamp(false);
      lampDirty = true;
      return;
    }
    if (!committed && !lampDirty) return;
    lampDirty = false;
    publishLamp(true);
  }

  const parentOf = (el) => (el.parentNode?.nodeType === Node.ELEMENT_NODE ? el.parentNode : null);

  // Every rect is read before anything is written, so the pass lays the
  // page out once.
  function publishLamp(lit) {
    const writes = new Map();
    const onRoot = new Map();
    const put = (to, el, names, values) => {
      let own = to.get(el) ?? "";
      for (let i = 0; i < names.length; i++) own += `;${names[i]}:${Math.round(values[i])}`;
      to.set(el, own);
    };
    const toRoot = (names, values) => names.forEach((name, i) => onRoot.set(name, String(Math.round(values[i]))));

    const fixed = new Map();
    const isFixed = (el) => {
      if (!fixed.has(el)) fixed.set(el, typeof getComputedStyle === "function" && getComputedStyle(el).position === "fixed");
      return fixed.get(el);
    };
    const pinned = (el) => {
      for (let at = el; at; at = parentOf(at)) if (isFixed(at)) return true;
      return false;
    };
    // How far the scrollers between an element and its window have
    // carried it, which is what puts it back at rest. A fixed box stands
    // where its window puts it, so nothing above one moves it; a stage's
    // window is where the walk ends.
    const shifts = new Map();
    const shift = (el, win) => {
      let s = shifts.get(el);
      if (s) return s;
      const up = parentOf(el);
      if (!up || up === win || isFixed(el)) s = [0, 0];
      else {
        const above = shift(up, win);
        s = [above[0] + (up.scrollLeft || 0), above[1] + (up.scrollTop || 0)];
      }
      shifts.set(el, s);
      return s;
    };
    // Left, top, width and height in the element's lamp window at rest.
    // The scrollers above a stage move the stage and its plates alike,
    // so its window's own rect is the origin as it stands. In a zoomed
    // scene they are the scene's pixels, which is what the sheet spends
    // them as there, and what its scrollers' offsets already are.
    const zooms = new Map();
    const zoomIn = (viewport) => {
      if (!zooms.has(viewport)) zooms.set(viewport, sceneZoom(viewport));
      return zooms.get(viewport);
    };
    const atRest = (el) => {
      const r = el.getBoundingClientRect();
      const win = el.closest(LAMP_WINDOW);
      const [sx, sy] = shift(el, win);
      const o = win ? win.getBoundingClientRect() : { left: 0, top: 0 };
      const [num, den] = win ? zoomIn(el.closest(SCENE_VIEWPORT)) : [1, 1];
      const own = (v) => (v * den) / num;
      return [own(r.left - o.left) + sx, own(r.top - o.top) + sy, own(r.width), own(r.height)];
    };
    // One chrome edge over the page: the union of what the selector
    // finds on screen, or the last of it — the top of the stack.
    const edge = (names, selector, union) => {
      let box = null;
      for (const el of into.querySelectorAll(selector)) {
        if (el.closest(LAMP_WINDOW) || !pinned(el)) continue;
        const r = el.getBoundingClientRect();
        if (!(r.width > 0)) continue;
        box = union && box
          ? [Math.min(box[0], r.left), Math.min(box[1], r.top), Math.max(box[2], r.right)]
          : [r.left, r.top, r.right];
      }
      if (box) toRoot(names, [box[0], box[1], box[2] - box[0]]);
    };

    if (lit) {
      for (const host of roots) {
        for (const win of host.querySelectorAll(LAMP_WINDOW)) {
          const r = win.getBoundingClientRect();
          put(writes, win, LAMP_WINDOW_SIZE, [r.width, r.height]);
          // A zoomed scene is lit from the same window, in its pixels.
          const viewport = childOf(win, "stage-viewport");
          const [num, den] = zoomIn(viewport);
          if (num !== den) put(writes, viewport, LAMP_WINDOW_SIZE, [(r.width * den) / num, (r.height * den) / num]);
        }
        for (const el of host.querySelectorAll(LAMP_PLATES)) put(writes, el, LAMP_PLATE, atRest(el));
        for (const el of host.querySelectorAll(LAMP_SCROLLPORTS)) {
          const [, top, , height] = atRest(el);
          put(writes, el, LAMP_SCROLLPORT, [top, height]);
        }
        for (const el of host.querySelectorAll(LAMP_SIDEWAYS_SCROLLERS)) put(writes, el, LAMP_SIDEWAYS, [atRest(el)[1]]);
      }
      toRoot(LAMP_WINDOW_SIZE, [root.clientWidth || innerWidth, root.clientHeight || innerHeight]);
      edge(LAMP_EDGE_BAR, LAMP_EDGE_BAR_PLATES, true);
      edge(LAMP_EDGE_CHOSEN, LAMP_EDGE_CHOSEN_PLATES, true);
      edge(LAMP_EDGE_SHEET, LAMP_EDGE_SHEET_PLATES, false);
    }

    for (const el of lampOwners) if (!writes.has(el)) setOwn(el, undefined);
    for (const [el, own] of writes) setOwn(el, own);
    lampOwners = new Set(writes.keys());
    for (const name of lampRoot.keys()) if (!onRoot.has(name)) root.style.removeProperty(name);
    for (const [name, value] of onRoot) if (lampRoot.get(name) !== value) root.style.setProperty(name, value);
    lampRoot = onRoot;
  }

  doc.fonts?.addEventListener?.("loadingdone", lampAgain);
  doc.fonts?.ready?.then(lampAgain);

  dark.addEventListener("change", () => {
    nk.nokre_dom_system_appearance(dark.matches ? 1 : 0);
    frame();
  });
  moreContrast.addEventListener("change", () => {
    nk.nokre_dom_system_contrast(moreContrast.matches ? 1 : 0);
    frame();
  });
  lessTransparency.addEventListener("change", () => {
    nk.nokre_dom_system_transparency(lessTransparency.matches ? 1 : 0);
    frame();
  });
  lessMotion.addEventListener("change", () => {
    nk.nokre_dom_system_reduce_motion(lessMotion.matches ? 1 : 0);
    frame();
  });

  // Why this is not `innerHTML = html`.
  //
  // The markup is a projection of the tree and the tree is rebuilt
  // whole, so replacing the document wholesale *renders* correctly —
  // and destroys everything the browser was keeping on the side of it.
  // A scroll offset is the clearest case: a `segmented` track scrolled
  // halfway, a `scroll_region` mid-list, the page itself. Those live on
  // the element, and an element that is replaced rather than updated
  // starts over at zero. Selection, the caret, and `:focus` go the same
  // way.
  //
  // nokre has an answer the browser does not: every focus stop carries
  // its `NodeId` as `data-n`, so identity across frames is *stated*
  // rather than guessed at. Two nodes are the same node when they are
  // the same kind of thing and carry the same id; a node whose id
  // changed is a different node and is replaced outright.
  //
  // ## The first frame is a handover, and there the id says nothing
  //
  // That rule holds between two frames of one running app, because both
  // came out of one tree and a `data-n` is a handle *into* that tree: a
  // slot index and that slot's generation (core/tree.zig's `NodeId`).
  // A page a generator wrote carries no such handles: the file numbers
  // its own nodes (file_numbering.zig), so the numbers it arrives with
  // name nothing in this app's tree and cannot be matched against it.
  //
  // So across the handover identity is **positional**. The file and the
  // frame are the same tree serialized twice by the same walk in the
  // same order — that is what makes hydrating one with the other mean
  // anything at all — and position plus tag is the whole of what the two
  // processes share. The frame's ids arrive the way every other
  // attribute arrives, adopted rather than matched, and from the second
  // frame on the document carries the running tree's own and the rule
  // above is the rule again.
  //
  // The frames themselves keep the tree's ids and are never numbered:
  // a per-frame ordinal would shift every node after an insertion, which
  // destroys exactly the mid-session identity this diff is for
  // (dom-substrate.md, "Node ids").
  let hydrating = true;
  const WAITING = "data-waiting";

  function sameNode(a, b) {
    if (a.nodeType !== b.nodeType) return false;
    if (a.nodeType === Node.TEXT_NODE) return true;
    if (a.nodeName !== b.nodeName) return false;
    if (hydrating) return true;
    return (a.dataset?.n ?? null) === (b.dataset?.n ?? null);
  }

  function patch(cur, next) {
    let a = cur.firstChild;
    let b = next.firstChild;
    while (a || b) {
      if (!b) {
        const gone = a;
        a = a.nextSibling;
        cur.removeChild(gone);
      } else if (!a) {
        const add = b;
        b = b.nextSibling;
        cur.appendChild(document.importNode(add, true));
      } else if (sameNode(a, b)) {
        const [na, nb] = [a.nextSibling, b.nextSibling];
        patchNode(a, b);
        [a, b] = [na, nb];
      } else {
        const fresh = document.importNode(b, true);
        b = b.nextSibling;
        const old = a;
        a = a.nextSibling;
        cur.replaceChild(fresh, old);
      }
    }
  }

  function patchNode(a, b) {
    if (a.nodeType === Node.TEXT_NODE) {
      if (a.data !== b.data) a.data = b.data;
      return;
    }
    if (a.nodeName === "FIGURE" && a.hasAttribute(BIG) !== b.hasAttribute(BIG)) holdPlace(a, b.hasAttribute(BIG));
    for (const attr of [...a.attributes]) {
      if (attr.name === "style") continue;
      if (!b.hasAttribute(attr.name) && !tableOwns(a, attr.name) && !pictureOwns(b, attr.name)) a.removeAttribute(attr.name);
    }
    for (const attr of b.attributes) {
      if (attr.name === "style") continue;
      if (a.getAttribute(attr.name) !== attr.value) a.setAttribute(attr.name, attr.value);
    }
    writeStyle(a, b.getAttribute("style"));
    // A stage waiting for its recording keeps what the document holds
    // there: a written page's first scene and its step's words, which
    // the frame, having no scene yet, would otherwise wipe.
    if (b.hasAttribute(WAITING)) return;
    // Attributes are the markup's idea of a field; the property is the
    // browser's, and only the second one shows. The tree owns both —
    // except mid-composition, when the focused field is the IME's:
    // the preedit lives in its value, the markup carries the value
    // *without* it, and writing that out from under an open session
    // aborts it in every engine. The frame after the session resolves
    // puts the tree's answer back.
    if ((a.nodeName === "INPUT" || a.nodeName === "TEXTAREA") && !(composing && a === document.activeElement)) {
      const value = a.nodeName === "INPUT" ? (b.getAttribute("value") ?? "") : b.textContent;
      if (a.type !== "checkbox" && a.type !== "radio" && a.value !== value) a.value = value;
      // Assigned every time, not only when it looks wrong: the tree's
      // answer is the answer, and a control the browser has been
      // touching can disagree with its own attribute.
      a.checked = b.hasAttribute("checked");
    }
    patch(a, b);
  }

  // The regions this driver writes into, in document order. One where
  // it owns the whole mount, two where the host kept its own <main> —
  // and a focus stop, a press or a keystroke may land in either, so
  // nothing below asks `into` alone.
  const roots = content ? [into, content] : [into];

  function find(selector) {
    for (const root of roots) {
      const el = root.querySelector(selector);
      if (el) return el;
    }
    return null;
  }

  function listen(type, handler) {
    for (const root of roots) root.addEventListener(type, handler);
  }

  // Focus and the selection live on the tree, not in the DOM —
  // `focus.zig` moves one and `editing.zig` the other — so after the
  // document is rewritten they are put back from there rather than
  // guessed at. Which is the second half of a bargain: the browser
  // states the selection the reader made (`sendSelection`), core
  // decides what an edit does to it, and this writes the decision back.
  function restoreFocus() {
    const node = nk.nokre_dom_focused_node();
    const span = nk.nokre_dom_focused_span();
    const selector = span < 0
      ? `[data-n="${node}"]:not([data-s])`
      : `[data-n="${node}"][data-s="${span}"]`;
    // One stop can be many buttons — a ranking is one focus stop over a
    // column of rows, each a button — and the one its cursor stands on
    // says so with `data-cursor` (serialize.zig). Asked first, because
    // the first button under the id is slot 0, which ↑/↓ may long since
    // have left.
    const el =
      find(`${selector}[data-cursor]`) ??
      find(`${selector}:is(a,button,input,select,textarea,[tabindex])`) ??
      find(selector);
    if (!el) return;
    if (el !== document.activeElement) {
      el.focus({ preventScroll: true });
      revealInTable(el);
    }

    // The selection is restored on every frame, not only when focus
    // moved. `editing.zig` owns both of its ends, and writing a field's
    // value puts the DOM's own back at one end — so the frame after a
    // keystroke would leave it there, which is a cursor that jumps to
    // the start of what you are typing.
    //
    // The whole **range**, with the end the caret is on. Restoring a
    // collapsed caret from `cursor` alone is what this used to do, and
    // it destroyed a selection the reader had made on the next event
    // that landed a frame — including the one they made in order to
    // replace it.
    //
    // Not mid-composition, though: the caret is the IME's then — core's
    // own points before the preedit — and poking a field's selection
    // under an open session aborts it, the patchNode rule. Nor while
    // the pointer is down in a field: that is a selection still being
    // drawn, and a write into it ends the drag.
    if (composing || dragging) return;
    const caret = nk.nokre_dom_caret();
    if (caret < 0 || !el.setSelectionRange) return;
    // Both offsets are core's bytes; a field's own are UTF-16 units.
    const to = unitAt(el.value, caret);
    const from = unitAt(el.value, nk.nokre_dom_anchor());
    const start = Math.min(from, to);
    const end = Math.max(from, to);
    // A caret has no direction to disagree about — engines spell a
    // collapsed one "none" and "forward" both — so it is compared only
    // where there is a range, or every frame would rewrite it.
    const way = from > to ? "backward" : "forward";
    if (el.selectionStart === start && el.selectionEnd === end) {
      if (start === end || el.selectionDirection === way) return;
    }
    el.setSelectionRange(start, end, way);
  }

  // core/router.zig's `Change`, in that enum's order.
  const MOTION = ["push", "pop", "replace", "switch_to"];

  // The address bar, both ways (docs/routing.md, "The address"). What
  // the bar shows is core's answer — the current screen's address in the
  // app's declared form, its secret arguments dropped — and what an
  // arriving address names is core's answer too: this glue splits no
  // path and joins no separator.
  //
  // **Secrets never rest in the bar or in history**, and history is
  // written to disk for session restore, `state` included. So an entry
  // holds a key and nothing else, and the whole reference behind it —
  // secrets and all — is held here, in memory, for this page's life:
  // Back and Forward within it restore the screen whole, and after a
  // reload the map is empty, the entry is read as the address it shows,
  // and the screen is entered without its secrets and says what it
  // needs. The key carries the page life's origin so that an entry from
  // before a reload can never name one kept after it.
  const life = String(performance.timeOrigin);
  const kept = new Map();
  let entries = 0;
  let shown = "";
  const current = () => read(nk.nokre_dom_address(), nk.nokre_dom_address_len());

  function syncAddressBar() {
    const ref = read(nk.nokre_dom_route(), nk.nokre_dom_route_len());
    if (ref === shown) return;
    const first = shown === "";
    shown = ref;
    // Where a screen is a document, a route change *is* a navigation:
    // the reader is owed the file for that screen, not this file
    // wearing its name. Nothing to do on the first frame — the screen
    // the router just landed on is the one this document already is —
    // and the href comes from the app's own RefResolver, so the bar and the
    // links in the page cannot disagree about where a screen lives.
    if (documents) {
      if (first) return;
      location.assign(read(nk.nokre_dom_href(put(ref)), nk.nokre_dom_href_len()));
      return;
    }
    // A pushed screen adds a history entry and nothing else does: a
    // section switch and a `replace` are the router saying *this is the
    // same place*. Which of those it was is the router's answer, not a
    // guess from here — browser Back and the in-app Back control are
    // the same motion, deliberately, and they only stay the same if the
    // entries match.
    const push = MOTION[nk.nokre_dom_route_motion()] === "push";
    const key = `${life}:${++entries}`;
    kept.set(key, ref);
    history[push ? "pushState" : "replaceState"]({ nokre: key }, "", current());
  }

  // The address the bar holds now, as core reads it: the path, and the
  // fragment without its `#`, in one scratch. `atLoad` is the page
  // load's own arrival, right after the build (`address.When`).
  function arrive(atLoad) {
    const path = bytes.encode(location.pathname);
    const fragment = bytes.encode(location.hash.slice(1));
    const ptr = nk.nokre_dom_scratch(path.length + fragment.length);
    if (!ptr) return 0;
    memory().set(path, ptr);
    memory().set(fragment, ptr + path.length);
    return nk.nokre_dom_arrive(path.length, fragment.length, atLoad ? 1 : 0);
  }

  // ---- events -----------------------------------------------------

  // Nothing activates on the way down. The press is recorded, focus
  // moves to what is under it, and the release decides — which is
  // core's rule (WCAG 2.5.2) and also, conveniently, what `click`
  // already means in a browser.
  listen("click", (e) => {
    // The scrim is the layer saying the rest of the tree is inert, and
    // pressing it means what Esc means: dismiss the layer. It carries
    // no node of its own, so it is the one press resolved by class
    // rather than by id — and it goes through the same key core
    // already handles rather than a second way to close things.
    if (e.target.classList.contains("scrim")) {
      nk.nokre_dom_key(KEY_BY_CODE.Escape, 0);
      frame();
      return;
    }
    // Where a screen is a document, a link is the browser's: it has a
    // file behind it, and letting the router answer instead would take
    // the one navigation a reader can middle-click, copy, open in a tab
    // and come Back from, and turn it into a redraw. It also settles
    // the destinations core has no opinion about — a heading on this
    // page, a source file on someone else's host — which are legal
    // hrefs and not routes at all, so nothing would have happened.
    if (documents && e.target.closest("a[href]")) return;
    // An external link is the browser's on every driver, for the same
    // reasons: it carries a real href (target _blank, noopener —
    // serialize.zig), and re-opening it through the open_url service
    // would drop the reader's modifier keys — their middle click, their
    // "open in new window". Route links carry the screen's address and
    // stay the router's; keyboard activation of an external link still
    // crosses into core and reaches the service (services.js).
    {
      const anchor = e.target.closest("a[href]");
      if (anchor && anchor.getAttribute("target") === "_blank") return;
    }
    // An exclusive choice is resolved on the chip, which is the whole
    // label — checked *first*, because the label is an ancestor of the
    // control and `closest` would otherwise find the control and let
    // the browser act on the label before this ever ran.
    const chip = e.target.closest("[data-i]");
    if (chip) {
      // And cancelled here, not later: the tree owns the selection, so
      // the browser must not also apply one. Cancelling a radio's
      // activation after the fact reverts it, which is how a control
      // ends up showing one answer while the tree holds another.
      e.preventDefault();
      nk.nokre_dom_select(Number(chip.dataset.n), Number(chip.dataset.i));
      frame();
      return;
    }
    const stop = e.target.closest("[data-n]");
    if (!stop) return;
    // A link is a real link: it has an href a reader can copy, and the
    // navigation belongs to the router rather than to a page load.
    e.preventDefault();
    // One call. A press moves focus *and* activates, and both are one
    // input — two calls would be two inputs, and every rule an input
    // carries would run twice.
    nk.nokre_dom_press(Number(stop.dataset.n), stop.dataset.s === undefined ? -1 : Number(stop.dataset.s));
    // And then where in the field it landed, which the press could not
    // carry. Activating a field means placing the caret, and core puts
    // it at the value's end because the road a semantic press takes has
    // no coordinate on it (`input.activate`) — the shells that have one
    // place it themselves. Here the browser has already placed it, on
    // the mousedown that started this, so what it placed is stated
    // rather than recomputed: a click mid-value keeps its caret, a drag
    // that ended in this click keeps the range it drew, and a repeated
    // click keeps the larger unit the engine took — which is why this
    // substrate counts no clicks of its own (live.zig's `selectRange`).
    const field = editableOf(stop);
    if (field) sendSelection(field);
    frame();
  });

  // ---- the dial's turning stream -----------------------------------
  //
  // The rule is docs/elements.md's, `dial`: **a gesture belongs to
  // whatever it started on**, and a wheel, which starts on nothing,
  // belongs to a dial only while that dial is focused. It is written
  // here a second time because a browser's wheel and pointer events
  // are not core's scroll stream and never reach it — the page is the
  // browser's to scroll, so nothing crosses into wasm that core could
  // have routed. What core does keep is the quantum: raw travel goes
  // over, detents come back, and this file never learns how tall a
  // plate is.
  //
  // The two streams are separate because their ends are: a pointer
  // says when it let go, and a wheel has to be waited out.
  const DIAL_IDLE_MS = 150;
  // `{ node }` once the first tick of a wheel stream has decided whose
  // it is, where `node` is null for the page's. Null between streams.
  let wheelStream = null;
  let wheelIdle = 0;
  let dragDial = null; // { node, at } while a finger holds the column

  function dialUnder(target) {
    const device = target instanceof Element ? target.closest("[data-dial]") : null;
    return device ? Number(device.dataset.dial) : null;
  }

  function turnDial(node, travel) {
    nk.nokre_dom_dial(node, Math.round(travel), 0);
    frame();
  }

  function endDial(node) {
    // The close spends whatever travel never made up a detent, so the
    // next stream starts from zero rather than inheriting a push the
    // reader has forgotten making.
    nk.nokre_dom_dial(node, 0, 1);
  }

  function endWheelStream() {
    if (wheelStream && wheelStream.node !== null) endDial(wheelStream.node);
    wheelStream = null;
  }

  // On the **document**, not on the mount roots, and not passive. A
  // stream that opens on a part of the page this driver did not write —
  // the host's own header, the margin beside the column — is still a
  // stream, and one that never reached a listener would leave the next
  // tick free to open a dial's mid-scroll. Engines make a wheel
  // listener passive by default at this level and only at this level,
  // so `preventDefault` has to be asked for.
  doc.addEventListener("wheel", (e) => {
    // **Resolved once**, on the tick that opens the stream, and kept
    // until the gap closes it — the page's ticks marked as the page's
    // exactly as a dial's are marked as the dial's. Both halves
    // matter, because the pointer does not travel under a wheel: the
    // content travels under a stationary pointer. Without the first, a
    // dial scrolling up into that pointer takes over a scroll already
    // under way; without the second, a reader standing on a dial can
    // never scroll the page past it.
    if (!wheelStream) {
      const node = dialUnder(e.target);
      // A wheel belongs to no gesture, so focus is what names the
      // owner — the fix browsers themselves landed on for
      // `<input type=number>`, and the rule core holds for a free tick.
      const focused = node !== null && nk.nokre_dom_focused_node() === node;
      wheelStream = { node: focused ? node : null };
    }
    // The gap is the browser's, not core's: core has no clock, and a
    // wheel is the one stream whose end nothing announces. Restarted on
    // every tick, the page's included, so a long page scroll does not
    // fall out of its own stream halfway down a dial.
    clearTimeout(wheelIdle);
    wheelIdle = setTimeout(endWheelStream, DIAL_IDLE_MS);
    if (wheelStream.node === null) return;
    e.preventDefault();
    turnDial(wheelStream.node, e.deltaY);
  }, { passive: false });

  doc.addEventListener("pointerdown", (e) => {
    // The column only. A drag that begins on a step button is that
    // button's press — the browser will deliver its click — and a
    // device that turned under the finger *and* stepped on release
    // would move twice for one gesture.
    if (!e.target.closest?.(".dial-plates")) return;
    const node = dialUnder(e.target);
    if (node === null) return;
    dragDial = { node, at: e.clientY };
    // The pointer is captured so a finger that leaves the column keeps
    // turning it, which is the same sentence as the lock core holds
    // across a bracket's moves.
    e.target.setPointerCapture?.(e.pointerId);
  });

  doc.addEventListener("pointermove", (e) => {
    if (!dragDial) return;
    // Content follows the finger: a finger moving up raises the
    // travel, and a positive travel turns the value down, because what
    // is below the current plate is one less (the shells' own sign).
    const travel = dragDial.at - e.clientY;
    dragDial.at = e.clientY;
    turnDial(dragDial.node, travel);
  });

  // Both endings, for the reason the editable drag above states: a
  // pointer released outside the window still ends this drag, and a
  // recognizer that loses it sends `pointercancel` and nothing else.
  for (const ending of ["pointerup", "pointercancel"]) {
    doc.addEventListener(ending, () => {
      if (!dragDial) return;
      endDial(dragDial.node);
      dragDial = null;
    });
  }

  // ---- a scroll names its desk region -------------------------------
  //
  // On a canvas a scroll's start names the band region it began in
  // (docs/routing.md, "The region a desk shows"); here the browser
  // scrolls and core never sees it, so the start is reported. In the
  // capture phase because `scroll` does not bubble: a region's inner
  // scroller is seen on its way down. The page's own scroll targets the
  // document, which is in no region. Once per burst, closed by the gap
  // a wheel's is, and again whenever the burst moves to another region.
  const REGION = ".region";
  let scrolledRegion = null;
  let regionScrollIdle = 0;
  doc.addEventListener("scroll", (e) => {
    const region = e.target.closest?.(REGION);
    if (!region || region.dataset.n === undefined) return;
    clearTimeout(regionScrollIdle);
    regionScrollIdle = setTimeout(() => { scrolledRegion = null; }, DIAL_IDLE_MS);
    if (region === scrolledRegion) return;
    scrolledRegion = region;
    nk.nokre_dom_region_scrolled(Number(region.dataset.n));
    frame();
  }, { capture: true, passive: true });

  // Tabbing is the browser's: the markup is the tree, so document
  // order already *is* focus order. What crosses back into wasm is
  // where it landed.
  listen("focusin", (e) => {
    const stop = e.target.closest("[data-n]");
    if (!stop) return;
    if (stop.dataset.i !== undefined && stop !== e.target) return; // the chip, not its control
    nk.nokre_dom_focus(
      Number(stop.dataset.n),
      stop.dataset.s === undefined ? -1 : Number(stop.dataset.s),
    );
  });

  // Tab included, deliberately. Leaving it to the browser looks like
  // delegation and is really a rule going missing: core's traversal
  // knows the focus *scope* — an open sheet or picker holds focus
  // inside it, and the page behind a scrim is inert — and it knows to
  // skip the nav while a banner owns the bottom pane. A browser knows
  // neither, and would tab straight out of a modal layer.
  listen("keydown", (e) => {
    // Mid-composition every key is the IME's — Enter takes a candidate,
    // Escape dismisses the preedit — and forwarding one would run it
    // twice, once in the IME and once in core. The old canvas glue kept
    // this same silence.
    if (composing || e.isComposing) return;
    // A chord is claimed **only inside a field**, and that is the whole
    // of where an editing command means anything: outside one ⌘A, ⌘C
    // and ⌘Z are the reader's own — select the page, copy it, undo a
    // form the host document wrote — and page-wide selection is on the
    // list of what this substrate traded pixel goldens for. Cancelling
    // them everywhere would take it back.
    const editable = e.target.matches(EDITABLE);
    const key = (editable ? chordKey(e) : undefined) ?? KEY_BY_CODE[e.key];
    if (key === undefined) return;
    // Where a screen is a document, a link is the browser's on the
    // keyboard exactly as it is under a press — the click handler above
    // states the reasons and they are the same reasons. The two have to
    // agree: a press that hands the reader their file beside a keystroke
    // that hands core a destination the route table cannot spell — a
    // locale's copy of this page, a heading, a file on someone else's
    // host — is a link that works with a pointer and does nothing at all
    // with a keyboard, which is WCAG 2.1.1 Keyboard, level A. A footer's
    // language chooser is exactly that destination on a real site.
    //
    // Enter alone, because Enter is the one key an anchor activates on
    // in a browser. Space stays core's: a browser does not activate a
    // link with it, so returning here would not navigate — it would only
    // take the activation away from the destinations core *can* honor.
    // The reader's modifiers ride along, the click handler's point:
    // Ctrl+Enter is "open in a new tab", which core has no way to mean.
    if (documents && e.key === "Enter" && e.target.closest("a[href]")) return;
    // Inside a field the arrows and Home/End are the caret's, and
    // `editing.zig` is what moves it — so they go through like any
    // other key. Space in a field is text, not activation.
    if (editable && e.key === " ") return;
    // A scrolling table's and a code block's ←/→ are the browser's:
    // scrolling is the browser's here, and the wrap and the `pre` are
    // real scroll containers. Core's answer to the same keys is the
    // raster's sideways scroll, which this substrate has no offset for.
    if ((e.key === "ArrowLeft" || e.key === "ArrowRight") && e.target.matches?.(".table-wrap, pre.code")) return;
    e.preventDefault();
    // Every key below acts on a *range* when there is one — Backspace
    // deletes it, a plain arrow collapses onto the end it points at,
    // cut carries it off — so core is told what the reader has selected
    // before it is asked to act on it. The reader may have made that
    // selection with a drag, a double-click or a ⌘A this driver never
    // saw (`sendSelection`).
    if (editable) sendSelection(e.target);
    nk.nokre_dom_key(key, mods(e));
    frame();
  });

  // Typing edits the tree, and the tree is what the field then shows.
  // `beforeinput` is where that is possible: the DOM's own edit is
  // refused, the bytes go to core, and the re-render puts back a value
  // core decided on.
  listen("beforeinput", (e) => {
    if (!e.target.matches("input, textarea")) return;
    // A composition's own edits ride the IME lane below, never this
    // one. COMPOSITION_INPUTS says why the refusal still applies.
    if (COMPOSITION_INPUTS.has(e.inputType)) {
      e.preventDefault();
      return;
    }
    if (composing || e.isComposing) return;
    e.preventDefault();
    // What the edit is *about*. Every arm below either replaces the
    // selection or deletes it, and the reader made it in the browser —
    // dragging in a real field, double-clicking a word, ⌘A — so core's
    // copy of it is only as fresh as this call. Before the edit and not
    // after: an insertion replaces the range it was told about
    // (`editing.insertText`), and one told about nothing appends.
    sendSelection(e.target);
    if (e.inputType === "insertText" && e.data) {
      nk.nokre_dom_text(put(e.data));
    } else if (e.inputType === "insertFromPaste" || e.inputType === "insertFromDrop") {
      // Paste carries its text on `data` in some engines and on the
      // dataTransfer in others; a drop always on the dataTransfer.
      // Either way it enters the tree as typed text — core owns what a
      // field holds, however the bytes arrived.
      const data = e.data ?? e.dataTransfer?.getData("text/plain");
      if (!data) return;
      nk.nokre_dom_text(put(data));
    } else if (e.inputType === "deleteContentBackward" || e.inputType === "deleteByCut") {
      // A cut's clipboard write already happened, on the browser's own
      // `cut` — the one half of a cut this driver does not touch, so
      // the reader gets the flavours, the permission and the gesture a
      // real field has. What is owed here is the deletion, and it is
      // the *selection* the browser just carried off: the call above
      // stated it, and Backspace over a range deletes exactly that
      // range (`editing.editKey`).
      nk.nokre_dom_key(KEY_BY_CODE.Backspace, 0);
    } else if (e.inputType === "deleteContentForward") {
      nk.nokre_dom_key(KEY_BY_CODE.Delete, 0);
    } else if (e.inputType === "historyUndo" || e.inputType === "historyRedo") {
      // A field's history is core's now (`App.edit_history`), so these
      // are the two keys rather than nothing: the browser's own undo
      // stack was emptied by every `preventDefault` above it and would
      // step back to a value nobody typed. They arrive here from the
      // edit menu and the trackpad gesture; the chord itself is claimed
      // a lane earlier, in `chordKey`.
      nk.nokre_dom_key(KEY_BY_CODE[e.inputType === "historyUndo" ? "undo" : "redo"], 0);
    } else {
      // Deliberately unhandled: a formatting input cannot apply to a
      // plain field. preventDefault above has already refused the DOM's
      // own edit.
      return;
    }
    frame();
  });

  // ---- IME --------------------------------------------------------

  // Composition is the browser's while it lasts and the tree's when it
  // resolves. The preedit lives in the real field — the native IME a
  // real field buys is on the list of what this substrate traded pixel
  // goldens for — so an open session owns that field outright: its keys
  // are not forwarded, its edits are not refused, and a frame that
  // lands mid-session leaves its value and caret alone (the patchNode
  // and restoreFocus guards). What crosses into core is the same three
  // legs every shell sends: the preedit streams as updates so the
  // tree's `composition` is true on this platform too, and the session
  // ends as a commit or — empty, the reading every shell gives the
  // same silence — a cancel.
  let composing = false;

  listen("compositionstart", (e) => {
    if (!e.target.matches("input, textarea")) return;
    composing = true;
  });

  listen("compositionupdate", (e) => {
    if (!composing) return;
    // The cursor rides at the preedit's end. Core draws the caret
    // wherever this says (platform-shells.md, "IME"), and every native
    // shell reports its engine's own offset — but `compositionupdate`
    // carries no caret, and the field composing the preedit is the
    // browser's own, so the end is both the only answer available here
    // and the right one for a caret nobody moved.
    const len = put(e.data || "");
    nk.nokre_dom_ime_update(len, len);
    // The frame is nearly free — the markup carries the value without
    // the preedit, so its bytes usually have not moved — and it keeps
    // the invariant that every event lands one.
    frame();
  });

  listen("compositionend", (e) => {
    if (!composing) return;
    composing = false;
    const text = e.data || "";
    if (text) nk.nokre_dom_ime_commit(put(text));
    else nk.nokre_dom_ime_cancel();
    frame();
  });

  function mods(e) {
    return (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
  }

  // The browser's Back and Forward, and a fragment the reader typed.
  // An entry this page life wrote is entered whole, from what was kept
  // for it; any other is read as the address it shows. The browser's
  // Back and the in-app Back are the same motion, deliberately. An
  // address that names no screen leaves the app where it is and the bar
  // goes back to it — so it never describes a screen nobody is on.
  addEventListener("popstate", (e) => {
    // Not this lane's, where a screen is a document: a fragment there
    // names a heading on the page the reader is already on, and the
    // browser is the only thing that should act on it.
    if (documents) return;
    const whole = kept.get(e.state?.nokre);
    if (whole === shown) return;
    const entered = whole === undefined ? arrive(false) : nk.nokre_dom_navigate(put(whole));
    if (!entered) {
      // The entry now shows the screen the reader is still on, so it
      // keeps that screen whole too.
      const key = `${life}:${++entries}`;
      kept.set(key, shown);
      history.replaceState({ nokre: key }, "", current());
      return;
    }
    frame();
  });

  // Layout is core's, so a resize is a relayout — and on this substrate
  // it is also what re-asks every measured decision, the nav's shape
  // among them.
  //
  // The width is the container's, not the window's — the element the
  // *screen* is in, and where the host owns that element, the chrome's
  // own container is not it. A host page may hold the screen to a
  // readable column (the one nokre ships does), and core measuring
  // against the window instead would decide against a width nobody is
  // looking at: prose wrapped somewhere else, a row of actions that had
  // room to spare and so never folded its tail, a track that fitted in
  // a column it overflows. The height stays the window's, because that
  // is what "how much is visible" means and what a scroll region
  // resolves against.
  function remeasure() {
    if (!nk) return; // the faces beat the module; boot reports it itself
    nk.nokre_dom_resize(screen.clientWidth, innerHeight);
    // The window moved every plate's light, whether or not a byte did.
    lampDirty = true;
    frame();
  }

  addEventListener("resize", remeasure);

  // ---- boot -------------------------------------------------------

  // The tag, strictly before boot: a locale read inside the first
  // build has to answer synchronously (services/locale/web.zig owns the
  // seed exports; this is the shell half that calls them).
  //
  // Two sources, and the *page's* outranks the device's.
  // `navigator.language` is the only evidence an app booting into an
  // empty body has, and it stays the answer there. It is the wrong
  // answer over a page a generator already wrote: that page is the
  // app's first frame and it is in one language, while hydration
  // matches nodes by tag and position and never by text — so an app
  // that boots in another language swaps every string, mirrors the
  // layout back, and reports nothing at all (dom-substrate.md, "The
  // page's locale, not the reader's").
  if (nk.nokre_locale_seed) {
    // A page that pins the *empty* tag is a real page and not an absent
    // option: it is the document of an app that chose no locale, whose
    // catalog therefore resolved to its own template, and reproducing
    // that is exactly the job. `undefined` is the only "nobody said".
    const pinned = typeof locale === "string";
    const tag = bytes.encode(pinned ? locale : navigator.language || "");
    const ptr = nk.nokre_locale_scratch(tag.length);
    if (ptr) {
      memory().set(tag, ptr);
      nk.nokre_locale_seed(tag.length);
    }
    // Every change after boot, on the same lane — and only where the
    // device is what the app was following. A pinned page keeps its
    // language when the reader changes their browser's: the URL is the
    // language there, and one URL that shows two languages is the thing
    // per-locale pages exist to prevent.
    if (!pinned) {
      addEventListener("languagechange", () => {
        const t = bytes.encode(navigator.language || "");
        const p = nk.nokre_locale_scratch(t.length);
        if (!p) return;
        memory().set(t, p);
        nk.nokre_locale_receive(p, t.length);
        frame();
      });
    }
  }

  // The stored secrets, strictly before boot for the locale's reason:
  // a boot-time `get` inside the first build answers synchronously
  // (services/secure_store/web.zig owns the seed exports; services.js
  // owns the sessionStorage schema, so the scan lives beside the
  // mirror it feeds).
  seedStores(nk, memory);

  // The oauth redirect: this page's own address, without query or
  // fragment — the provider appends its own. Seeded before boot like
  // the locale, because `oauth.redirectUri` is called inside an action
  // and answers synchronously. A null scratch is an over-cap URL,
  // seeded as nothing so the first sign-in fails loudly rather than
  // sending a truncated redirect (services/oauth/web.zig).
  if (nk.nokre_oauth_seed_scratch) {
    const rb = bytes.encode(location.origin + location.pathname);
    const ptr = nk.nokre_oauth_seed_scratch(rb.length);
    if (ptr) {
      memory().set(rb, ptr);
      nk.nokre_oauth_seed_redirect(rb.length);
    }
  }

  // The host page's own bytes, on the locale's lane and for the locale's
  // reason: whatever the app makes of them, it makes inside the first
  // `build`, so they cannot arrive after it. A page generated from a
  // document hands over that document.
  if (seeding) nk.nokre_dom_seed(put(await seeding));

  // The screen this document is, as a boot argument rather than a
  // navigation after the fact: the file already shows it, and switching
  // afterwards would build and paint some other screen on the way past.
  if (!nk.nokre_dom_boot(screen.clientWidth, innerHeight, route ? put(route) : 0)) {
    throw new Error("nokre: the module exports no nokreWebBuild");
  }
  // After boot rather than before it, unlike the locale: an appearance
  // is read at paint and the first frame has not run yet, while a
  // locale is read inside the first `build` (services/locale/web.zig
  // says so at length).
  nk.nokre_dom_system_appearance(dark.matches ? 1 : 0);
  nk.nokre_dom_system_contrast(moreContrast.matches ? 1 : 0);
  nk.nokre_dom_system_transparency(lessTransparency.matches ? 1 : 0);
  nk.nokre_dom_system_reduce_motion(lessMotion.matches ? 1 : 0);
  // Whether the reader can see the page, at boot and on every change:
  // the boot report is what makes a tab opened behind another still
  // launching when it is first shown, and a page hidden and shown again
  // the app's return (core/foreground.zig).
  const pageShown = () => (doc.visibilityState === "hidden" ? 0 : 1);
  nk.nokre_dom_foreground(pageShown());
  doc.addEventListener("visibilitychange", () => {
    nk.nokre_dom_foreground(pageShown());
    frame();
  });
  // The notification service's worker, and the cold-start tap it may
  // have carried. Registration is after boot deliberately — it is
  // asynchronous either way, and nothing in the first `build` can wait
  // on it: the boot probes read `Notification.permission`, which the
  // page answers without a worker (docs/internals/notifications.md).
  registerServiceWorker();
  {
    // A tap with no page open opens one, and the only thing sw.js can
    // hand a page that does not exist yet is its URL. Delivered as a tap
    // once, then stripped from the address bar so a reload is not a
    // second tap — the route the app navigates to is what stays there.
    const q = new URLSearchParams(location.search);
    const tapped = q.get("nokre.id");
    if (tapped && nk.nokre_notification_scratch) {
      const ib = bytes.encode(tapped);
      const rb = bytes.encode(q.get("nokre.route") || "");
      const ptr = nk.nokre_notification_scratch(ib.length + rb.length);
      if (ptr) {
        memory().set(ib, ptr);
        memory().set(rb, ptr + ib.length);
        nk.nokre_notification_receive(1, 1, ib.length, rb.length);
      }
      q.delete("nokre.id");
      q.delete("nokre.route");
      const rest = q.toString();
      history.replaceState(null, "", location.pathname + (rest ? "?" + rest : "") + location.hash);
    }
  }

  // The address the page was loaded at. An arrival that names no screen,
  // or only the front (`/`), leaves the app where its build put it, and
  // the first frame writes that screen's address over it; one that
  // does is written back without its secrets. A page that states the
  // screen it is (`route`, above) was written for that screen, and its
  // own statement outranks the address it was served at.
  if (!documents && !route) arrive(true);
  frame();
  return nk;
}
