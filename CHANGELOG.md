# Changelog

Versions come from git tags (`Scripts/version.sh`). `Scripts/build_app.sh` writes it into the app's Info.plist; the sidebar footer and
*PSR Banks ▸ About* show it. The library folder records its format version and the last app version that opened it
(`library.json`).

## Unreleased
- Blank patch replaces “default patch” everywhere. A patch called “BLANK” (the former “Default <BLANK>”) ships inside the app and is added to the library when it has none, shown grayed out; mark any other patch as the blank patch to override it.
- Delete on a slot puts the blank patch in it; Delete on a bank (after confirming) puts it in all 4 memories; Delete on a setlist asks first.
- Show Info for setlists (properties, file path) and the patch file path in patch info; more of a patch decoded (style, transpose, pitch bend, touch, harmony, DSP parts).

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
