# SwiftStudio

SwiftStudio contains native macOS terminal-runnable GUI apps:

- `code_studio`: a SwiftUI project/file editor that sends raw source through Firestore, downloads the compiled preview library returned by the runner, and hosts the preview locally.
- `preview_runner`: a companion runner app with a log window. It compiles SwiftUI into a loadable preview library, uploads that library through Firestore chunks, reports status back, and can exchange projects with Studio.

The repository is configured for the GitHub repo:

```text
https://github.com/Bluegrayfoo/SwiftStudio
```

## Install

After pushing this folder to GitHub, install with:

```bash
curl -fsSL https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main/install.sh | bash
```

That command installs `~/cmds/code_studio` and opens the SwiftStudio window.

Local install from a clone:

```bash
./install.sh
```

The installer builds the native Cocoa Studio executable and places it in:

```text
~/cmds
```

Install the preview runner on the runner computer with:

```bash
curl -fsSL https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main/install_runner.sh | bash
```

## Run

Open the studio:

```bash
~/cmds/code_studio --thread Thread1
```

## Editor Features

- Automatic indentation on new lines.
- Syntax highlighting:
  - keywords: pink
  - types and built-in SwiftUI views: blue
  - declaration names: cyan
  - variables and custom `View` declarations: green
  - comments: green
  - strings: red
- Project file renaming from the project screen.
- Project deletion from the main screen with a confirmation alert.
- Tuned scrolling for the editor and bottom console.
- Collapsible fullscreen inline preview pane from the small bottom-left preview button.
- Fullscreen automatically expands the Studio layout and opens the inline preview pane.
- Normal fullscreen preview can expand wider with `|<`.
- Wide preview has a side bar with `>|>` to return to normal width and `>|` to collapse.
- Red `Stop` button stops hosted previews and older running preview processes started by Studio.

Install without automatically opening the window:

```bash
SWIFTSTUDIO_NO_LAUNCH=1 curl -fsSL https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main/install.sh | bash
```

## Firestore Paths

SwiftStudio uses the Firebase project embedded in the source.

- `Threads/Thread1.send`
- `Threads/Thread2.send`
- `Percent/Send.%`
- `Percent/Compile.%`
- `Percent/Run.%`
- `Threads/<thread>/Compiled/<requestId>-0000...`
- `Threads/ProjectShare`
- `Threads/ProjectReturn`
- `LatestHistory/History.hist`

`code_studio` writes raw SwiftUI source to the selected thread's `send` field. `preview_runner` compiles that raw source, strips Xcode-only `#Preview { ... }` blocks for command-line compilation, wraps `ContentView` in an exported `NSHostingView` factory, uploads the compiled preview library as base64 chunks, and writes the status back. The runner has its own log window, but it does not open preview windows. When Studio sees a successful response, Studio downloads the compiled library, writes it to a uniquely named local temp library for that request, loads it, and hosts the returned preview view locally.

Project sharing uses `Threads/ProjectShare` for Studio-to-runner shares and `Threads/ProjectReturn` for runner-to-Studio project returns or add-to-projects shares.

The preview is inline only while Studio is fullscreen and the preview pane is expanded. Outside fullscreen, or when the fullscreen pane is collapsed, Studio moves the same hosted preview into a separate Studio-owned preview window. Studio continually rechecks placement so an already-loaded preview follows fullscreen, split-screen, resize, and collapse changes.

Studio sends its current process architecture with each preview request. The runner uses that value when compiling the preview library, so an arm64 Studio receives an arm64 library and an x86_64/Rosetta Studio receives an x86_64 library. If an older Studio request does not include an architecture, the runner builds a universal preview library with both arm64 and x86_64 slices.

`Percent/Run.%` represents the post-compile workflow:

```text
Runner uploads preview library chunks
Studio downloads all chunks
Studio base64-decodes them
Studio writes the preview library to disk
Studio loads the library
Studio creates the SwiftUI hosting view
Studio places it inline in fullscreen or in a separate window otherwise
```

Studio downloads preview library chunks concurrently, and the runner uses larger chunk documents to reduce request count. Studio and runner also use shorter polling intervals so completed work is noticed faster.

## Requirements

- macOS
- Xcode Command Line Tools
- `clang`
- `swiftc`

Install command line tools if needed:

```bash
xcode-select --install
```

## Source Layout

```text
src/code_studio_native.m
src/preview_runner_native.m
assets/swiftlogo.png
install.sh
```

## Notes

Projects are stored locally after install at:

```text
~/cmds/swift_studio_projects.json
```
