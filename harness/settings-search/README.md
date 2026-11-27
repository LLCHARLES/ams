# Settings search harness

`Settings/SGSettingsIndex.m` — everything Mod Settings' search reads and matches, apart from the field and its table
(`Settings/SGSettingsSearch.m`) — run against pages of plain `SGModRow` rows. It builds and exits nonzero on failure.

```sh
sh harness/settings-search/build.sh
```

Mac Catalyst's UIKit, no simulator, no window, no network, no phone. The build products stay in `build/` (gitignored), and
`CFFIXED_USER_HOME` points inside it, so the recents the check writes never touch the real defaults domain.

## What it covers

- **The page a time (candidate 3).** Opening the field reads the searched page itself and builds no page under it;
  the first pass builds one page and the second the one after it; a query typed between passes matches the rows read
  already and is matched again as each pass adds to them; a stopped build is not continued by a pass already
  requested, and an old build's pass leaves a new build alone; the results are told once per pass that read a page and
  once when the pages end. Depth three and the 60-result cap hold. One case drives the **real run loop**: after
  `scheduleStep` nothing else calls the index, and every page within reach is read and `running` ends.
- **Keywords (candidate 4).** A word only `SGModRow.searchKeywords` holds is found; a row whose title holds the word
  lands over one that only its keywords or its trail hold (both ways round); the trail's page and the row's subtitle
  are found too; full-width text, diacritics and Korean initials all still match. A row `SGModRow.visible` hides is
  left out, and a switch that shows it needs the pages read again.
- **What a hit picks (both).** A row that opens a page is found as that page; a row of a page opens the page it sits
  on; a choice row is the row, not its list.
- **Recents (candidate 6).** Newest first, once each, six at most; a place is the **names** of the settings led
  through (`SGModRow.searchIdentifier`, else the row's key), never a title and never the typed query; a place the
  current look no longer has is skipped; a place written outside the search is read back, and Clear removes what was
  stored. A switch row is named by its key with nothing set; a row (or a row under a page row) with no name has no
  place and is never stored.
- **A look switch.** Two rows of one title, named per look, are two places: after the look changes, the other look's
  place resolves to nothing and the title's other row is a place of its own.
- **A language switch.** The same place finds its row after its title is translated.
- **A title two pages share.** Each row's own name tells them apart, so a recent opens the row it was.

## What it does not cover

The field, its table and `SGSettingsSearch.m` (`harness/mod-settings`' `search-controller` mode drives the real
`UISearchController` in the simulator), real `App/Pages.m` page builders and their cost, and the look of the results.
`search-attach-stub.m` stands in for `SGSettingsSearchAttach`, which the real `SGModPage` calls when a page is
searchable and which nothing here opens.
