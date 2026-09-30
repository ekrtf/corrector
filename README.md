# Corrector

A small floating macOS app for spelling corrections in French and English.

## Install

Run `./install.sh` in this directory. It builds the app with the macOS Swift command-line tools and puts `Corrector.app` in `~/Applications`. Launch **Corrector** from Raycast or Spotlight. No Xcode project or menu-bar item is required.

On first launch, enter an OpenRouter API key. The app stores it in the macOS Keychain. Pasted text is sent to OpenRouter; the app does not save a text history.

## Use

Paste text into **Original**. A correction starts automatically. Review **Corrected**, then click **Copy corrected text**. The clipboard receives rich text, including a plain-text representation for apps that do not accept formatting.

The model menu defaults to **Automatic (fastest)**. It checks OpenRouter's recent latency ranking and selects the first available model from a small set of general-purpose models suitable for French and English. The selection is cached for 30 minutes. You can choose a listed model or enter any OpenRouter model ID with **Other model…**.

**Detect format** treats pasted rich text as rich text. For plain text containing common Markdown markers, it renders the correction as rich text. You can force Plain text, Markdown, or Rich text with the format menu. Markdown rendering covers headings, simple lists, blockquotes, bold, italic, links, inline code, and fenced code. The original remains visible as pasted.

The app accepts only spelling and accent edits. If the model changes punctuation, whitespace, Markdown markers, a URL, or a code span, it shows an error instead of copying altered text. Manual edits to the original clear the previous result; paste again to request a new correction.

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
- `swiftc Sources/Corrector/FormattingGuard.swift Tests/FormattingGuardTests.swift -o /tmp/corrector-formatting-tests && /tmp/corrector-formatting-tests` checks formatting preservation.
- `swiftc -parse-as-library Sources/Corrector/MarkdownRenderer.swift Tests/MarkdownRenderingTests.swift -o /tmp/corrector-markdown-tests && /tmp/corrector-markdown-tests` checks Markdown rendering.
