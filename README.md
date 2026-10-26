# Fly Break

A Koreader plugin that reminds you to rest your eyes. Every X minutes of reading, a fly shows up on the screen and won't leave until you squash it.

<table>
  <tr>
    <td align="center">
      <img width="1072" height="1448" alt="Reader_BeginningAfterTheEnd kepub epub_p12218_2026-10-25_193519" src="https://github.com/user-attachments/assets/d4029ef8-5931-4a64-8729-cab489d1a41e" />
    </td>
    <td align="center">
      <img width="1072" height="1448" alt="Reader_BeginningAfterTheEnd kepub epub_p12218_2026-10-25_193332" src="https://github.com/user-attachments/assets/8b9ef79e-1bd9-4157-999e-cd470900a8c1" />
    </td>
  </tr>
</table>


## Features

- A fly appears after a configurable amount of reading time (only counts while the screen is on and a book is open).
- The fly jumps around the screen and takes several taps to squash.
- A splat is left behind for every hit.
- While the fly is on screen, taps don't turn pages.
- If you don't touch the screen for 30 seconds, the fly gets tired and stays still to save battery. Touch the screen to wake it up.
- Two difficulty levels: **Normal** (3 hits) and **Hard** (5 hits, faster and smaller fly).
- Built for e-ink: only a small area is refreshed on each jump.

## Installation

1. Download the realese file and unzip it.
2. Copy the `flybreak.koplugin` folder into KOReader's `plugins` directory.
3. Restart KOReader.

## Usage

Open a book, then go to the top menu → **More tools** → **Fly Break**:

- **Enabled**: turn the plugin on or off.
- **Interval**: minutes of reading between flies (type any number).
- **Difficulty**: Normal or Hard.
- **Show fly now (test)**: spawn a fly right away to try it out.

Settings are saved in KOReader's settings folder (`flybreak.lua`).

## Customization
You can change the fly to any image of your liking, just replace `fly.png` or `splat.png` for another image.
