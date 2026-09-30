# ADR 0001: Personal macOS spelling corrector

Status: **Implemented for review — rich-text defaults await user confirmation**

## Context

The app is for one person on macOS, with AeroSpace managing windows. The user wants to paste French or English text, send it to OpenRouter for spelling corrections, see the result, and copy it with one button. The window should float rather than join the tiled layout. Response time matters.

## Proposed behavior

1. Show a small floating window with the original and corrected text visible together. Launch it as a normal macOS app through Raycast or Spotlight; no menu-bar item or dedicated global shortcut.
2. Submit pasted text to OpenRouter automatically. Fix misspelled words and accents only; preserve grammar, punctuation, wording, tone, and formatting.
3. Keep the input visible while the request runs and show clear loading and error states.
4. Copy the result to the clipboard on button press.
5. Keep the OpenRouter API key in the macOS Keychain. Do not place it in the app bundle or preferences file.
6. Select a model automatically by default, with a user-controlled model override.
7. Accept rich text and support Markdown-to-rich-text output.

## Current defaults to confirm

- Pasted rich text keeps its original attributes when words are corrected. A single corrected word containing multiple styles inherits the attributes at its first character.
- Pasted Markdown is rendered as rich text in the corrected pane; **Copy corrected text** places rich text on the clipboard. Common Markdown constructs are supported; complex nested structures and tables are not yet rendered.
- Corrections run after paste only. Typing clears the previous result; pasting again starts a new request.
- Automatic model selection prioritizes speed among a curated set of general-purpose models, then asks OpenRouter to route to a low-latency provider.

## Technical findings

- OpenRouter offers `POST /api/v1/chat/completions` with bearer API-key authentication. Its Auto Router selects a model for a prompt, but its stated goal is task fit, not minimum latency. Provider routing supports sorting by latency or throughput for a selected model. [Chat API](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request), [Auto Router](https://openrouter.ai/docs/guides/routing/routers/auto-router), [performance controls](https://openrouter.ai/blog/insights/evaluate-llm-provider-performance/).
- The models API supports server-side `latency-low-to-high` sorting by recent median performance. Automatic selection uses this order among a short list of general-purpose French/English-capable models, caches the choice for 30 minutes, and falls back to OpenRouter Auto Router if the list is unavailable. A custom model ID overrides it. [Models API](https://openrouter.ai/docs/api/api-reference/models/get-models).
- AppKit has a `moveToActiveSpace` window behavior, but AeroSpace uses its own workspace emulation. Its documented `on-window-detected` rule can force an app window to float. The app's own panel behavior and an optional AeroSpace rule should be verified together. [Apple](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace), [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide).
- This Mac has the Swift command-line tools and AeroSpace, but no Xcode application at the standard `/Applications/Xcode.app` path. The implementation should remain buildable with command-line tools, or Xcode must be installed before using an Xcode-only project workflow.

## Acceptance checks

- Paste a multiline French sample with accents and an English sample; compare unchanged line breaks and spacing.
- Paste bold, italic, and linked text; confirm the copied correction has the intended formatting.
- Paste Markdown; confirm the expected rendered and copied forms.
- The app never silently replaces the source text or copies a failed response.
- Open the window on an AeroSpace workspace and confirm that it floats and receives keyboard focus.
- Confirm an invalid API key and a network error have understandable recovery paths.
