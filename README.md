# codewords.koplugin

**Code Words** (FR *Mots de code*) — a team word-association party game for
[KOReader](https://github.com/koreader/koreader). Put the reader in the middle
of the table: two spymasters, two teams of field operatives, 25 words.

## Screenshot

![Screenshot](images/codewords.png)

## Rules

- Two teams, **Red** and **Blue**. Each picks a spymaster; everybody else is
  a field operative.
- A secret key says which of the 25 words are Red agents, Blue agents, neutral
  bystanders, and which one is the **assassin**. The starting team has 9
  agents, the other 8 (7 bystanders, 1 assassin).
- Only the spymasters see the key: **Show key**, operatives look away, tap the
  screen. Any tap hides it again (with a full e-ink refresh, so no ghost of the
  key stays on the panel).
- On its turn, a spymaster gives a one-word clue and a number (“ocean 2”).
  **Clue** shows it in the status line. Operatives tap words to reveal them:
  - own agent → keep guessing, up to the number + 1;
  - bystander or enemy agent → the turn ends;
  - the assassin → that team loses at once.
  **End turn** stops guessing early.
- A team wins when all its agents are revealed — even if the other team
  revealed the last one. Wins are counted across games.

## E-ink patterns

No colours on e-ink, so revealed cards use patterns:

| Card | Look |
|------|------|
| Red agent | solid black, white word |
| Blue agent | diagonal stripes, thick border, word on a white plate |
| Bystander | light grey |
| Assassin | black with a white X |

In the key view (and once the game is over) every card shows its role, and a
notch in the corner marks the cards already revealed.

## Features

- 5×5 grid sized to the screen; long words shrink, names with a space or a
  hyphen go on two lines.
- Word packs, picked in the menu (**Packs: all** or any mix); each grid draws
  from the selected packs only, and each pack is a file loaded only when a grid
  is dealt. Common nouns mixed with famous names and places (Napoléon,
  Einstein, Astérix, Égypte, Eiffel, Titanic, Lune, Jupiter…):

  | Pack | EN | FR |
  |------|----|----|
  | Classic words | 500 | 440 |
  | History & famous people | 264 | 263 |
  | Geography & monuments | 264 | 272 |
  | Pop culture | 240 | 240 |
  | Science & nature | 240 | 240 |
  | Food | 232 | 240 |
  | Kids | 240 | 240 |

  1873 distinct English words, 1785 French (a few words sit in two packs). The
  word language is its own setting (**Language: FR/EN**), defaulting to
  KOReader's language; the interface follows KOReader.
- The game in progress is saved when the screen closes; a finished game comes
  back with **New game** in the action bar.

## Installation

Copy `codewords.koplugin/` into KOReader's `plugins/` folder, with the shared
`game-common/` library as its `common/` folder (the release zip includes it).
**Code Words** then appears in the Tools menu.

## Development

`board.lua` is the game logic (no UI); `test_board_spec.lua` covers it and the
word packs (sizes, duplicates, excluded names):

```
busted test_board_spec.lua
```

## License

GPL-3.0
