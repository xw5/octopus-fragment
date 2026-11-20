#Requires AutoHotkey v2.0
; ============================================================
; SearchPanel.ahk - 快速搜索面板 (无边框、置顶、跟随显示)
; ============================================================

class SearchPanel {
    static Title   := "Octopus Fragment · Quick Search"
    static gui     := ""
    static edit    := ""
    static list    := ""
    static hint    := ""
    static results := Array()
    static ready   := false

    static Build() {
        if (SearchPanel.ready)
            return
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +Border", SearchPanel.Title)
        g.BackColor := "FAFAFA"
        g.MarginX := 8
        g.MarginY := 8
        g.SetFont("s11")

        ed := g.Add("Edit", "x8 y8 w560 h32 -VScroll", "")
        g.SetFont("s10")
        lb := g.Add("ListBox", "x8 y46 w560 h260", [])

        hint := g.Add("Text", "x8 y312 w560 h20 Center c808080", I18n.T("search.hint"))

        ed.OnEvent("Change", (*) => SearchPanel.Filter())
        lb.OnEvent("DoubleClick", (*) => SearchPanel.Confirm())

        SearchPanel.gui := g
        SearchPanel.edit := ed
        SearchPanel.list := lb
        SearchPanel.hint := hint
        SearchPanel.ready := true
    }

    ; 切换语言时销毁重建（Gui 文本无法整体重设，只能重建）
    static Reset() {
        try {
            if (SearchPanel.ready && IsObject(SearchPanel.gui) && SearchPanel.gui)
                SearchPanel.gui.Destroy()
        }
        SearchPanel.gui := ""
        SearchPanel.edit := ""
        SearchPanel.list := ""
        SearchPanel.hint := ""
        SearchPanel.results := Array()
        SearchPanel.ready := false
    }

    static Show(kw := "") {
        SearchPanel.Build()
        ed := SearchPanel.edit
        ed.Value := kw
        SearchPanel.Filter()
        sw := A_ScreenWidth
        sh := A_ScreenHeight
        w := 576
        h := 340
        x := (sw - w) // 2
        y := (sh // 4)
        SearchPanel.gui.Show("x" x " y" y " w" w " h" h)
        ed.Focus()
        ; 预填关键字时光标放到末尾，方便继续输入
        try SendMessage(0x00B1, -1, -1, ed)
    }

    static Hide() {
        if (SearchPanel.ready)
            SearchPanel.gui.Hide()
    }

    ; Esc 取消：触发符+关键字仍原样留在目标窗口里，直接关面板即可
    static Cancel() {
        global gSlashErase, gLastFocusHwnd
        gSlashErase := 0
        SearchPanel.Hide()
        if (gLastFocusHwnd && WinExist("ahk_id " gLastFocusHwnd))
            WinActivate("ahk_id " gLastFocusHwnd)
    }

    static IsVisible() {
        return (SearchPanel.ready && WinActive(SearchPanel.Title))
    }

    static Filter() {
        kw := Trim(SearchPanel.edit.Value)
        limit := Store.cfg["search_limit"]
        list := Store.Search(kw)
        if (list.Length > limit) {
            tmp := Array()
            loop limit
                tmp.Push(list[A_Index])
            list := tmp
        }
        SearchPanel.results := list
        labels := Array()
        for sn in list {
            label := sn["title"] . "  (" . I18n.TypeName(sn) . ")  " . sn["trigger"] . "  " . sn["category"]
            labels.Push(label)
        }
        lb := SearchPanel.list
        lb.Delete()
        if (labels.Length)
            lb.Add(labels)
        else
            lb.Add(I18n.T("search.empty"))
        if (labels.Length)
            lb.Choose(1)
    }

    static Move(step) {
        if (!SearchPanel.IsVisible())
            return
        lb := SearchPanel.list
        n := SearchPanel.results.Length
        if (n = 0)
            return
        cur := lb.Value
        next := cur + step
        if (next < 1)
            next := n
        if (next > n)
            next := 1
        lb.Choose(next)
    }

    static Confirm() {
        if (!SearchPanel.IsVisible())
            return
        idx := SearchPanel.list.Value
        if (idx < 1 || idx > SearchPanel.results.Length)
            return
        sn := SearchPanel.results[idx]
        PasteSnippet(sn["id"])
    }
}
