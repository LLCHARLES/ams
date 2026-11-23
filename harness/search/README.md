# Search harness

    THEOS=$HOME/theos HARNESS_BUILD_DIR=/tmp/<dir> SHOTS=<dir> ./check.sh

Spotify's Browse page (the Search tab before anything is typed) mocked for `Redesigned/Search/SearchSections.x`: a
self-sizing compositional list (`BrowsePage.ContentScrollView`) of `Element_List.CollectionViewCell` cells whose content
view is a subclass named for the BrowseStructure's, the shape `trees/clean/search/01.txt` and the file's own comment give:
two watch feed carousels, each its own section with 16pt and 24pt after it, then 21 category cards two to a row with
16pt under the last row, the list inset 120pt under Spotify's header and 100pt over the tab bar. The page's layout pass
calls `SGRSearchCloseGap` as `SearchPage.x` does; `SearchPage.x` itself (the header) is not built.

With both collapse switches at their default, it requires the first card at the top of the list's inset, the last row
16pt over the content's end when scrolled as far as the list goes, no layout pass of the list while it sits there, and
the first card back at the top. `search-top.png` and `search-end.png` are written before the checks.

What it does not cover: Spotify's own list class and layout, which come from static reading and a recorded tree rather
than the running app.
