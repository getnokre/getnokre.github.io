const nok = @import("nokre");

pub const L = nok.l10n.Bundle(&.{
    @embedFile("l10n/site_en.arb"),
});

comptime {
    _ = L;
}

pub const locales = @import("std").enums.values(L.Locale);
