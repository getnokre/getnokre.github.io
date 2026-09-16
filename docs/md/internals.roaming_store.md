# The roaming_store service

How the second pouch in [../services.md](../services.md) is wired.
Landed 2026-09-15.

It is [secure_store](secure_store.md)'s contract with the opposite
posture, and this file says only what differs. The caps, the key
charset, the buffers, the error names, the sort order and the fake are
**imported from secure_store, not copied** — `roaming_store.ValueBuf`
*is* `secure_store.ValueBuf`, and a test asserts the type equality — so
there is one home for the pouch contract and no way for the two stores
to drift into two meanings of `ValueTooLarge`.

The policy layer is
[roaming_store.zig](../../src/services/roaming_store/roaming_store.zig).
[native.zig](../../src/services/roaming_store/native.zig) declares four
`nokre_rs_*` externs — secure_store.h's contract under a second prefix,
so one binary can carry both stores. Four of the six backends behind
them are **secure_store's own sources**, reached by a four-line shim
that redefines `NOKRE_STORE_FN` and includes the implementation:
[windows.c](../../src/services/roaming_store/windows.c),
[linux.c](../../src/services/roaming_store/linux.c),
[android.c](../../src/services/roaming_store/android.c) (which also
redefines `NOKRE_STORE_JAVA_CLASS`) and
[dev.c](../../src/services/roaming_store/dev.c) (which also redefines
the env var and its meaning). Only two legs are this service's own:
[apple.m](../../src/services/roaming_store/apple.m), and
[NokreRoamingStore.java](../../src/platform/android/java/dev/nokre/shell/NokreRoamingStore.java)
behind the Android shim. The web leg is
[web.zig](../../src/services/roaming_store/web.zig). Tests are
[roaming_store_test.zig](../../src/services/roaming_store/roaming_store_test.zig),
and the two gates that run real verbs are
[tests/dev_store.zig](../../tests/dev_store.zig) and
[tests/web_services.mjs](../../tests/web_services.mjs).

## Why a second service rather than a posture on the first

The consumer that asked for it needs both at once: a session that must
die with the device and a credential that must outlive it. One store
cannot hold two postures, and secure_store's own refusals rule out the
alternatives — no per-item protection levels, no custom namespaces, no
cap knobs. A second linked service is what is left, and it is also the
honest shape: a build file says out loud that this app carries a store
whose entries are meant to travel.

secure_store's **"No cross-device sync"** refusal is not reversed by
this. Its grounds — that two devices merging secrets is nondeterminism —
still hold, and still hold *for that store*. What the split adds is that
nondeterminism is the right answer for some data and the wrong answer
for the rest, so the two answers get two stores rather than one knob.

## The namespace, and why it cannot alias

`pkg_id ++ "#roaming"`, composed at comptime in build.zig out of
[namespace.zig](../../src/services/roaming_store/namespace.zig) — the
one home both sides of the build read, since
[packaging.zig](../../src/packaging/packaging.zig) needs the same suffix
to name the file Android's backup carries.

The suffix has to fall outside **both** the key charset (`[a-z0-9._-]`)
and reverse-DNS ids, and `#` is in neither. A dotted suffix would not
do: app `com.a`'s roaming namespace would be `com.a.roaming`, which is
app `com.a.roaming`'s *secure* namespace, and the two would compose the
same Windows target name, the same Keychain service, the same prefs file
and the same dev-store file. The test that pins this asserts on the
first byte of the suffix, not on a literal.

The separation is then structural on every backend, because each is a
stateless function of `ns`: the Windows target is `ns + "/" + key`, the
Keychain service is `ns`, the libsecret attribute is `ns`, the dev
store's file is named `ns`, the prefs file is `"nokre.rs." + ns`, and
the browser storage key is `"nokre.ss." + ns + "/" + key` — one storage
schema, two namespaces.

## The byte budget

`max_total_bytes = 64 KiB`, keys and values together, `key.len +
value.len` summed with no per-entry framing. It is the one cap this
service has that secure_store does not, and it is contract on every
platform for the reason every other cap is: so a `set` that succeeds in
development succeeds at a user's.

- **Why there is a byte cap at all.** What bounds a roaming store is
  how much crosses a network into a per-account backup, not how many
  rows a keychain holds. 256 entries at the 2560-byte value cap is
  688 KiB, which is a document store rather than a pouch.
- **Why 64 KiB.** It is the smallest credential-roaming facility any of
  the six platforms offers: Google's Block Store, 16 byte arrays of
  4 KiB (developer.android.com/identity/block-store, read 2026-09-15).
  The Android leg does not use it — the next section says why — but it
  is the floor a replacement leg would have to clear, so holding to it
  keeps a future backend swap from being a contract change. Windows'
  2560 became every platform's value cap on the same argument.
- **What it buys the first consumer, and the 99% is arithmetic.**
  rokovski's token store holds records of
  `token_len:u8 ++ raw token ++ raw signature` — 289 bytes at a
  2048-bit signature, 577 at a 4096-bit modulus — under 128-byte keys,
  and its own gate budgets 705 bytes per record as the upper bound. It
  holds **no record cap of its own**: the count is read off this budget
  at runtime through `remaining`, so what it can hold is
  `⌊65536 / 705⌋` = 92. The worst case therefore lands at 92 × 705 =
  **64,860 of 65,536** — 99% — by construction rather than by luck, and
  the 676 bytes left over are the remainder of that division, not
  headroom anyone spent. A derived count always fills its budget to
  within one record; a count that did not would mean the consumer had
  stopped reading `remaining`.

  So there is **one knob, and it is `max_total_bytes`.** Raising it
  raises the consumer's record count with it and the fit stays at 99%;
  lowering it lowers the count and the fit stays at 99%. What the number
  decides is not whether the consumer fits — it always does — but how
  many channels a person can be sending in, which is the thing to argue
  about if 92 is ever too few. The shape that actually ships spends
  92 × 417 = 38,364 bytes, 59%, and the distance between that and the
  ceiling is the distance between the signature in use and the widest
  one the gate admits. A test spends the ceiling and asserts the 676, so
  a change to this constant is a failing test rather than a discovery at
  a user's.
- **`StoreFull` means both lines, and that is deliberate.** The entry
  cap and the byte budget raise the same error because a consumer's
  answer to either is the same — store less — and `remaining` is how it
  finds out which. Two names would be two error sets and one more switch
  arm in every caller for a distinction only a log reader wants.
- **secure_store refused exactly this, and the refusal still stands
  there.** Its "why not more than 256" reasoning rules out a byte-arena
  table on the grounds that `StoreFull` would fire on total bytes, so
  whether a `set` succeeds would depend on the sizes of unrelated
  values, and it "would stop meaning the same thing on every platform".
  The first half is true here and accepted: it is what a roaming store
  is. The second half is answered rather than accepted — the accounting
  is the contract's, not any backend's, so the number is identical on
  all six platforms.

`remaining` is not free on the native legs. No OS store reports its own
byte total, so the first call after boot enumerates the namespace and
reads every value once; after that the app's own writes keep the tally
(`UsageCache`), and the cost is one pass per app lifetime. A second
process writing the namespace drifts it — the same best-effort bargain
secure_store's entry count already makes, and for the same reason:
enumerate-then-set was never atomic either.

## Apple: one layer, synchronizable

`kSecClassGenericPassword`, `kSecAttrService` = the namespace,
`kSecAttrAccount` = the key, and three differences from secure_store's
leg:

1. **`kSecAttrSynchronizable = YES` on every query**, set in
   `base_query` so no verb can forget it. Apple counts the attribute as
   part of an item's identity, so a query that omits it matches only
   non-synchronizable items: a `delete` or a `list` without it would
   silently miss everything this service wrote. (`kSecAttrSynchronizableAny`
   exists and is not used — this store's items are all synchronizable,
   and matching both classes would let a device-local leftover answer.)
2. **`kSecAttrAccessibleAfterFirstUnlock`**, not the `ThisDeviceOnly`
   twin. The `ThisDeviceOnly` classes are *defined* as the ones that do
   not migrate and are not carried in a backup, so they are mutually
   exclusive with a synchronizable item by construction rather than by
   policy. Boot reads still work whenever the app can run; a
   pre-first-unlock read is `errSecInteractionNotAllowed` → `Unavailable`,
   with no dialog.
3. **No legacy file-keychain layer.** The legacy keychain holds no
   synchronizable items, so there is nothing to fall through to: an
   unentitled binary's `errSecMissingEntitlement` is `Unavailable` here
   rather than a second lookup. Which is why a driver on macOS wants
   `.roaming_store_dev` at least as much as it wants secure_store's.

| OS result | Contract |
| --- | --- |
| `errSecSuccess` | OK |
| `errSecItemNotFound` | get → ABSENT (`null`); delete → OK (the postcondition already held); list → 0 entries — a fresh install, or one whose iCloud copy has not arrived, and the first `set` consults `list` |
| `errSecDuplicateItem` on add | retry as `SecItemUpdate` — upsert; delete + add when the new value is empty, secure_store's measured case on the same API |
| anything else | `Unavailable` |

**No entitlement is derived**, and the silence is the row rather than an
omission. `kSecAttrSynchronizable` **is** the mechanism: there is no
separate synchronizable entitlement to declare. The app's default
keychain access group is derived from its application identifier and
needs nothing declared; `keychain-access-groups` exists for *additional*
or *shared* groups, and this service never sets `kSecAttrAccessGroup`,
so it never asks for one.

The two are also different questions, which is where the doubt came
from: an access group decides **who may read** an item, and
`kSecAttrSynchronizable` decides **whether it participates in iCloud
Keychain sync**. Being synchronizable does not imply Keychain Sharing.
The packaging test asserts the emitted entitlements file stays empty, so
an edit that adds one is a failing test rather than a surprise.

What is genuinely unobserved here is narrower, and it is not a library
question: whether an item this leg writes on one signed device turns up
on a second signed device under the same Apple Account. That is iCloud
Keychain doing its own job, it needs two provisioned devices and a
signed build, and it belongs in a consumer's runbook as a device test —
not in this repository, which has neither.

## Android: the platform's own backup, not Block Store

The Keystore key secure_store wraps its values in is device-bound, so a
backup of that ciphertext restores bytes nothing can open. Something has
to give, and what gives is the on-device wrapping:
`NokreRoamingStore` writes base64 values into an app-private
`SharedPreferences` file with **no Keystore layer**, and Android's Auto
Backup carries that one file.

**The at-rest posture, stated.** The value in that file is plain base64,
and base64 is transport into a prefs map's `String`, not a cipher. It is
not wrapped because the wrap would buy nothing this store can spend. A
Keystore key is device-bound, so anything under it restores as bytes
nothing can open — which is the one extraction this service exists to
allow. And secure_store's key carries no user-authentication and no
unlocked-device requirement, so it is usable by any code running as the
app: against the attacker who has the app's uid, the wrap is already
transparent. What it defends is the attacker who reads the file without
being the app — and that attacker is held off by the app sandbox and by
file-based encryption, which this store keeps. So the wrap protected
exactly the case this store is for, and nothing else. It is left off.
Off the device, the protection is the backup's own encryption, keyed by
the device's lockscreen secret and unreadable to Google. That posture is
weaker than secure_store's on one axis and honest about it, and it is
stated in [../services.md](../services.md) where a consumer reads it.

**The residual, on Android 9 through 11.** Auto Backup's end-to-end
encryption needs a lockscreen secret to key it, so a device with no lock
screen has none — and the backup still runs, under Google's key. On
Android 12 and up that is closed at the source:
`<cloud-backup disableIfNoEncryptionCapabilities="true">` switches the
cloud half **off** rather than downgrading it, so a device that cannot
encrypt backs this store up nowhere. Below 12 the rules come from
`fullBackupContent`, which has **no equivalent attribute**: on Android 9
to 11, on a device with no lock screen, this store's file is carried to
Google readable. That is a real hole, it is the platform's, and there is
no manifest that closes it. Device-to-device transfer is unaffected on
every version and needs no flag — it never reaches a server, which is
also why the switch above is scoped to the cloud half alone.

Two manifest artifacts fall out, and they are the first time a service
has changed a default rather than added to one:
`android:allowBackup` flips to `true`, and
`android:fullBackupContent` / `android:dataExtractionRules` name
`res/xml/nokre_backup_rules.xml` and
`res/xml/nokre_data_extraction_rules.xml`. Two attributes because
Android split the schema at API 31 and keeps reading the older one below
it; both name the same file, because a phone handed to its replacement
over a cable is the same event as one restored from the cloud.

**The exposure stays exactly the store.** An `<include>` inverts Auto
Backup's default: with one present it carries only what is listed, so
every other byte the app writes is as excluded as `allowBackup="false"`
made it. The file's name is one fact with two readers — the emitter and
`NokreRoamingStore.PREFS_PREFIX` — so the packaging test writes the
literal out rather than composing it, and a rename that reached only one
side fails there instead of silently backing up nothing.

**Why not Block Store**, which is Google's own answer to this and was
the shape first proposed. Four counts, each independently sufficient:

1. **Quota.** 16 byte arrays of 4 KiB is 65,536 bytes *before* any
   framing, against Auto Backup's 25 MB per app. A consumer deriving its
   count from the budget does not overflow either way — it holds fewer
   records — so what the quota decides is capability, and Block Store
   decides it for us: 64 KiB is Google's number, minus whatever a packed
   map's per-entry framing costs, and no argument raises it. Under Auto
   Backup the same ceiling is nokre's own policy line, 385 times inside
   the platform's bound, and raising it is an edit to one constant.
2. **Atomicity.** A logical map across 16 arrays is 16 non-atomic
   `storeBytes` calls, so a failure between them leaves a torn store —
   the exact objection that killed chunking on Windows
   ([secure_store.md](secure_store.md), "Chunking, weighed and worse").
   Making it whole again needs a commit record, which is a file format
   smeared across a platform store.
3. **Shape.** Block Store's API is `Task`-based. The contract is
   synchronous, and `Tasks.await` refuses to run on the main thread, so
   the leg would be an in-memory mirror with a blocking boot load —
   state on the native side, which the charter forbids, and a stall on
   the first frame. `SharedPreferences` is synchronous and holds
   nothing.
4. **Cost to the consumer.** Block Store is Play Services: a Maven
   coordinate, a source directory and `android.useAndroidX=true` in the
   consumer's own `app/build.gradle`, iap's exception again. Auto Backup
   asks for none of it, and works on a device with no Play Services at
   all.

Two things Auto Backup is *worse* at, recorded so the choice is not sold
as free. Its restore lands at install rather than continuously, so
nothing "roams" between two devices in use the way the Apple leg does —
this store only survives a replacement there. And its schedule is the
platform's (roughly nightly, idle, Wi-Fi), so a value written shortly
before a device is lost may never have travelled; Block Store's writes
reach its store immediately. Both are stated in
[../services.md](../services.md); neither outweighs the four above.

| Java outcome | Contract |
| --- | --- |
| value bytes (may be zero-length) | get → OK; an empty value is a present, empty value |
| `getString` returns null | get → ABSENT (`null`) |
| `commit()` true | set / delete → OK |
| empty key array | list → 0 entries |
| any thrown `Exception` / false `commit` / null array | `Unavailable` |

## Windows, desktop Linux, web: nothing roams, and the verbs behave

Choosing `Unavailable` on the three platforms with no roaming facility
was weighed and refused: a consumer's code path would fork by platform
for a store that is supposed to be the same four verbs everywhere, and
the web rooms that need this store need it to *work* on the web. So
Windows and desktop Linux get the same backend secure_store has under a
namespace that cannot alias it — literally the same C, through the shim
— and the web gets the same table-and-shadow posture. What each platform
carries onward is a row in the consumer table, not a difference in the
API.

Credential Manager does have a roaming persistence,
`CRED_PERSIST_ENTERPRISE`, and it is not used: it follows a *domain*
profile rather than a consumer account, so it would be a different
promise wearing this one's name.

**The web table is a byte arena**, which is the one place the budget
pays for itself. secure_store's table is 256 × (128 + 2560) ≈ 673 KiB of
`.bss` because every slot is sized for the largest value; here the
values share a 64 KiB arena behind 256 key slots, ~99 KiB in all. That
shape is the one secure_store's "why not more than 256" bullet refused —
and refused *because* it would make `StoreFull` fire on total bytes,
which is this service's contract. A delete compacts the arena and shifts
every offset after the hole; `tests/web_services.mjs` deletes from the
middle and reads the survivors back, because a stale offset would hand
out a neighbour's bytes and nothing else would notice.

## The dev store: a directory is one account's cloud

`.roaming_store_dev = true`, under `devStoreAllowed`'s same three gates
(Debug, macOS or desktop Linux, alongside the linked service), and the
same announcement on stderr at every launch. It is secure_store's
`dev.c` compiled a second time through a four-line shim, so there is one
file format with one writer and a fix to the record walk reaches both.

The one difference is what the environment variable names.
`$NOKRE_SECURE_STORE_DEV` names the store *file* — one run, one store.
`$NOKRE_ROAMING_STORE_DEV` names a **directory**, and the file inside it
is named for the namespace. That is the affordance a device-replacement
journey needs: two app instances pointed at one directory are two
devices restoring one account's backup, and a driver that copies the
directory has copied the cloud.

## What is verified, and by what

- **The unit suite** drives the whole contract through the shared fake:
  the two stores staying two stores, the budget arithmetic through
  `remaining`, `StoreFull` on the byte line firing before the entry cap,
  and the first consumer's measured shape fitting.
- **`tests/dev_store.zig`** runs the release verbs against a store the
  OS answers — a real executable, no mock in the binary. It asserts the
  two stores are two files (the run points them at different places and
  the same key reads back differently), that the budget is `key + value`
  and nothing else, that the byte line fires against the real backend,
  and that a second `App` reads back what the first wrote.
- **`tests/web_services.mjs`** boots a real wasm app on the shipped
  `live.js` and drives the web leg: the two namespaces in one storage
  schema, the arena compacting on a middle delete, the budget refusing a
  write, and the boot snapshot filtering to this store's namespace.
- **`zig build check-targets`** compiles the leg for all six OS tags,
  which is the only thing that analyzes `apple.m` at all; its own object
  rather than riding the store one, because on COFF zig refuses to fold
  two C sources into one and this store's Windows leg *is*
  secure_store's windows.c under a second prefix.
- **The packaging tests** hold the manifest, both rule resources and the
  empty entitlements file byte-exact.
- **Nothing runs `apple.m` or the Java backend.** The Apple leg cannot
  be reached from an unsigned test binary at all, and the Android leg is
  NDK-built by a consumer's Gradle. Both were written against the
  platform documentation and against secure_store's measured behaviour
  on the same APIs; neither has been run on a device in this repository,
  and nothing here pretends otherwise. The one observation that would
  need real hardware is the round trip itself — an item written on one
  signed device read back on a second under the same Apple Account, and
  its Android twin across a restore — which is a consumer's device test,
  since it exercises iCloud Keychain and Auto Backup rather than
  anything this library decides.

## Refusals

secure_store's refusals all carry over — no change notifications, no
per-item protection levels, no encryption theater on the web, no cap
knobs, no custom namespaces, no async shape — and this service adds two
of its own:

- **No in-app switch.** Whether entries travel is the operating
  system's own setting, exercised where the user already exercises it.
  A per-app toggle would be a second authority over a decision the OS
  already owns, and it would have to lie on the four platforms that
  carry nothing.
- **No merge policy.** On Apple a `get` can return what another device
  wrote and a `list` can name a key this device never stored. The
  service reports what is there; deciding what two devices' writes mean
  together is the consumer's, and a store that guessed would be a store
  that silently discarded one of them.
