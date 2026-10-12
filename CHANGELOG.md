# Changelog

Versions come from git tags (`Scripts/version.sh`). `Scripts/build_app.sh` writes it into the app's Info.plist; the sidebar footer and
*PSR Banks ▸ About* show it. The library folder records its format version and the last app version that opened it
(`library.json`).

## 0.4.0
- Bank descriptions: a short editable phrase per bank in each setlist (e.g. “Salsa”, “Song SBC”), shown under the bank name. The label is remembered by the bank's content, so importing the same bank again
  (even after deleting the setlist) restores it.

## 0.3.0
- Copy / cut / paste patches between slots (⌘C ⌘X ⌘V).
- Default patch: mark one (⇧⌘D), put it into the selected slot (⇧⌘U), fill empty slots with it (⇧⌘F).
- App version shown in the sidebar and About; library format version and default patch stored in `library.json`.

## 0.2.0
- Tags, instrument icons (23), patch info sheet, Finder-style rename, keyboard shortcuts and a cheat sheet (⌘/),
  drag-and-drop from the patch library, resilient loading of damaged or half-deleted libraries.

## 0.1.0
- First MVP: import a PSR-E483 `.USR`, library of patches, setlists of 8 banks × 4 memories, export with a valid checksum.
