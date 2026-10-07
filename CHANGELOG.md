# Changelog

Every release of Opus Lite. The newest is at the top; each one is also on [GitHub](https://github.com/glozahn/Opus-lite/releases).

## 2.1

Opus Lite now keeps itself up to date and can become the app that opens your voice notes.

### Updates install themselves

Opus Lite checks GitHub Releases, downloads the new disk image in the background and installs it only after three checks: the download matches its published SHA-256, it is signed by the same developer as the copy you are running, and Gatekeeper confirms Apple notarized it. A button in the sidebar restarts into the new version; ignore it and the update lands when you quit. Turn it off in *Settings ▸ General*.

### Open voice notes with a double-click

*Settings ▸ General ▸ Voice notes ▸ Make Default* makes Opus Lite the app for `.opus`, `.ogg` and `.oga` files, so a WhatsApp voice note opens and transcribes straight from Finder.

### Also

- A clear button above the file list removes files that no longer exist, or clears the whole history — files and transcripts. Also in *Settings ▸ Privacy* and *Transcript ▸ Clear History…* (⌥⇧⌘⌫). Original files are never touched.
- *Help ▸ What's New* shows this changelog. It also opens once after an update.
- Star the project on GitHub from the sidebar, *About* or the *Help* menu.
- *Help ▸ Report an Issue* opens the issue tracker.
- Signed with a Developer ID; the microphone keeps working under the hardened runtime.

## 2.0

A full rework into a library app.

- Three columns: library filters, files, and the transcript, plus an *Options* inspector.
- Video, PDF and image support, with Vision OCR for scanned pages and pictures.
- Timestamps, subtitles, and a waveform player that follows the text.
- Search across names and transcripts, favorites, trash and a processing queue.
- Export to TXT, DOCX, Markdown, SRT and VTT.
- Record voice notes from the microphone.
- English and Spanish interface, following the system language.

## 1.0

The first version: drop a WhatsApp voice note, press Convert, read the text.
