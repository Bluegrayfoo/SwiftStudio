# SwiftStudio

SwiftStudio contains native macOS terminal-runnable GUI apps:

- `code_studio`: a SwiftUI project/file editor that sends raw source through Firestore, downloads the compiled executable returned by the runner, and opens that executable locally.
- `preview_runner`: companion source is included for the runner side. It silently compiles SwiftUI into an executable, uploads that executable through Firestore chunks, and reports status back; it does not open the preview window.

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

Install the headless runner on the runner computer with:

```bash
curl -fsSL https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main/install_runner.sh | bash
```

## Run

Open the studio:

```bash
~/cmds/code_studio --thread Thread1
```

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
- `Threads/<thread>/Compiled/<requestId>-0000...`
- `LatestHistory/History.hist`

`code_studio` writes raw SwiftUI source to the selected thread's `send` field. `preview_runner` compiles that raw source silently, strips Xcode-only `#Preview { ... }` blocks for command-line compilation, adds a SwiftUI host around `ContentView`, uploads the compiled executable as base64 chunks, and writes the status back. The runner is headless and never opens a preview window. When Studio sees a successful response, Studio downloads the compiled executable, writes it to a local temp file, and opens the preview window on the Studio computer.

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
