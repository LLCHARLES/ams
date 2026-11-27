# Library harness

Spotify's Your Library page mocked under its own class names and accessibility identifiers (from
`trees/clean/library/03.txt`, recorded 2026-09-16), so `Redesigned/Library/LibraryHeader.x` can be laid out
and looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/LibraryHarness.app
    xcrun simctl launch <udid> com.vojta.libraryharness            # first look
    xcrun simctl launch <udid> com.vojta.libraryharness back       # then the pass the page gets coming back from a playlist
    xcrun simctl io <udid> screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over `LibraryHeader.x` from the checkout it sits in and
links it with the real `Core/` and `Redesigned/Kit/` sources; `SRC=<other tweak/Sources> ./build.sh` builds
an older tree instead, to compare. `stubs.m` stands in for the hook files the harness does not compile.

It plays issue #21. The page comes up with the header's control row holding Search alone. At 0.8 s the
header's model lands: Recents and Create show, and the page lays out in the same turn. The mock of
`AutoLayoutStackView` (the real one's ivars are `observationsDictionary` and `needsCoalescedLayoutUpdate`)
places what changed on the next turn of the main queue, in a pass of its own container that reaches
neither the header nor the page. So at the page's pass a button just shown still stands at the row's
origin, where 03.txt has the hidden Recents. Before the fix the moves worked out on that pass stayed:
Search ends up next to the title, left of Recents, and Create goes off the screen. A page pass later (`back`)
put Search on top of Recents, which the old code never placed. After the fix the row's own pass places
everything again.

Launch words: `back` adds the page pass at 2.4 s. `steady` builds the header with the model already in it.
`nocreate` leaves Create out of the model, and `norecents` leaves Recents out (the account the tree was
recorded on). `wrapped` puts the header in the plain `UIStackView` Spotify 9.2.0 holds it in
(`design/spotify-920/920-library-tree.txt:488-489`), pinned at its top and sides, with the header's height Auto
Layout's (row on the safe area, chips under it, chips' bottom the header's, as read off 9.2.0 in the simulator);
without it the header is the page's own child laid out by frame, as through 9.1.90. Each moment is logged with where every control landed in the header:

    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "redesign library"'

What it does not cover: the real stack's constraints and when its coalesced update actually runs, the
element framework behind the avatar, the list's rows (`LibraryRows.x`) and the folder page.

## Compact library

    THEOS=$HOME/theos HARNESS_BUILD_DIR=/tmp/<dir> ./compact-check.sh

builds the app, runs it in a simulator of its own (made for the run, deleted after it) and exits nonzero on the
first failed check. The mock has what Compact library (`spotifyglass.redesign.library.hideChips`, `LibraryMenu.m`)
works with, under Spotify 9.1.x's identifiers: the chips as a collection view `Layout.CollectionView`
whose delegate selects and clears a filter, a clear chip whose class name holds `ClearChip`, and the list's sort row
(`YourLibraryContent.sort`, `YourLibraryContent.gridToggle`) with grid cards (`Components.UI.CardLibrary`) or rows.
The sort button cycles the order where Spotify opens its sheet; the toggle switches the view.

`check` launches (main.m) assert: off, the header has no menu, its scrim and Spotify's title are gone, the large
title leads and the avatar ends 8pt from the trailing edge, both as the page's child and in 9.2.0's stack (`wrapped`); on, the chips fold once the sort row
has been seen (`late`: the list loads after the page, on its own pass), the header shrinks to its row, the list's inset
drops by the chips' band and holds through Spotify's next pass; the row reads title, menu button, controls, avatar
from the leading edge, each starting where the one before ends and the avatar 8pt from the trailing edge, mirrored
right to left, the menu with its VoiceOver label, hint and large content; the menu reads `Sort (Recents) | List,
Grid*`. Sorted on the mock's own row and the row then scrolled away, the menu names no order rather than the old one;
Sort picked then scrolls the list to its top in sight, fires the row's control only once it is there, and the list is
still at its top after the reload the sort makes; with the row on screen Sort fires in place, the list left where it
is; a view already shown fires nothing; a filter on keeps the chips folded and Clear all filters clears it through
the delegate; a list with no sort row (`nosort`) and a sort row gone when fired give the chips back; a folder keeps its
chips. The compact and `noclear` runs go again `wrapped`, where the header closes up through its constraints rather
than its frame. `safearea` then moves the page's top safe area 20pt down and back (as a rotation or a window resize
moves it; the mock's header and its inset for the list follow the safe area the way Spotify's do) and requires the
list's inset the chips' band under Spotify's new one each time, and Spotify's new one once the chips come back
(`SHOTS=<dir>` keeps `library-safearea.png`). `wrapped safearea` checks that the folded stacked header ends at the
control row and the list inset follows it both ways. `safearea bottomfirst` runs with each page pass setting the list's bottom
inset on a set of its own, the top carried in it as it stands, before the whole inset.
`wrapped headerpass` moves the row 33pt on a header-only pass and checks the title and menu against Search before
the page or controls lay out again. `wrapped safearea liveinset` has Spotify write the stacked header's live height
instead of its chips-included height. The list must meet the folded header as the safe top moves down and back,
then to 8pt and back without another inset write; unfolding must restore the full inset for the current safe top.
These reproduce the two stale positions in issue #59, not the unknown tab or settings sequence that triggered them.
Every menu read and pick goes through the header's own menu button, its deferred element's provider
run the way UIKit runs it as the menu opens, so the page the button finds from the header is the one checked. `noclear` chooses a filter with no clear chip the menu knows in the chips alone, with no pass of the page's:
the chips come back on the chips' own pass, fold again when it is cleared there, and with no pass at all are back by
the time the menu opens. The same run at the largest accessibility text size and right to left, then `settings`
(settings-check.m: the Library page's preview reads the chips or the menu with the switch, its title and sort rows
read from the leading edge, the switch stores the key, the card grows with the text) left to right and right to
left. Screenshot rehearsals are not part of this assertion runner; `look` remains available for manual review.

What it does not cover: Spotify's real chips, sort sheet and list, whose identifiers and class names come from
static reading rather than a recorded tree; whether the real list's content size changes once its rows arrive (the
hook that has the page look again); and where Spotify draws a selected chip (a selected trait or a selected control).
