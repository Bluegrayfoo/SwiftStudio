# SwiftStudio

SwiftStudio is a pair of native macOS terminal-runnable GUI apps:

- `code_studio`: a SwiftUI project/file editor that sends raw source through Firestore.
- `preview_runner`: a companion runner that watches Firestore, compiles SwiftUI with `swiftc`, opens the preview window, and reports status back.

The repository is configured for the GitHub repo:

```text
https://github.com/Bluegrayfoo/SwiftStudio
```

## Install

After pushing this folder to GitHub, install with:

```bash
curl -fsSL https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main/install.sh | bash
```

Local install from a clone:

```bash
./install.sh
```

The installer builds native Cocoa executables and places them in:

```text
~/cmds
```

## Run

Open the runner:

```bash
~/cmds/preview_runner --all
```

Open the studio:

```bash
~/cmds/code_studio --thread Thread1
```

## Firestore Paths

SwiftStudio uses the Firebase project embedded in the source.

- `Threads/Thread1.send`
- `Threads/Thread2.send`
- `Percent/Send.%`
- `Percent/Compile.%`
- `LatestHistory/History.hist`

`code_studio` writes raw SwiftUI source to the selected thread's `send` field. `preview_runner` compiles that raw source, strips Xcode-only `#Preview { ... }` blocks for command-line compilation, adds a SwiftUI host around `ContentView`, launches the compiled executable, and writes the preview/status back.

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
