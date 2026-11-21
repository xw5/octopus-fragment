#Requires AutoHotkey v2.0
; ============================================================
; Actions.ahk - 粘贴 / 热字符串 / 托盘菜单 / 热键注册
; ============================================================

class App {
    static Name    := "Octopus Fragment"
    static Version := "1.0.3"
}

global gLastFocusHwnd := 0     ; 呼出面板前的活动窗口
global gHotstrings    := Map() ; 已注册的缩写 -> snippet id
global gSlashSpec     := ""    ; 已注册的「触发符+Tab」热字符串
global gSlashBusy     := false ; 触发符钩子运行中
global gSlashErase    := 0     ; 目标窗口里仍待删除的「触发符+关键字」字符数（粘贴前兜底删除）
global gSlashDeleted  := ""    ; Tab 收尾时已从目标窗口删掉的文本，Esc 取消面板时原样还原

; ---------- 调试日志（临时诊断用，定位后可关） ----------
global gDebugLog := true
DebugLog(msg) {
    global gDebugLog
    if !gDebugLog
        return
    try {
        p := A_ScriptDir "\data\debug.log"
        ; 超过 1MB 就清空，避免日志无限增长
        if (FileExist(p) && FileGetSize(p) > 1048576)
            FileDelete(p)
        t := FormatTime(, "HH:mm:ss.fff")
        FileAppend("[" t "] " msg "`n", p, "UTF-8")
    }
}

; 取窗口标题/类名用于日志：面板刚隐藏、焦点切换瞬间可能没有活动窗口，
; 直接 WinGetTitle("A") / WinGetClass("A") 会抛 TargetError，必须兜底
SafeWinTitle(hwnd) {
    try return WinGetTitle(hwnd)
    return ""
}

SafeWinClass(hwnd) {
    try return WinGetClass(hwnd)
    return ""
}

quoted(s) {
    return "'" StrReplace(StrReplace(s, "`r", "\r"), "`n", "\n") "'"
}

; ---------- 插入片段到当前窗口 ----------
; 兜底：删掉目标窗口里仍遗留的「触发符+关键字」（正常情况 Tab 收尾时已就地删掉）
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

; 还原 Tab 收尾时删掉的「触发符+关键字」（Esc 取消 / 放弃填写时调用）
; 需先把焦点切回目标窗口
RestoreSlashDeleted() {
    global gSlashDeleted
    if (gSlashDeleted = "")
        return
    Sleep(80)
    SendText(gSlashDeleted)
    gSlashDeleted := ""
}

PasteSnippet(id, restoreFocus := true) {
    global gSlashErase, gSlashDeleted
    sn := Store.Get(id)
    if (sn = "") {
        EraseSlashTyped()
        ToolTip(I18n.T("act.noSnippet"))
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
    DebugLog("paste: id=" id " type=" sn["type"] " target=[" (target ? SafeWinTitle(target) : "none") "] active=[" SafeWinTitle("A") "]")

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
                ; 取消填写：焦点还给原窗口，再还原删掉的「触发符+关键字」。
                ; 切不回去就不动键盘（Backspace/还原文本会打进别的窗口），只丢弃记录
                back := false
                if (target && WinExist("ahk_id " target)) {
                    WinActivate("ahk_id " target)
                    try WinWaitActive("ahk_id " target, , 1)
                    back := WinActive("ahk_id " target) ? true : false
                }
                if (back) {
                    Sleep(60)
                    EraseSlashTyped()
                    RestoreSlashDeleted()
                } else {
                    gSlashErase := 0
                    gSlashDeleted := ""
                }
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
            gSlashDeleted := ""
            ; 兜底：切不回原窗口就不强插，把内容放进剪贴板让用户手动粘贴
            copied := CopySnippetToClipboard(sn, text)
            ShowTip(copied ? I18n.T("act.clipFallback") : I18n.T("act.backFail"))
            return
        }
        Sleep(60)
    }

    ; 触发符+Tab 唤起的搜索：此时焦点已回到目标窗口，先删掉遗留的「/关键字」再粘贴
    EraseSlashTyped()

    ok := true
    failMsg := ""
    try {
        if (sn["type"] = "text") {
            A_Clipboard := text
            if !ClipWait(2)
                ok := false
        } else {
            if !Store.RestoreClipboard(sn["file"])
                throw Error(I18n.T("act.assetMissing", sn["file"]))
            if !ClipWait(2, 1)
                ok := false
        }
        if (ok) {
            Sleep(80)
            Send("^v")
            DebugLog("paste: ^v sent, text=" quoted(SubStr(text, 1, 40)))
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
        failMsg := e.Message
        ok := false
        DebugLog("paste: exception " e.Message)
    }
    ; 插入失败兜底：把片段内容放进剪贴板，提示用户手动 Ctrl+V
    if !ok {
        copied := CopySnippetToClipboard(sn, text)
        ShowTip(copied ? I18n.T("act.clipFallback")
                       : (failMsg != "" ? I18n.T("act.pasteFail", failMsg) : I18n.T("act.backFail")))
    }
    ; 粘贴后剪贴板保留片段内容本身（不再恢复旧剪贴板）：
    ; 1) 避免旧剪贴板里的残留内容（如之前遗留的「/关键字」）被误认为是片段的一部分
    ; 2) 部分应用粘贴是异步读剪贴板的，过早恢复旧值会粘出错误内容
    gSlashDeleted := ""               ; 本次 slash 流程已完结，清除取消还原记录
    if (ok)
        Store.BumpUsage(id)
}

; 把片段内容放进剪贴板（插入失败时的手动粘贴兜底），返回是否成功
CopySnippetToClipboard(sn, text) {
    ok := false
    try {
        if (sn["type"] = "text") {
            A_Clipboard := text
            ok := ClipWait(1)
        } else {
            ok := Store.RestoreClipboard(sn["file"]) && ClipWait(1, 1)
        }
    }
    return ok
}

ShowTip(msg, ms := 2500) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -ms)
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
;       等 Tab 收尾：就地删掉「触发符+关键字」（此刻焦点仍在目标窗口，删除最可靠），
;       再打开搜索面板；Esc 取消时把删掉的文本还原回目标窗口。
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
        ToolTip(I18n.T("act.slashRegFail", e.Message))
        SetTimer(() => ToolTip(), -3000)
    }
}

SlashTrigger(*) {
    global gSlashBusy, gSlashDeleted, gSlashErase
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
        ; Wait 的参数单位是「秒」，slash_timeout 配置是毫秒，必须换算
        ;（此前直接传毫秒值会挂起 25 分钟，期间 gSlashBusy 一直为 true，
        ;  触发符+Tab 再唤起无响应，且迟到的 Tab/Esc 会误删正文/多发 Esc）
        ih.Wait(wait / 1000)
        typed  := ih.Input
        reason := ih.EndReason
        endKey := ih.EndKey
    } finally {
        gSlashBusy := false
    }

    if (reason = "EndKey" && endKey = "Tab") {
        ; 只把「无空白、长度合理的关键字」当成命令，避免误伤正常输入
        ; （允许 @、大写、中文等，按 Tab 即视为想唤起搜索）
        if (RegExMatch(typed, "\s") || StrLen(typed) > 40) {
            SetTimer(() => Send("{Tab}"), -20)
            return
        }
        ; 关键：不能在热字符串回调线程里发按键——此时键盘钩子尚未从 Tab 收尾中恢复，
        ; 注入的按键会被延迟数秒甚至丢弃（实测 Backspace / Ctrl+C 全部失效）。
        ; 交给定时器在新线程执行，按键投递才可靠。
        DebugLog("slash Tab: typed=" quoted(typed) " -> dispatch timer")
        SetTimer(SlashFinish.Bind(typed), -20)
        return
    }
    if (reason = "EndKey" && endKey = "Escape")
        SetTimer(() => Send("{Escape}"), -20)
}

; Tab 收尾后的善后：删除「触发符+关键字」并打开搜索面板
; 运行在定时器线程（非热字符串回调线程）
SlashFinish(typed) {
    global gSlashDeleted, gSlashErase
    key := Trim(Store.cfg["slash_key"])
    expected := key . typed
    n := StrLen(expected)
    DebugLog("slash finish: typed=" quoted(typed) " n=" n " active=[" SafeWinTitle("A") "] class=" SafeWinClass("A"))

    removed := false

    ; ---------- 路径 A：窗口消息删除（不注入任何按键） ----------
    ; EM_GETSEL 取光标位置 → 校验光标左侧正是「/关键字」→ EM_SETSEL 选中 → WM_CLEAR 删除。
    ; 消息是同步返回的，删除结果可立即用文本长度校验，适用于所有标准 Edit / RichEdit 控件。
    ; 注意：InputHook 的 V 模式会把作为结束键的 Tab 也打进文档（光标左侧多一个 \t），
    ; 比对时先跳过它，并连同该 Tab 一起删除（它本来就是触发键，不该留在正文里）。
    try {
        ctl := ControlGetFocus("A")
        ch  := ControlGetHwnd(ctl, "A")
        sel := SendMessage(0x00B0, 0, 0, , "ahk_id " ch)      ; EM_GETSEL
        cp  := sel & 0xFFFF
        before := ControlGetText(ctl, "A")
        endIdx := cp
        extra  := 0
        if (endIdx > 0 && SubStr(before, endIdx, 1) = "`t") {
            endIdx -= 1                                       ; 跳过光标左侧的 Tab
            extra  := 1
        }
        seg := (endIdx >= n) ? SubStr(before, endIdx - n + 1, n) : ""
        if (seg = expected) {
            SendMessage(0x00B1, endIdx - n, endIdx + extra, , "ahk_id " ch)  ; EM_SETSEL
            SendMessage(0x0303, 0, 0, , "ahk_id " ch)                        ; WM_CLEAR
            Sleep(40)
            after := ControlGetText(ctl, "A")
            removed := (StrLen(after) = StrLen(before) - n - extra)
        }
        DebugLog("pathA: ctl=" ctl " cp=" cp " tab=" extra " seg=" quoted(seg) " removed=" (removed ? 1 : 0))
    } catch as e {
        DebugLog("pathA err: " e.Message)
    }

    ; ---------- 路径 B：按键删除（兜底，适用于不支持消息删除的控件） ----------
    if !removed {
        cls := ""
        try cls := WinGetClass("A")
        isConsole := (cls = "ConsoleWindowClass" || cls = "CASCADIA_HOSTING_WINDOW_CLASS" || cls = "mintty")
        oldClip := ClipboardAll()
        oldText := ""
        try oldText := A_Clipboard
        selected := false
        if !isConsole {
            Send("+{Left " n "}")      ; 选中「/关键字」
            Sleep(40)
            Send("^c")                 ; 复制用于校验
            loop 40 {
                Sleep(25)
                cur := ""
                try cur := A_Clipboard
                if (cur = expected && oldText != expected) {
                    selected := true
                    break
                }
            }
            if !selected {
                copied := ""
                try copied := A_Clipboard
                DebugLog("pathB copy=" quoted(copied) " old=" quoted(oldText))
            }
            A_Clipboard := oldClip     ; 还原用户剪贴板
        }
        if selected {
            Send("{Delete}")           ; 删掉选区；若被吞，粘贴时 ^v 替换选区，结果一致
        } else {
            Send("{Backspace " n "}")  ; 兜底：传统退格删除
        }
        DebugLog("pathB: selected=" (selected ? 1 : 0))
    }

    Sleep(60)
    gSlashDeleted := expected      ; 记下删掉的内容，Esc 取消时还原
    gSlashErase := 0
    ShowSearch(typed, 0)
    DebugLog("slash panel-shown")
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
    lblMgr := I18n.T("tray.manager")
    A_TrayMenu.Add(I18n.T("tray.search"), (*) => ShowSearch())
    A_TrayMenu.Add(lblMgr, (*) => Manager.Show())
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
            sub.Add(I18n.T("tray.empty"), (*) => 0)
        A_TrayMenu.Add(c, sub)
    }

    A_TrayMenu.Add()
    A_TrayMenu.Add(I18n.T("tray.reload"), (*) => ReloadAll())
    A_TrayMenu.Add(I18n.T("tray.rescript"), (*) => Reload())
    A_TrayMenu.Add(App.Name " v" App.Version " · " I18n.T("tray.about"), (*) => ShowAbout())
    A_TrayMenu.Add(I18n.T("tray.exit"), (*) => ExitApp())
    A_TrayMenu.ClickCount := 2
    A_TrayMenu.Default := lblMgr
}

ShowAbout() {
    body := App.Name " v" App.Version "`n" I18n.T("about.body", Store.DataDir)
    MsgBox(body, I18n.T("tray.about"), "Iconi")
}

ReloadAll() {
    Store.LoadDb()
    RefreshHotstrings()
    RegisterSlashTrigger()
    BuildTrayMenu()
    if Manager.ready
        Manager.RefreshCats()
    ToolTip(I18n.T("act.reloaded"))
    SetTimer(() => ToolTip(), -1500)
}

; ---------- 热键 ----------
RegisterHotkeys() {
    try Hotkey(Store.cfg["hotkey_search"], (*) => ShowSearch())
    try Hotkey(Store.cfg["hotkey_manager"], (*) => Manager.Show())
}

; erase：由「触发符+Tab」唤起时，目标窗口里遗留的字符数（插入前删掉）；普通唤起为 0
ShowSearch(kw := "", erase := 0, activate := true) {
    global gLastFocusHwnd, gSlashErase
    gSlashErase := erase
    gLastFocusHwnd := WinExist("A")
    SearchPanel.Show(kw, activate)
}
