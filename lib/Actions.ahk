#Requires AutoHotkey v2.0
; ============================================================
; Actions.ahk - 粘贴 / 热字符串 / 托盘菜单 / 热键注册
; ============================================================

class App {
    static Name    := "Octopus Fragment"
    static Version := "1.0.0"
}

global gLastFocusHwnd := 0     ; 呼出面板前的活动窗口
global gHotstrings    := Map() ; 已注册的缩写 -> snippet id
global gSlashSpec     := ""    ; 已注册的「触发符+Tab」热字符串
global gSlashBusy     := false ; 触发符钩子运行中
global gSlashErase    := 0     ; 面板打开期间目标窗口里遗留的「触发符+关键字」字符数，插入前需删掉

; ---------- 插入片段到当前窗口 ----------
; 删掉「触发符+Tab」遗留在目标窗口里的「/关键字」
; 只能在焦点已切回目标窗口后调用，否则会误删别的程序里的字符
EraseSlashTyped() {
    global gSlashErase
    n := gSlashErase
    gSlashErase := 0
    if (n > 0) {
        Send("{Backspace " n "}")
        Sleep(50)
    }
}

PasteSnippet(id, restoreFocus := true) {
    global gSlashErase
    sn := Store.Get(id)
    if (sn = "") {
        EraseSlashTyped()
        ToolTip("片段不存在")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    ; 关闭搜索面板 / 管理窗口
    if (WinActive(SearchPanel.Title)) {
        SearchPanel.Hide()
        if (gLastFocusHwnd && WinExist("ahk_id " gLastFocusHwnd)) {
            WinActivate("ahk_id " gLastFocusHwnd)
            try WinWaitActive("ahk_id " gLastFocusHwnd, , 1)
        }
    }
    target := WinExist("A")

    ; 文本片段先渲染模板：含自定义变量时弹窗填写
    text  := ""
    caret := -1
    usedDialog := false
    if (sn["type"] = "text") {
        content  := sn.Has("content") ? sn["content"] : ""
        clipText := A_Clipboard
        vals := 0
        if Template.NeedsFill(sn) {
            vals := FillDialog.Collect(sn)
            if !IsObject(vals) {
                ; 取消填写：焦点还给原窗口，并清掉遗留的「/关键字」
                if (target && WinExist("ahk_id " target))
                    WinActivate("ahk_id " target)
                Sleep(60)
                EraseSlashTyped()
                return                       ; 用户取消，不插入
            }
            usedDialog := true
        }
        r := Template.Render(content, vals, clipText)
        text  := r["text"]
        caret := r["caret"]
    }

    ; 弹窗抢过焦点：插回前必须切回原窗口，切不回去就放弃，避免粘到别的程序里
    if usedDialog {
        back := false
        if (target && WinExist("ahk_id " target)) {
            WinActivate("ahk_id " target)
            try WinWaitActive("ahk_id " target, , 1.5)
            back := WinActive("ahk_id " target) ? true : false
        }
        if !back {
            gSlashErase := 0
            ToolTip("未能切回原窗口，已取消插入")
            SetTimer(() => ToolTip(), -2500)
            return
        }
        Sleep(60)
    }

    ; 触发符+Tab 唤起的搜索：此时焦点已回到目标窗口，先删掉遗留的「/关键字」再粘贴
    EraseSlashTyped()

    oldClip := ClipboardAll()
    ok := true
    try {
        if (sn["type"] = "text") {
            A_Clipboard := text
            if !ClipWait(2)
                ok := false
        } else {
            if !Store.RestoreClipboard(sn["file"])
                throw Error("资源文件丢失：" sn["file"])
            if !ClipWait(2, 1)
                ok := false
        }
        if (ok) {
            Sleep(80)
            Send("^v")
            ; {{cursor}}：粘贴后把光标退回到标记位置
            if (sn["type"] = "text" && caret >= 0) {
                tail := StrLen(text) - caret
                if (tail > 0) {
                    Sleep(120)
                    Send("{Left " tail "}")
                }
            }
        }
    } catch as e {
        ToolTip("插入失败：`n" e.Message)
        SetTimer(() => ToolTip(), -3000)
        ok := false
    }
    Sleep(150)
    A_Clipboard := oldClip
    if (ok)
        Store.BumpUsage(id)
}

; ---------- 热字符串 ----------
RefreshHotstrings() {
    ; 关闭旧热字符串
    for trigger, id in gHotstrings {
        try Hotstring(trigger,, "Off")
    }
    gHotstrings.Clear()

    if !Store.cfg["auto_expand"]
        return

    prefix := Store.cfg["abbrev_prefix"]
    caseOpt := Store.cfg["case_sensitive"] ? "C" : ""
    for sn in Store.db["snippets"] {
        ab := Trim(sn["trigger"])
        if (ab = "")
            continue
        spec := ":" caseOpt "*:" prefix ab
        ; 用闭包捕获 id
        cb := BindPaste(sn["id"])
        try {
            Hotstring(spec, cb, "On")
            gHotstrings[spec] := sn["id"]
        }
    }
}

BindPaste(id) {
    return (*) => PasteSnippet(id)
}

; ---------- 触发符 + Tab 唤起搜索（默认 / 或 /ul + Tab） ----------
; 原理：把触发符注册为热字符串（B0 = 不退格，触发符留在屏幕上），
;       触发后开一个 InputHook 接管后续按键（V = 字符照常打进前台窗口），
;       等 Tab 收尾：记下「触发符+关键字」长度并打开搜索面板；
;       真正删除发生在用户选中片段（粘贴前）或取消填写时，且只在目标窗口里删。
RegisterSlashTrigger() {
    global gSlashSpec
    if (gSlashSpec != "") {
        try Hotstring(gSlashSpec, , "Off")
        gSlashSpec := ""
    }
    if !Store.cfg["slash_enable"]
        return
    key := Trim(Store.cfg["slash_key"])
    if (key = "")
        return
    spec := ":*B0:" key
    try {
        Hotstring(spec, (*) => SlashTrigger())
        gSlashSpec := spec
    } catch as e {
        ToolTip("触发符注册失败：" e.Message)
        SetTimer(() => ToolTip(), -3000)
    }
}

SlashTrigger(*) {
    global gSlashBusy
    if (gSlashBusy)
        return
    if IsOwnWindow(WinExist("A"))
        return

    key  := Trim(Store.cfg["slash_key"])
    if (key = "")
        return
    wait := Store.cfg["slash_timeout"]
    if (wait < 300)
        wait := 1500

    gSlashBusy := true
    typed := ""
    reason := ""
    endKey := ""
    try {
        ih := InputHook("V", "{Tab}{Escape}")
        ih.VisibleNonText := true      ; 方向键/快捷键照常放行，避免打断正常操作
        ih.Start()
        ih.Wait(wait)
        typed  := ih.Input
        reason := ih.EndReason
        endKey := ih.EndKey
    } finally {
        gSlashBusy := false
    }

    if (reason = "EndKey" && endKey = "Tab") {
        ; 只把「纯 ASCII 简短关键字」当成命令，避免误伤正常输入
        if !RegExMatch(typed, "^[a-z0-9_\-\.]{0,20}$") {
            Send("{Tab}")
            return
        }
        ; 触发时不删字符（热字符串线程里发 Backspace 有竞态，容易只删掉半截、留下触发符），
        ; 改为记住待删长度，等用户选中片段或取消时在目标窗口里一次性删干净
        ShowSearch(typed, StrLen(key) + StrLen(typed))
        return
    }
    if (reason = "EndKey" && endKey = "Escape")
        Send("{Escape}")
}

; 当前活动窗口是否为本工具的某个界面
IsOwnWindow(hwnd) {
    if (hwnd = 0)
        return false
    for cls in [SearchPanel, Manager, Editor, Settings, FillDialog] {
        try {
            if (cls.ready && IsObject(cls.gui) && cls.gui.Hwnd = hwnd)
                return true
        }
    }
    return false
}

; ---------- 托盘菜单 ----------
BuildTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("快速搜索", (*) => ShowSearch())
    A_TrayMenu.Add("管理片段", (*) => Manager.Show())
    A_TrayMenu.Add()

    ; 分类子菜单
    cats := Store.Categories()
    for c in cats {
        sub := Menu()
        list := Store.Search("", c)
        for sn in list {
            title := sn["title"]
            if (StrLen(title) > 28)
                title := SubStr(title, 1, 26) "…"
            sub.Add(title, BindPaste(sn["id"]))
        }
        if !list.Length
            sub.Add("(空)", (*) => 0)
        A_TrayMenu.Add(c, sub)
    }

    A_TrayMenu.Add()
    A_TrayMenu.Add("重新加载数据", (*) => ReloadAll())
    A_TrayMenu.Add("重载脚本（改代码后用）", (*) => Reload())
    A_TrayMenu.Add(App.Name " v" App.Version " · 关于", (*) => ShowAbout())
    A_TrayMenu.Add("退出", (*) => ExitApp())
    A_TrayMenu.ClickCount := 2
    A_TrayMenu.Default := "管理片段"
}

ShowAbout() {
    MsgBox(App.Name " v" App.Version "`n"
        . "类 FastKeys 的片段管理工具（AutoHotkey " A_AhkVersion "）`n`n"
        . "数据目录：" Store.DataDir, "关于", "Iconi")
}

ReloadAll() {
    Store.LoadDb()
    RefreshHotstrings()
    RegisterSlashTrigger()
    BuildTrayMenu()
    if Manager.ready
        Manager.RefreshCats()
    ToolTip("片段已重新加载")
    SetTimer(() => ToolTip(), -1500)
}

; ---------- 热键 ----------
RegisterHotkeys() {
    try Hotkey(Store.cfg["hotkey_search"], (*) => ShowSearch())
    try Hotkey(Store.cfg["hotkey_manager"], (*) => Manager.Show())
}

; erase：由「触发符+Tab」唤起时，目标窗口里遗留的字符数（插入前删掉）；普通唤起为 0
ShowSearch(kw := "", erase := 0) {
    global gLastFocusHwnd, gSlashErase
    gSlashErase := erase
    gLastFocusHwnd := WinExist("A")
    SearchPanel.Show(kw)
}
