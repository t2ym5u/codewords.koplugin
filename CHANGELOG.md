# Changelog

## [1.2.0] - 2026-11-10

### Added
- Twice as many French words in every pack: Classic 881 (was 440), Food
  501 (240), Geography 554 (272), History 527 (263), Kids 481 (240), Pop
  culture 512 (240), Science 499 (240). The game remembers the last 5,000
  words it dealt (was 3,000), so they all come up before any repeats.

## [1.1.3] - 2026-11-09

### Fixed
- A language tried once in the game no longer sticks for good: the game
  now starts in KOReader's language (French when KOReader is in French),
  and a language picked in the game holds until KOReader's language changes.

## [1.1.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.1.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.1.0] - 2026-11-03

### Changed
- Fresh words on every grid: the game remembers the words already dealt, per
  language, and a new grid takes words not seen yet; a word only comes back
  once every word of the selected packs has been on a grid (about 70 grids
  with all packs).
- French "History & people" pack: Coco Chanel and Dior, better known as
  fashion brands, replaced by Champollion and Vauban.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: two teams, a 5×5 grid of words, a hidden 9/8/7/1 key.
- Spymaster key view behind a hand-over screen; any tap hides it again.
- Clue entry (word + number) shown in the status line; the turn ends on a
  bystander, an enemy agent, or after number + 1 guesses; End turn button.
- E-ink patterns for the revealed cards (black, striped, grey, crossed).
- Wins counted across games; game saved and restored.
- Seven word packs selectable in the menu (Classic, History & famous people,
  Geography & monuments, Pop culture, Science & nature, Food, Kids): 1873
  distinct English and 1785 distinct French words, common nouns and famous names.
