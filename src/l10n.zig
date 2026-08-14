//! This site's catalog, and its locale axis.
//!
//! One ARB source, so one locale — but the axis is real and nothing
//! below it is written for a set of size one. `L.Locale` is the list of
//! locales this site publishes; nowhere else names one, and there is no
//! `locales` constant anywhere that could disagree with the catalog
//! (`dom.Alternates` and `dom.localeStub` take the bundle for exactly
//! that reason). Adding `site_fa.arb` to the array below is the whole of
//! what "publish Persian" means to the generator: the loop, the paths,
//! the stubs and the `hreflang` sets all widen from here.
//!
//! **What is in the catalog and what is not.** Every string this site's
//! *Zig* authors: the page titles and blurbs (pages.zig), the framework's
//! own chrome words (`L.chrome`, one reserved key per `Chrome` field, so
//! a word nokre grows is a compile error here rather than shipped
//! English), the skip link, the footer, the 404 page's body, and the
//! chooser stub's words. Not in the catalog: nokre's `docs/*.md`, which
//! are rendered into most of this site's pages and stay one language,
//! and the prose of the screens this site builds by hand (content.zig's
//! home, indexes, gallery, palette and colophon) — those are page
//! *bodies*, the same category as the Markdown beside them in the route
//! table.
//!
//! A one-locale site whose pages are English documents and whose frame
//! is a catalog is not half-finished; it is exactly the shape a docs
//! site has on the day it adds a second language, and the shape that
//! says which half of the machinery is proven.

const nok = @import("nokre");

/// The bundle. The first source is the template and therefore
/// `L.default_locale` — what `resolve` answers for a reader this site
/// has no language for, and the language the chooser stub itself is
/// written in.
pub const L = nok.l10n.Bundle(&.{
    @embedFile("l10n/site_en.arb"),
});

// Zig analyses lazily: an L nothing reaches is an L nokre never checks.
comptime {
    _ = L;
}

/// Every locale this site publishes, in catalog order. The one place
/// the axis is enumerated; the generator's loop, the alternate sets and
/// the stubs all spend this and none of them counts it.
pub const locales = @import("std").enums.values(L.Locale);
