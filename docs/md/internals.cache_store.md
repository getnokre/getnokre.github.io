# The cache_store service

How the kept-copy contract in [../services.md](../services.md) is wired.
The policy layer is
[src/services/cache_store/cache_store.zig](../../src/services/cache_store/cache_store.zig)
— key validation, the value cap, the one-shot delivery, comptime
dispatch, and the per-app test fake.
[native.zig](../../src/services/cache_store/native.zig) declares the
externs of [cache_store.h](../../src/services/cache_store/cache_store.h)
and runs each verb on its own thread; the file verbs are one
implementation, [posix.c](../../src/services/cache_store/posix.c), for
macOS, iOS, Android and desktop Linux, with the cache directory found by
[apple.m](../../src/services/cache_store/apple.m),
[android.c](../../src/services/cache_store/android.c) (over JNI from
[NokreCacheStore.java](../../src/platform/android/java/dev/nokre/shell/NokreCacheStore.java))
and [linux.c](../../src/services/cache_store/linux.c);
[windows.c](../../src/services/cache_store/windows.c) is the verbs over
Win32 in one file. On wasm, [web.zig](../../src/services/cache_store/web.zig)
ferries each verb to IndexedDB through
[services.js](../../src/render/dom/services.js) and lands the answer
through exports in [live.zig](../../src/render/dom/live.zig). The
contract tests are
[cache_store_test.zig](../../src/services/cache_store/cache_store_test.zig);
the one gate that runs the real verbs against a directory the OS
answers is [tests/cache_store.zig](../../tests/cache_store.zig).

## Why a third store

`secure_store` and `roaming_store` are pouches: a value is at most 2560
bytes, because Windows' credential blob is, and a read is one
synchronous call inside `build`, because a secret decides the first
screen. A document an app fetched and wants to find again at the next
launch — an exhibit's recordings, a catalog, a page of legal text —
fits neither cap, and reading megabytes inside `build` would hold the
frame it is deciding. `std.fs` is not the answer either (services.md,
"Not services"): the web has no filesystem, and the point of a service
is one contract on six platforms with a mock under `zig test`.

So the store is asynchronous, in http's shape exactly: a verb from any
action, the arguments copied before it returns, and one `Result` back on
the UI thread between events, through a one-shot delivery slot
(`workers.openOneShotTagged`) carrying the caller's `ctx` and `tag`.
No verb blocks the UI thread and no callback runs off it. A `Handle`
cancels like http's.

## The contract

Three verbs, each with its own options struct of `app`, `key`, (`value`),
`ctx`, `tag`, `on_result`:

- `get` answers `GetResult`: `value: Bytes` (take it to keep it),
  `absent`, or `failure: Failure`.
- `set` and `delete` answer `WriteResult`: `done` or `failure: Failure`.

The issue-time error sets are closed and the same on every target:
`GetError = error{ InvalidKey, OutOfMemory, Unavailable }`, `SetError`
adds `ValueTooLarge`, `DeleteError` equals `GetError`. `InvalidKey` and
`ValueTooLarge` are pure functions of the arguments and the caps,
decided in Zig before any leg is asked; `Unavailable` at issue means the
transport could not start (a thread would not spawn). The one failure
name delivered is `"Unavailable"`: the directory could not be made, the
file not read or written, the browser refused IndexedDB. One name,
because the consumer's only move is the same every time — go back to
the source.

The caps: `max_key_bytes = 128` in secure_store's charset
(`secure_store.validKey`, one home — a key is a file name as it stands on
every platform, and the charset is what makes that true), and
`max_value_bytes = 64 MiB`, `nokre-serve`'s own `max_file_bytes`: the
largest file nokre's serve answers is the largest body an exhibit fetches,
so one fetched body always fits as one value. There is no entry cap and
no `list`: a store of documents is bounded by the consumer's key set,
which the consumer knows, and eviction is the consumer's call, by
`delete`.

The posture, stated: **a copy the device may lose.** Every leg writes
where the OS is allowed to purge — Caches on Apple, `getCacheDir()` on
Android, `$XDG_CACHE_HOME` on Linux, `%LOCALAPPDATA%` on Windows,
IndexedDB under storage pressure — so `absent` is data the consumer
always handles by going to the source, and nothing an app cannot fetch
again belongs here.

Linking is secure_store's: `.cache_store = true` requires `.pkg`, since
the id is the store's namespace; the options module
`nokre_cache_store_options` carries `linked` and `namespace`, and an
unlinked call site is a curated comptime error. The directory is
`<cache dir>/nokre.cs.<pkg_id>`, the web key prefix `nokre.cs.<pkg_id>/`
— `/` is outside both the charset and reverse-DNS ids, so namespaces
never alias, as secure_store's `nokre.ss.` already argues. Packaging
footprint: nothing, anywhere — a cache directory is handed to every app
unasked.

## The native legs

`native.zig` keeps the one piece of per-app release state the service
has, whether `nokre_cs_ready` has run: the first verb on an App calls it
on the UI thread with the namespace, and it finds the platform's cache
directory, makes `nokre.cs.<ns>` under it, and remembers the path.
Android's lookup of `getCacheDir()` is the reason it is a separate call
on the main thread: `FindClass` resolves an app class only through the
main thread's env, and the verbs run on other threads.

Each verb copies its arguments into a gpa-owned job, spawns one detached
`std.Thread` that calls the C verb and delivers through the slot
(`workers.deliverOneShot`), and frees the job on the way out — http's
transport without the watchdog, because a file read has no deadline to
hold. A get hands the stored length to Zig through the `alloc` callback
in the header, which allocates exactly that many bytes from the app's
gpa, refuses above the cap, and the C side reads straight into them:
one allocation, no copy, `Bytes.adopt` at delivery. The file stays open
from the size to the read, so a set racing it on another thread is seen
whole or not at all.

A set is atomic per value: the bytes go to a temporary name in the same
directory, beginning with a byte outside the key charset so no key can
alias it, and are renamed over the key. A reader finds the old value or
the new one, never a half-written file. The temporary's name carries the
process id and a serial, so two sets of one key on two verb threads
never share a file; a crash leaves at most stray temporaries, and
`ready` sweeps every `~`-named entry out of the directory at the next
launch, before answering. Deleting an absent key is `OK`.

Which file compiles where (`build.zig`, `addCacheStore`): `posix.c` and
`apple.m` for macOS and iOS on a macOS host (Foundation for
`NSSearchPathForDirectoriesInDomains`); `windows.c` with libc for
Windows from any host; `posix.c` and `linux.c` for desktop Linux from any
host, since both are plain libc, so `check-targets` analyzes them
everywhere; Android compiles `posix.c` and `android.c` in the consumer's
CMake beside the shell, like every service's android.c, so the three
Gradle projects nokre carries (the kitchen sink's, the support console's
and `src/exhibit/android`) name both. The Java half,
`NokreCacheStore.java`, is attached by `NokreActivity` beside
`NokreSecureStore` and keeps the cache directory's absolute path for
`android.c` to read once in `ready`.

## The web leg

IndexedDB, and not the Cache API or OPFS: an exhibit on a phone is served
over plain http from another machine on the local network, which is no
secure context, and only IndexedDB answers there. Database `nokre.cs`,
version 1, one object store `entries` keyed by the full string
`nokre.cs.<pkg_id>/<key>`, values as `ArrayBuffer`. `web.zig` hands each
verb out through `nokre_cs_js_get`, `nokre_cs_js_set` and
`nokre_cs_js_delete` on the import object (`index`, `gen`, the key, and
for set the value — copied synchronously inside the call, as every
borrow ends when the import returns), and the answer lands through
`nokre_cs_scratch(len)` and `nokre_cs_deliver(index, gen, kind, len)`:
kind 0 is a value whose bytes are in the scratch, 1 absent, 2 done, 3 a
failure whose name is in the scratch — the three beats of http's
landing, then the shared delivery queue and an inline pump. Exported only
when linked. A browser that refuses IndexedDB (a private window, a
blocked origin) answers every verb with the failure `"Unavailable"`: the
one leg where a write can refuse, stated rather than hidden.

The node gate (`tests/web_services.mjs` over `tests/web_browser.mjs`)
carries a small in-memory `indexedDB` so the real web leg runs under
`zig build test`: absent, set, value, delete, absent again, and the
refused path with the fake withheld.

## The mock

`Mock.mock(.{ .seeds, .available })` and a `MockState` on the heap, as
every stateful service's: owned entries, a journal of `get`, `set` (with
the value) and `delete` in call order, and the knobs `available`,
`fail_writes` and `fail_next`. A verb validates and caps in Zig, journals,
then queues its delivery through the slot at the call, so it lands at
the next pump — no settle step, because a store answers from the device
and the test's interleaving is the pump. The harness maps the config
(`InitOptions.cache_store`) and exposes the state
(`HarnessApp.cache_store`), so a test seeds a kept document and asserts
the app never asked the network for it.

## The gate that runs the real verbs

`tests/cache_store.zig` is built as an executable and run under
`zig build test` on a native desktop host, as `tests/dev_store.zig` is:
the one place the platform leg's files, threads and delivery are in a
room together. Namespace `dev.nokre.cachestore`; it sets, gets, replaces,
deletes and reads the absence back, refuses a key outside the charset
and a value above the cap at issue, and leaves nothing behind. It writes
under the host's own cache directory and never near a keychain.
