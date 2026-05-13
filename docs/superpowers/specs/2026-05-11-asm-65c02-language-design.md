# Assembly (65C02) Language Support — Design

**Status:** Draft for review
**Date:** 2026-05-11
**Author:** Brian Tabone (PaperWasp)

## 1. Background

PaperWasp inherits Notepad++'s Assembly (`L_ASM`) language, which is wired through
the Lexilla `LexAsm.cxx` lexer (`SCLEX_ASM`) and uses an x86/x64/MASM-flavored
keyword set. The lexer itself is dialect-agnostic — it exposes eight `WordList`
slots that are filled by `langs.model.xml`. The current `<Language name="asm">`
entry populates them with Intel/AMD mnemonics, x86 registers (`ax`, `eax`,
`rax`, `xmm0`…), and MASM directives (`.386`, `.code`, `.model`…).

The author works on the **WDC W65C02S** (per the WDC Assembler/Linker manual:
https://www.westerndesigncenter.com/wdc/documentation/Assembler_Linker.pdf)
and wants first-class syntax highlighting for that dialect.

## 2. Goals

- Add a new language `Assembly (65C02)` that:
  - Highlights the full WDC W65C02S instruction set (including WDC `WAI`/`STP`
    and Rockwell `SMB`/`RMB`/`BBR`/`BBS` extensions).
  - Highlights 65C02 registers (`A X Y S P SP PC`).
  - Highlights WDC Assembler directives.
  - Folds on `macro`/`mend` and `if`/`endif`.
- Live alongside the existing x86 `Assembly` language; do not break or replace it.

## 3. Non-goals (out of scope for v1)

- 65816 long-mode support (`longa`/`longi`/`shorta`/`shorti`, 24-bit operands,
  bank wrapping). A future `L_ASM_65C816` can be added the same way.
- WDC linker control file (`.lkr`) highlighting.
- Editor-side build integration (running `WDC65xx.exe`, parsing `.lst`).
- Auto-completion API file (`PowerEditor/installer/APIs/asm65c02.xml`). Can be
  added later when API completion is wanted.
- A sophisticated function-list parser. v1 reuses the existing "label at column
  0 followed by `:`" heuristic.

## 4. Architecture

### 4.1 Lexer reuse

LexAsm.cxx (`SCLEX_ASM`) is reused unchanged. It accepts eight `WordList`s:

| Index | LexAsm role             | Styler class | 65C02 content                                |
|-------|--------------------------|--------------|----------------------------------------------|
| 0     | CPU instructions         | `instre1`    | All W65C02S opcodes (NMOS + CMOS + WDC + Rockwell extensions) |
| 1     | Math (FPU) instructions  | `instre2`    | *empty* — no FPU                              |
| 2     | Registers                | `type1`      | `a x y s sp p pc` (case-insensitive matching)|
| 3     | Directives               | `type2`      | WDC Assembler directive set                  |
| 4     | Directive operands       | `type3`      | *empty* in v1                                |
| 5     | Extended instructions    | `type4`      | *empty* in v1                                |
| 6     | Fold-open directives     | n/a          | `macro if ifdef ifndef`                      |
| 7     | Fold-close directives    | n/a          | `mend endif`                                 |

LexAsm is case-insensitive by default (`asm.case.sensitive` defaults to false),
so keywords are listed in lowercase and match both `LDA` and `lda`.

### 4.2 Language identity

- Enum value: `L_ASM_65C02`, appended **immediately before `L_EXTERNAL`** in
  `LangType` (preserves the "L_EXTERNAL is always last" invariant called out in
  the enum's source comment, and keeps existing enum values stable for plugin
  ABI compatibility).
- Short name: `asm65c02`
- Display name: `Assembly (65C02)`
- Description: `WDC 65C02 assembly source file`
- Default extension entry: `asm` (the same as `L_ASM` — see §4.5).
- Comment line marker: `;`. No block comments.

### 4.3 Menu integration

- New command ID `IDM_LANG_ASM_65C02` in `menuCmdID.h`, placed in the same
  numeric block as other `IDM_LANG_*` commands.
- Two `Notepad_plus.rc` insertions, both immediately after the existing
  `IDM_LANG_ASM` line:
  - Language submenu (currently `MENUITEM "Assembly", IDM_LANG_ASM` at
    `Notepad_plus.rc:1003`).
  - Tab-context language list (currently `Notepad_plus.rc:1107`).

### 4.4 ScintillaEditView wiring

`PowerEditor/src/ScintillaComponent/ScintillaEditView.{h,cpp}`:

- Append `{L"asm65c02", L"Assembly (65C02)", L"WDC 65C02 assembly source file",
  L_ASM_65C02, "asm65c02"}` to the language descriptor table at line 138.
- Add `L_ASM_65C02` to each of the language-set checks at lines 1820 and 2477
  (these enable column-aware behavior shared with `L_CSS`, `L_CAML`, `L_ASM`,
  `L_MATLAB`).
- Add `case L_ASM_65C02: setAsm65C02Lexer(); break;` in `defineDocType` near
  line 1974 (immediately after the existing `L_ASM` case).
- Declare and inline-define `setAsm65C02Lexer()` in the header alongside
  `setAsmLexer()` (around line 855); the body is identical:
  `setLexer(L_ASM_65C02, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5
  | LIST_6 | LIST_7);`.

### 4.5 Language ↔ command-ID maps

- `Parameters.cpp` `langTypeToCommandID` (around line 8005): add a case
  mapping `L_ASM_65C02 → IDM_LANG_ASM_65C02`.
- `Notepad_plus.cpp` `getLangFromMenuName` (around line 4024): add a branch
  returning `L_ASM_65C02` for the menu name `Assembly (65C02)`.

### 4.6 Default file-extension routing

Both `L_ASM` and `L_ASM_65C02` declare `ext="asm"`. WDC source files
conventionally use `.asm`; the author accepts the trade-off that the *default*
language picked when opening a `.asm` file depends on the order in which the
two `<Language>` blocks appear in `langs.xml`, and that the language for any
individual file can be overridden manually via the **Languages** menu.

To make 65C02 the default for `.asm` in PaperWasp, the new `<Language
name="asm65c02">` block is placed **after** `<Language name="asm">` in
`langs.model.xml`. Notepad++'s language registration is last-write-wins per
extension, so 65C02 will claim `.asm` on a fresh install. Users who prefer x86
can reorder the entries in their personal `langs.xml`.

### 4.7 Default styler

`PowerEditor/src/stylers.model.xml` gains a new `<LexerType name="asm65c02"
desc="Assembly (65C02)" ext="">` block. The `WordsStyle` entries (style IDs 0,
1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14) mirror the existing `asm` lexer
block at line 76 since the underlying SCLEX_ASM style IDs are identical. The
default color choices are copied verbatim from the existing ASM block; users
can re-tune via Style Configurator.

### 4.8 Function list

`PowerEditor/installer/functionList/asm65c02.xml` is created by cloning
`asm.xml` and renaming `displayName` and `id` to `asm65c02` /
`asm65c02_subroutine`. The label-at-column-0-followed-by-`:` heuristic in the
existing parser already matches the dominant 65C02 source convention.

`PowerEditor/installer/functionList/overrideMap.xml` is updated to associate
`asm65c02` with the new parser file.

## 5. Keyword content (concrete lists)

### 5.1 `instre1` — W65C02S instructions (lowercase, case-insensitive)

NMOS-6502 base set:
`adc and asl bcc bcs beq bit bmi bne bpl brk bvc bvs clc cld cli clv cmp cpx
cpy dec dex dey eor inc inx iny jmp jsr lda ldx ldy lsr nop ora pha php pla
plp rol ror rti rts sbc sec sed sei sta stx sty tax tay tsx txa txs tya`

CMOS additions: `bra phx phy plx ply stz trb tsb`

WDC additions: `wai stp`

Rockwell bit-test/bit-branch extensions:
`smb0 smb1 smb2 smb3 smb4 smb5 smb6 smb7
rmb0 rmb1 rmb2 rmb3 rmb4 rmb5 rmb6 rmb7
bbr0 bbr1 bbr2 bbr3 bbr4 bbr5 bbr6 bbr7
bbs0 bbs1 bbs2 bbs3 bbs4 bbs5 bbs6 bbs7`

### 5.2 `type1` — Registers

`a x y s sp p pc`

### 5.3 `type2` — WDC Assembler directives

Data / layout: `equ db dw dd ds fill org chip endasm end`

Modules / linker: `include import export extern global public record`

Macros: `macro mend mexit mlist mnolist`

Conditionals: `if ifdef ifndef else elseif endif`

Listing controls: `list nolist title subttl page lf clrlst radix`

Sections: `code data bss udata dpage ipage`

### 5.4 `type5` / `type6` — fold pairs

- Fold open (`type5`): `macro if ifdef ifndef`
- Fold close (`type6`): `mend endif`

These keywords also appear in `type2` per the existing langs.model.xml
convention (the comment block at line 31 of the existing `asm` entry).

## 6. Files changed / created

**Modified:**

- `PowerEditor/src/MISC/PluginsManager/Notepad_plus_msgs.h` — append
  `L_ASM_65C02` before `L_EXTERNAL` in the `LangType` enum.
- `PowerEditor/src/menuCmdID.h` — add `IDM_LANG_ASM_65C02`.
- `PowerEditor/src/Notepad_plus.rc` — two `MENUITEM` insertions.
- `PowerEditor/src/ScintillaComponent/ScintillaEditView.h` — declare
  `setAsm65C02Lexer()`.
- `PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp` — descriptor table
  row, two language-set updates, one `defineDocType` case.
- `PowerEditor/src/Parameters.cpp` — `langTypeToCommandID` case.
- `PowerEditor/src/Notepad_plus.cpp` — `getLangFromMenuName` case.
- `PowerEditor/src/langs.model.xml` — new `<Language name="asm65c02">` block
  after the existing `<Language name="asm">`.
- `PowerEditor/src/stylers.model.xml` — new `<LexerType name="asm65c02">`
  block.
- `PowerEditor/installer/functionList/overrideMap.xml` — register
  `asm65c02.xml`.

**Created:**

- `PowerEditor/installer/functionList/asm65c02.xml` — cloned from `asm.xml`.

## 7. Risks & trade-offs

- **`.asm` extension collision.** Both languages claim `.asm`. Default routing
  depends on ordering in `langs.xml`; PaperWasp ships with 65C02 last so it
  wins. The fallback for any user who prefers x86 is the Languages menu or a
  manual reorder of their `langs.xml`.
- **Enum-value stability.** `L_ASM_65C02` is appended at the tail (before
  `L_EXTERNAL`) so existing plugin binaries that reference older `LangType`
  values are unaffected.
- **Function-list parser is a heuristic.** Pure label-at-column-0 detection
  will surface every label, including data and macro labels — not just
  subroutines. Acceptable for v1; refinement is future work.
- **Upstream divergence.** This is a PaperWasp-only language; the upstream
  Notepad++ project will not have it. Future merges from upstream need to
  preserve these additions (typical for the PaperWasp port).

## 8. Verification

- macOS Xcode build (`cmake --build macos/build --target PaperWasp`) succeeds.
- App launches, **Languages** menu shows "Assembly (65C02)" near the existing
  "Assembly" item.
- Opening a hand-written 65C02 sample file (`*.asm`) auto-detects the new
  language; all four keyword classes (opcode, register, directive, comment)
  render with distinct colors.
- Folding works on a sample using `if … endif` and `macro … mend`.
- Function list panel shows top-level labels.
- Switching a buffer manually from "Assembly (65C02)" → "Assembly" and back
  works without crash.

## 9. Open questions

None at design time. Implementation may surface minor issues (e.g., how the
Windows resource compiler reacts to inserting the new menu item — should be
trivial) that will be handled in the implementation plan.
