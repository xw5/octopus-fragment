# Octopus Fragment User Guide

> A plain-language guide for everyday users. For developer docs, see [README.md](../README.md).
> [简体中文](UserGuide.zh-CN.md)

Octopus Fragment is a Windows snippet tool: store the text, images and files you use often as "snippets", then insert them into any input box with one keystroke. Great for email signatures, daily reports, canned replies and code blocks.

---

## 1. Install & Launch

1. Install [AutoHotkey v2](https://www.autohotkey.com/) (choose v2 during setup).
2. Double-click `OctopusFragment.ahk` to run.
3. An octopus icon appears in the system tray, and a few sample snippets are generated for you to try.

To auto-start with Windows: right-click the tray icon → open the data folder, create a shortcut to `OctopusFragment.ahk` and drop it into the Start Menu → Startup folder.

---

## 2. Quick Start: Insert Your First Snippet

1. Press **`Ctrl + Alt + Space`** to open the search panel.
2. Type a keyword (e.g. "email") — the list filters as you type.
3. Use **↑↓** to pick one, press **Enter** — it's inserted where you were typing.

Press **Esc** to close the panel at any time.

---

## 3. Four Ways to Insert

| Method | How | Best for |
|--------|-----|----------|
| Search panel | `Ctrl + Alt + Space` → search → Enter | Occasional snippets |
| Trigger + Tab | Type `/` then `Tab`; or type `/ul` then `Tab` to search "ul" directly | While typing |
| Abbreviation | Type `;;email` and it expands instantly | High-frequency short snippets |
| Tray menu | Tray icon → pick by category | Mouse users |

> Press Esc in the triggered panel and `/ul` stays in the text untouched — nothing lost.

---

## 4. Managing Snippets

Press **`Ctrl + Alt + M`** to open the manager window (or double-click the tray icon).

- **Add**: "⋯" menu (top-right) → Add; fill in a name, category and content.
- **Edit / Delete / Duplicate**: right-click any snippet. Duplicate creates "name 2", "name 3" copies.
- **Three content types**:
  - **Text**: multi-line text, just type it in.
  - **Image**: copy an image (screenshots work too), then click "Capture from clipboard" in the editor.
  - **File**: same — copy the file first, then capture.
- **Categories**: snippets are grouped into category tabs at the top of the window.

---

## 5. Dynamic Variables: Make Snippets Alive

Write `{{variable}}` in the content; a small dialog pops up on insert for you to fill in, then the rendered result is pasted.

**Example**: a daily report template

```
[Daily] {{date}}
Name: {{name}}   Env: {{env}}
Done today: {{done}}
```

On insert you're prompted for Name / Env / Done today, while `{{date}}` becomes today's date automatically.

**Built-in variables** (no setup needed):

| Syntax | Result |
|--------|--------|
| `{{date}}` / `{{time}}` / `{{datetime}}` | Today's date / time / both |
| `{{clipboard}}` | Current clipboard text at insert time |
| `{{cursor}}` | Cursor lands here after pasting |

Forgot the syntax? Hover the **?** next to "Dynamic variables" in the editor for a cheat sheet. Your last filled values are remembered and prefilled next time — just press Enter.

---

## 6. Settings

Manager window → "⋯" menu → Settings:

- **Hotkeys**: change the panel / manager shortcuts (`^`=Ctrl `!`=Alt `+`=Shift `#`=Win).
- **Trigger**: default `/`, changeable; abbreviation prefix defaults to `;;`, also changeable or disableable.
- **Language**: Follow system / 简体中文 / English — applies instantly, no restart needed.

---

## 7. Backup & Migration

All data lives in the `data\` folder next to the program:

- Backup: copy the whole `data\` folder.
- Move to a new PC: install AutoHotkey v2 + the program files, then put `data\` back in place.

---

## 8. FAQ

**Q: Typing `;;email` does nothing?**
Make sure your IME is in English/half-width mode; Chinese IME may swallow `;;` or `/`.

**Q: Image snippet inserts wrong?**
Image snippets are stored as clipboard snapshots and restored to the clipboard before pasting — the target app must support pasting images.

**Q: Changes don't take effect?**
Saving a snippet applies immediately. If you edited `data\snippets.json` by hand, use "Reload" in the tray menu.

**Q: {{cursor}} doesn't place the cursor?**
Some web rich-text editors don't support cursor movement — a known limitation.

**Q: How do I turn off auto-expansion?**
Disable abbreviation expansion in Settings; everything else keeps working.
