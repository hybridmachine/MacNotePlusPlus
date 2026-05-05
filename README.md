# PaperWasp

PaperWasp is an independent macOS source code editor based on the Notepad++ codebase.
It ports the Windows-native C++ editor through a macOS compatibility layer, preserving
the Scintilla editor component, Lexilla lexers, tabbed editing, plugins, and related
editing workflows where practical.

PaperWasp is not affiliated with, sponsored by, or endorsed by the creators of
Notepad++.

## Attribution

PaperWasp is based on Notepad++ by Don Ho and the Notepad++ contributors. The
upstream project is available at https://github.com/notepad-plus-plus/notepad-plus-plus
and https://notepad-plus-plus.org/.

PaperWasp also uses Scintilla and Lexilla. See the project licenses and vendored
dependency notices for details.

## Build PaperWasp

The macOS port uses CMake with the Xcode generator:

```bash
cd macos/build
cmake -G Xcode ..
cmake --build . --target PaperWasp
cmake --build . --target PaperWasp_package
cmake --build . --target PaperWasp_dmg
```

Build outputs are written under `macos/build/` and `macos/dist/`.

For legacy upstream Windows build information, see [BUILD.md](BUILD.md).
