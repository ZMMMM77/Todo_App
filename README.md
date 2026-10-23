# ToDo App

A lightweight, local-first macOS to-do app that stays within reach. A small floating dot expands into a native Liquid Glass panel when you hover over it, so checking your tasks does not require opening a full application window.

Built with **SwiftUI and AppKit**, with no third-party dependencies.

## Features

- **Floating dot:** a compact entry point displaying your unfinished task count.
- **Hover to expand:** smooth expand/collapse transitions with support for the system Reduce Motion preference.
- **Pin when needed:** keep the panel open, or let it collapse when the pointer leaves.
- **Draggable panel:** move it using the top title bar; its position is remembered.
- **Simple task management:** add, edit, complete, restore, delete, and undo the most recent deletion during the current session.
- **Reordering:** use the task context menu to move items up or down. A drag handle is also available; drag-and-drop behavior still needs broader testing.
- **Larger click targets:** the input strip and completed-task header are clickable across the row.
- **Local storage:** changes are saved automatically to a JSON file on your Mac.
- **Menu bar controls:** show or hide the panel, open the data folder, or quit the app.

The current interface is in Chinese and follows the system appearance.

## Requirements

- macOS **26 or later** for native Liquid Glass.
- Swift **6.2 or later** and a macOS SDK supporting the macOS 26 APIs.
- Xcode or compatible Command Line Tools selected with `xcode-select`.

Development builds have been tested on Apple Silicon. Other hardware, multiple monitors, and fullscreen Spaces need further validation.

## Build and run

```sh
git clone https://github.com/ZMMMM77/Todo_App.git
cd Todo_App
zsh build.sh
open "ToDo App.app"
```

The build script compiles a release executable, creates the `.app` bundle, and applies a local ad-hoc signature. The bundle is intended for local use; it is not a notarized distribution build.

No account, API key, server, or package download is required by the application.

## Usage

1. Launch the app. A small dot appears near the top-right corner of the screen on a fresh setup.
2. Hover over or click the dot to open the panel.
3. Click the input strip or its **+** button, type a task, and press **Return** or click the submit button.
4. Click a task's text to edit it. Press Return or leave the field to save.
5. Click the circle beside a task to complete it. Expand the completed section to restore it.
6. Right-click a task for move and delete actions. Use **Undo** after deletion if needed.
7. Use the pin button to keep the panel open, or the minus button to collapse it.
8. Drag the title bar to reposition the panel. The pin and collapse buttons remain independently clickable.

The menu bar checklist icon provides show, hide, data-folder, and quit actions. The app does not need to occupy the Dock.

## Data and privacy

Task data is stored at:

```text
~/Library/Application Support/ToDo App/tasks.json
```

The app does not implement cloud synchronization, analytics, or network requests. Window position is stored in macOS preferences. Rebuilding the app does not erase your tasks.

Task updates use atomic file writes. If the existing task file cannot be decoded, the app displays an error and stops writing rather than overwriting it. To make a backup, copy `tasks.json`. To restore a backup, quit the app first, replace the file, and relaunch.

## Verification

After building, run the isolated storage checks:

```sh
"./ToDo App.app/Contents/MacOS/ToDoApp" --self-test
```

These checks use a temporary directory and cover adding, trimming, editing, completion, persistence, deletion/undo, ordering, and protection against overwriting an invalid JSON file. They do not modify your real tasks.

Input, task actions, menu-based ordering, pinning, and expand/collapse have also been checked manually. Animation feel, drag-and-drop ordering, and multi-display behavior still benefit from additional testing.

## Project structure

```text
Package.swift                Swift package definition
Sources/ToDoApp/main.swift    Data model, floating panel, and SwiftUI interface
build.sh                     Local .app packaging and signing
```

Build caches, compiled app bundles, personal task data, and local screenshots are intentionally excluded from version control.

## Current scope

This is an early local-only prototype. It does not yet include reminders, recurring tasks, cloud sync, AI integration, Apple Reminders integration, or launch-at-login settings.
