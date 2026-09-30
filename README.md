# Corrector

A small floating macOS app for spelling corrections in French and English.

## Install

Run `./install.sh` in this directory. It builds the app with the macOS Swift command-line tools and puts `Corrector.app` in `~/Applications`. Launch **Corrector** from Raycast or Spotlight. No Xcode project or menu-bar item is required.

On first launch, Settings opens so you can enter an OpenRouter API key. The app stores it in its preferences (`defaults write com.emile.corrector openRouterAPIKey <key>` also works), not in the Keychain, so rebuilt copies don't ask for your password. Pasted text is sent to OpenRouter; the app does not save a text history.

## Use

Paste text into **Original**. Corrector checks it automatically and shows the result in **Corrected**. Misspelled words are underlined in the original and highlighted in the correction. Press **Copy** in the toolbar (⇧⌘C) to put the corrected text on the clipboard. Text you pasted as rich text, or Markdown that Corrector rendered, is copied as rich text with a plain-text fallback. Anything else is copied as plain text, so it takes the style of the app you paste it into.

You can also type in **Original**. The previous result stays visible but dimmed until you check again with ⌘↩. **Apply Corrections to Original** (⌥⌘↩) replaces the original with the corrected text as one undoable edit, so you can keep writing.

The model menu defaults to **Automatic**, which picks the fastest model. It checks OpenRouter's recent latency ranking and selects the first available model from a small set of general-purpose models suitable for French and English. The selection is cached for 30 minutes. If the model's providers are rate-limited or down, OpenRouter falls back to the next listed model, and the window subtitle names the model that answered. You can choose a listed model or enter any OpenRouter model ID with **Other Model…**.

**Detect Format** treats pasted rich text as rich text. For plain text containing common Markdown markers, it renders the correction as rich text. You can force Plain Text, Markdown, or Rich Text with the format menu. Markdown rendering covers headings, nested lists, blockquotes (as indented italic paragraphs), bold, italic, strikethrough, links, inline code, and fenced code. The original remains visible as pasted.

The app accepts only spelling and accent edits. If the model changes punctuation, whitespace, Markdown markers, a URL, or a code span, it shows an error with **Try Again** instead of copying altered text.

Settings (⌘,) holds the API key, the model, and three behaviors: check after pasting (on by default), check again when you stop typing, and hide Corrector after copying.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Check spelling | ⌘↩ |
| Copy corrected text | ⇧⌘C |
| Apply corrections to original | ⌥⌘↩ |
| New: clear both panes, or reopen the window after ⌘W | ⌘N |
| Focus Original / Corrected | ⌘1 / ⌘2 |
| Zoom in / out / actual size | ⌘+ / ⌘− / ⌘0 |
| Find, find next, find previous | ⌘F, ⌘G, ⇧⌘G |
| Paste and Match Style | ⌥⇧⌘V |
| Hide the window | Esc, ⌘W |
| Settings | ⌘, |
| Quit | ⌘Q |

The standard editing, window, and app shortcuts (⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V, ⌘A, ⌘M, ⌘H, ⌥⌘H, ⌥⌘T) work as in other Mac apps.

## AeroSpace

The app uses an AppKit floating panel. If AeroSpace still tiles it on your setup, add this rule to `~/.aerospace.toml`:

```toml
[[on-window-detected]]
if.app-id = 'com.emile.corrector'
run = 'layout floating'
```

Then reload AeroSpace's configuration.

## Development

- `./build.sh` creates `dist/Corrector.app`.
- `swiftc Sources/Corrector/Corrections.swift Sources/Corrector/FormattingGuard.swift Tests/FormattingGuardTests.swift -o /tmp/corrector-formatting-tests && /tmp/corrector-formatting-tests` checks formatting preservation.
- `swiftc -parse-as-library Sources/Corrector/MarkdownRenderer.swift Tests/MarkdownRenderingTests.swift -o /tmp/corrector-markdown-tests && /tmp/corrector-markdown-tests` checks Markdown rendering.
- `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.
