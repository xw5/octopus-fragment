#Requires AutoHotkey v2.0
; ============================================================
; Actions.ahk - 粘贴 / 热字符串 / 托盘菜单 / 热键注册
; ============================================================

global gLastFocusHwnd := 0     ; 呼出面板前的活动窗口
global gHotstrings    := Map() ; 已注册的缩写 -> snippet id
global gTrayBuilt     := false
global gSlashSpec     := ""    ; 已注册的「触发符+Tab」热字符串
global gSlashBusy     := false ; 触发符钩子运行中
global gSlashPending  := ""    ; 面板取消时需要还原到目标窗口的文字

; ---------- 插入片段到当前窗口 ----------
PasteSnippet(id, restoreFocus := true) {
    sn := Store.Get(id)
    if (sn = "") {
        ToolTip("片段不存在")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    ; 关闭搜索面板 / 管理窗口
    if (WinActive(SearchPanel.Title)) {
        SearchPanel.Hide()
        if (gLastFocusHwnd && WinExist("ahk_id " gLastFocusHwnd))
            WinActivate("ahk_id " gLastFocusHwnd)
    }

    oldClip := ClipboardAll()
    ok := true
    try {
        if (sn["type"] = "text") {
            A_Clipboard := sn["content"]
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
;       等 Tab 收尾：把屏幕上的「触发符+关键字」删掉，用关键字打开搜索面板。
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
        Send("{Backspace " (StrLen(key) + StrLen(typed)) "}")
        Sleep(40)
        ShowSearch(typed, key . typed)
        return
    }
    if (reason = "EndKey" && endKey = "Escape")
        Send("{Escape}")
}

; 当前活动窗口是否为本工具的某个界面
IsOwnWindow(hwnd) {
    if (hwnd = 0)
        return false
    for cls in [SearchPanel, Manager, Editor, Settings] {
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
    A_TrayMenu.Add("重新加载", (*) => ReloadAll())
    A_TrayMenu.Add("退出", (*) => ExitApp())
    A_TrayMenu.ClickCount := 2
    A_TrayMenu.Default := "管理片段"
    gTrayBuilt := true
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

; pending：由「触发符+Tab」唤起时要还原的文字（面板被取消时才用）
ShowSearch(kw := "", pending := "") {
    global gLastFocusHwnd, gSlashPending
    gSlashPending := pending
    gLastFocusHwnd := WinExist("A")
    SearchPanel.Show(kw)
}
