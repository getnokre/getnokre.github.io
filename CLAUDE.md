# getnokre.github.io

The site is a nokre app that renders itself to HTML. [README.md](README.md)
is the manual: build commands, the `-Drepo` caveat, what the build refuses
to publish, the URL scheme, the file layout, publishing. Read it first —
what follows is only what it does not say.

## `docs/` is output, not source

`docs/**` is written by `zig build site` and committed because GitHub Pages
serves that folder straight from the branch. **Never hand-edit anything
under `docs/`** — not the HTML, not `style.css`, not `md/`, not the
driver's `.js`, not `sitemap.xml`. The next build overwrites it, and until
then the committed tree misstates what the generator produces. A wrong page
is fixed in `src/` and rebuilt.

## The comment standard is nokre's

`../nokre/docs/internals/contributing.md`, "Comments" — its five checks
govern the Zig here too, and this repository keeps no copy of them. Cite
that page; do not transcribe it. The defect it is written against is the
one this repository actually grows: comments that were true once.

## After a change

```sh
zig fmt src/ build.zig     # build.zig is source here, not just src/
zig build test
zig build site
git diff --stat docs
```

Reading that diff is the review, not a formality — README's "Publishing"
says why there is nothing else.

## Emitted bytes are the contract

The generator is deterministic, so every line that moves in `docs/` is
something a change caused, and you should be able to name the cause of each
file in the diff before committing. Two traps:

- **`../nokre` must be clean before you build.** A dirty tree there stamps
  `(with uncommitted changes)` into the colophon *and* into `app.wasm` —
  both read the same options module — so the diff grows entries that are
  about your checkout rather than about the site, and the real changes hide
  behind them.
- A comment-only edit in `src/` should move **no** `docs/` bytes at all. If
  a page's prose changes, you edited emitted content: `content.zig`'s
  builders carry page text in string literals, and a comment beside one is
  not the same thing. Check which you are in before you type.

## One home, across two repositories

Facts about the library live in `../nokre/docs/` and are pointed at from
here, never restated — a second copy is a future contradiction, and the two
will not drift together. Counts especially: this repository has shipped a
page count in four places at once and a shell count that contradicted the
page it cited in the same comment. If a sentence here wants a number about
nokre, cite the page that owns it, or say what is true without the figure.
