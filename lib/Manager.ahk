#Requires AutoHotkey v2.0
; ============================================================
; Manager.ahk - 片段管理主窗口 + 编辑窗口 + 设置窗口
; ============================================================

class Manager {
    static Title   := "octopus-fragment 片段管理"
    static gui     := ""
    static lv      := ""
    static search  := ""
    static status  := ""
    static curCat  := "全部"      ; 当前选中的分类 Tab
    static tabBtns := Array()     ; [{ctl, cat, x, w}, ...]
    static tabCats := Array()     ; 全部分类（含「全部」）
    static tabWs   := Array()     ; 每个 Tab 的宽度
    static tabOff  := 0           ; 首个可见 Tab 下标（0 基）
    static tabPlaced := 0         ; 当前可见 Tab 数量
    static addTab  := ""          ; 分类行最右的「＋」按钮
    static arrowL  := ""          ; 左滚动
    static arrowR  := ""          ; 右滚动
    static ul      := ""          ; 选中 Tab 的下划线指示条
    static ids     := Array()   ; 行号 -> snippet id
    static ready   := false
    static ctxOpen := false     ; 右键菜单正在显示（防重复弹出）
    static ctxFromUp := false    ; 本次右键已由 NM_RCLICK 处理

    static Build() {
        if (Manager.ready)
            return

        g := Gui("+Resize", Manager.Title)
        g.BackColor := "FFFFFF"
        g.MarginX := 10
        g.MarginY := 10

        ; 顶部：搜索
        g.Add("Text", "x10 y12 w40 h24 +0x200", "搜索")
        ed := g.Add("Edit", "x52 y10 w440 h26")
        g.Add("Button", "x500 y9 w70 h26", "刷新").OnEvent("Click", (*) => Manager.RefreshCats())
        more := g.Add("Button", "x578 y9 w68 h26", "⋯")
        more.OnEvent("Click", (*) => Manager.ShowMoreMenu())

        ; 分类 Tab 栏占位 y44 h26，按钮在 BuildTabs() 中动态生成
        arrowL := g.Add("Button", "x556 y44 w26 h26 Hidden", "‹")
        arrowL.OnEvent("Click", (*) => Manager.ScrollTabs(-1))
        arrowR := g.Add("Button", "x586 y44 w26 h26 Hidden", "›")
        arrowR.OnEvent("Click", (*) => Manager.ScrollTabs(1))
        addTab := g.Add("Button", "x616 y44 w28 h26", "＋")
        addTab.OnEvent("Click", (*) => Manager.AddCategory())

        ; ListView
        lv := g.Add("ListView", "x10 y78 w636 h350",
            ["名称", "缩写", "分类", "类型", "标签", "次数"])

        st := g.Add("Text", "x10 y436 w636 h20 c808080", "")

        ed.OnEvent("Change", (*) => Manager.Refresh())
        lv.OnEvent("DoubleClick", (*) => Manager.InsertSelected())
        g.OnEvent("Close", (gObj, *) => gObj.Hide())
        ; 列表右键菜单
        ; 每一项上右键：控件通知 NM_RCLICK（最可靠，不依赖控件是否转发 WM_CONTEXTMENU）
        lv.OnNotify(-5, (*) => Manager.OnListRClick())
        ; 空白处右键 / 键盘菜单键：WM_CONTEXTMENU
        OnMessage(0x007B, (w, l, m, h) => Manager.OnContextMenu(w, l, m, h))

        Manager.gui := g
        Manager.lv := lv
        Manager.search := ed
        Manager.status := st
        Manager.addTab := addTab
        Manager.arrowL := arrowL
        Manager.arrowR := arrowR
        Manager.ready := true
        Manager.RefreshCats()
        ; 鼠标滚轮在 Tab 行上横向滚动
        OnMessage(0x020A, (w, l, m, h) => Manager.OnWheel(w, l, m, h))
    }

    static Show() {
        Manager.Build()
        Manager.RefreshCats()
        Manager.gui.Show("w660 h460 Center")
    }

    ; 「⋯」下拉菜单：原来底部那排按钮都收进来
    static ShowMoreMenu() {
        m := Menu()
        m.Add("新增片段", (*) => Editor.Open(""))
        m.Add("编辑选中", (*) => Manager.EditSelected())
        m.Add("删除选中", (*) => Manager.DeleteSelected())
        m.Add("复制选中", (*) => Manager.DuplicateSelected())
        m.Add("插入选中", (*) => Manager.InsertSelected())
        m.Add()
        m.Add("设置", (*) => Settings.Open())
        m.Add("打开数据目录", (*) => Run('explorer.exe "' Store.DataDir '"'))
        m.Add("重新加载数据", (*) => ReloadAll())
        m.Add("重载脚本（改代码后用）", (*) => Reload())
        m.Add()
        m.Add("退出", (*) => ExitApp())
        if (Manager.SelectedId() = "") {
            m.Disable("编辑选中")
            m.Disable("删除选中")
            m.Disable("复制选中")
            m.Disable("插入选中")
        }
        m.Show()          ; 在鼠标处弹出，正好贴着「⋯」按钮下方
    }

    ; ---------- 列表右键菜单 ----------
    ; 右键点「某一项」：控件会给父窗口发 NM_RCLICK（比 WM_CONTEXTMENU 可靠，空白处不会走这里）
    static OnListRClick() {
        if (!Manager.ready || Manager.ctxOpen)
            return 0
        row := Manager.HitTestRow()
        if (row > 0)
            Manager.lv.Modify(row, "Select Focus Vis")
        Manager.ctxFromUp := true          ; 同一次右键后续可能到达的 WM_CONTEXTMENU 直接跳过
        Manager.ShowRowMenu(row > 0)
        return 0
    }

    ; 空白处右键 / 键盘菜单键（lParam = -1 表示键盘触发）
    static OnContextMenu(wParam, lParam, msg, hwnd) {
        if (!Manager.ready || Manager.ctxOpen)
            return
        if (wParam != Manager.lv.Hwnd && hwnd != Manager.lv.Hwnd)
            return

        ; lParam 是打包的屏幕坐标
        sx := lParam & 0xFFFF
        sy := (lParam >> 16) & 0xFFFF
        if (sx > 0x7FFF)
            sx -= 0x10000
        if (sy > 0x7FFF)
            sy -= 0x10000

        if (sx = -1 && sy = -1) {          ; 键盘菜单键：保持选中行不动
            Manager.ctxFromUp := false
            Manager.ShowRowMenu(Manager.SelectedId() != "", -1, -1)
            return 0
        }
        if (Manager.ctxFromUp) {           ; 这一下右键已经弹过菜单了
            Manager.ctxFromUp := false
            return 0
        }
        row := Manager.HitTestRow(sx, sy)
        if (row > 0)
            Manager.lv.Modify(row, "Select Focus Vis")
        Manager.ShowRowMenu(row > 0, sx, sy)
        return 0
    }

    ; 鼠标位置命中的行号（1 基，0 = 没命中）
    ; sx/sy 为屏幕坐标；不传则取当前鼠标（MouseGetPos 默认是活动窗口客户区坐标，必须先切到 Screen）
    static HitTestRow(sx := "", sy := "") {
        if (sx = "") {
            prev := A_CoordModeMouse
            CoordMode("Mouse", "Screen")
            MouseGetPos(&sx, &sy)
            CoordMode("Mouse", prev)
        }
        pt := Buffer(8, 0)
        NumPut("int", sx, pt, 0)
        NumPut("int", sy, pt, 4)
        DllCall("ScreenToClient", "ptr", Manager.lv.Hwnd, "ptr", pt)

        ; LVHITTESTINFO { POINT pt; UINT flags; int iItem; }  -> iItem 在偏移 12
        hi := Buffer(24, 0)
        NumPut("int", NumGet(pt, 0, "int"), hi, 0)
        NumPut("int", NumGet(pt, 4, "int"), hi, 4)
        DllCall("SendMessageW", "ptr", Manager.lv.Hwnd, "uint", 0x1012
            , "uptr", 0, "ptr", hi, "ptr")               ; LVM_HITTEST
        return NumGet(hi, 12, "int") + 1
    }

    static ShowRowMenu(hasRow, sx := -1, sy := -1) {
        m := Menu()
        m.Add("插入", (*) => Manager.InsertSelected())
        m.Add("编辑", (*) => Manager.EditSelected())
        m.Add("删除", (*) => Manager.DeleteSelected())
        m.Add("复制", (*) => Manager.DuplicateSelected())
        if !hasRow {
            m.Disable("插入")
            m.Disable("编辑")
            m.Disable("删除")
            m.Disable("复制")
        }
        Manager.ctxOpen := true
        try {
            if (sx = -1 && sy = -1)
                m.Show()
            else
                m.Show(sx, sy)
        } finally {
            Manager.ctxOpen := false
        }
    }

    ; 复制选中项：插到原项前面，名称 = 原名 + 序号
    static DuplicateSelected() {
        id := Manager.SelectedId()
        if (id = "")
            return MsgBox("请先选择一个片段。", Manager.Title, "Iconi")
        newId := Store.Duplicate(id)
        if (newId = "")
            return
        RefreshHotstrings()
        BuildTrayMenu()
        Manager.RefreshCats()
        Manager.SelectId(newId)
        ToolTip("已复制：" Store.Get(newId)["title"])
        SetTimer(() => ToolTip(), -1500)
    }

    ; 按 id 选中对应行（复制后定位到新行）
    static SelectId(id) {
        for i, sid in Manager.ids {
            if (sid = id) {
                Manager.lv.Modify(i, "Select Focus Vis")
                return
            }
        }
    }

    static RefreshCats() {
        if (!Manager.ready)
            return
        cats := Array("全部")
        for c in Store.Categories()
            cats.Push(c)
        ; 当前分类已不存在 -> 回退到「全部」
        found := false
        for c in cats {
            if (c = Manager.curCat) {
                found := true
                break
            }
        }
        if !found
            Manager.curCat := "全部"
        Manager.BuildTabs(cats)
        Manager.Refresh()
    }

    ; 重建分类 Tab 栏（控件复用池，AHK v2 无法单独 Destroy 控件）
    static BuildTabs(cats) {
        g := Manager.gui
        while (Manager.tabBtns.Length < cats.Length) {
            b := g.Add("Button", "x0 y44 w80 h26 Hidden", "")
            ; 用事件首参定位控件（避免闭包共享循环变量），再取真实分类名
            b.OnEvent("Click", (ctrl, *) => Manager.OnTabClick(ctrl))
            Manager.tabBtns.Push(Map("ctl", b, "cat", "", "x", 0, "w", 0))
        }
        ; 选中指示条最后创建，保证盖在 Tab 之上
        if (Manager.ul = "")
            Manager.ul := g.Add("Progress", "x10 y71 w60 h3 Hidden c1668DC", 100)

        Manager.tabCats := cats
        ws := Array()
        for c in cats
            ws.Push(Max(64, StrLen(c) * 14 + 28))
        Manager.tabWs := ws
        if (Manager.tabOff > cats.Length - 1)
            Manager.tabOff := Max(0, cats.Length - 1)
        Manager.tabOff := Manager.NormalizeOff(Manager.tabOff)
        Manager.LayoutTabs()
    }

    ; Tab 可视区宽度：溢出时给 ‹ › ＋ 让位
    static TabViewport() {
        total := 0
        for w in Manager.tabWs
            total += w + 4
        if (total > 636 - 28 - 4)
            return 646 - 28 - 4 - 2 * (26 + 4) - 10
        return 636
    }

    ; 最后一个可用偏移：保证滚到底时可见区被填满
    static MaxTabOff() {
        n := Manager.tabCats.Length
        ws := Manager.tabWs
        avail := Manager.TabViewport()
        sum := 0
        i := n
        while (i >= 1) {
            if (sum + ws[i] > avail)
                break
            sum += ws[i] + 4
            i--
        }
        return Max(0, i)
    }

    ; 按 tabOff 摆放可见 Tab；溢出时显示 ‹ › 箭头（滚轮同样可用）
    static LayoutTabs() {
        cats := Manager.tabCats
        ws := Manager.tabWs
        n := cats.Length

        total := 0
        for w in ws
            total += w + 4
        needScroll := (total > 636 - 28 - 4)

        viewW := Manager.TabViewport()
        maxRight := 10 + viewW

        x := 10
        placed := 0
        i := Manager.tabOff + 1
        while (i <= n) {
            w := ws[i]
            clipped := false
            if (placed = 0 && x + w > maxRight) {   ; 单个超长 Tab 截断到可视宽度
                w := maxRight - x
                clipped := true
            }
            if (x + w > maxRight)
                break
            t := Manager.tabBtns[i]
            t["ctl"].Text := clipped ? Manager.ClipLabel(cats[i], w) : cats[i]
            t["ctl"].Move(x, 44, w, 26)
            t["ctl"].Visible := true
            t["cat"] := cats[i]
            t["x"] := x
            t["w"] := w
            t["clipped"] := clipped
            x += w + 4
            placed++
            i++
        }
        ; 右侧剩余空间露出下一个 Tab 的开头，提示「还有更多」
        if (i <= n) {
            gap := maxRight - (x - 4)
            ; 露出的是最后一个 Tab 但放不下：滚到尾部，让它完整显示
            if (i = n && gap < ws[n]) {
                off := Manager.MaxTabOff()
                if (off > Manager.tabOff) {
                    Manager.tabOff := off
                    Manager.LayoutTabs()
                    return
                }
            }
            if (gap >= 14) {
                t := Manager.tabBtns[i]
                w := gap - 2
                t["ctl"].Text := Manager.ClipLabel(cats[i], w)
                t["ctl"].Move(x, 44, w, 26)
                t["ctl"].Visible := true
                t["cat"] := cats[i]
                t["x"] := x
                t["w"] := w
                t["clipped"] := true
                placed++
                x += w + 4
                i++
            }
        }
        Manager.tabPlaced := placed

        ; 隐藏未摆放的（含复用池里多出来的）
        loop Manager.tabBtns.Length {
            idx := A_Index
            if (idx < Manager.tabOff + 1 || idx > Manager.tabOff + placed) {
                t := Manager.tabBtns[idx]
                t["ctl"].Visible := false
                t["cat"] := ""
            }
        }

        if needScroll {
            Manager.arrowL.Move(556, 44, 26, 26)
            Manager.arrowR.Move(586, 44, 26, 26)
            Manager.arrowL.Visible := true
            Manager.arrowR.Visible := true
            Manager.arrowL.Enabled := (Manager.tabOff > 0)
            Manager.arrowR.Enabled := (Manager.tabOff < Manager.MaxTabOff())
            Manager.addTab.Move(616, 44, 28, 26)
        } else {
            Manager.arrowL.Visible := false
            Manager.arrowR.Visible := false
            Manager.addTab.Move(Min(x, 616), 44, 28, 26)
        }
        Manager.HighlightTabs()
    }

    ; 点击 Tab：按控件的真实分类名处理（按钮文字可能被截断加 … ）
    static OnTabClick(ctrl) {
        for t in Manager.tabBtns {
            if (t["ctl"].Hwnd = ctrl.Hwnd) {
                Manager.SelectCat(t["cat"])
                return
            }
        }
    }

    ; 按像素宽度粗略截断文字，加省略号提示未显示全
    static ClipLabel(text, w) {
        maxCh := Max(1, Floor((w - 30) / 14))
        if (StrLen(text) <= maxCh)
            return text
        return SubStr(text, 1, maxCh) "…"
    }

    ; 预演某个偏移下的排版结果（不绘制），用于判断该偏移是否可用
    static PlanLayout(off) {
        cats := Manager.tabCats
        ws := Manager.tabWs
        n := cats.Length
        maxRight := 10 + Manager.TabViewport()
        x := 10
        placed := 0
        i := off + 1
        while (i <= n) {
            w := ws[i]
            if (placed = 0 && x + w > maxRight)
                w := maxRight - x
            if (x + w > maxRight)
                break
            x += w + 4
            placed++
            i++
        }
        return Map("placed", placed, "next", i, "gap", maxRight - (x - 4))
    }

    ; 该偏移是否合法：不能把「最后一个 Tab」截断在右边缘
    static OffsetOk(off) {
        p := Manager.PlanLayout(off)
        n := Manager.tabCats.Length
        if (p["next"] <= n && p["next"] = n && p["gap"] < Manager.tabWs[n])
            return false
        return true
    }

    ; 把偏移收敛到合法范围（越界/非法时向左回退）
    static NormalizeOff(o) {
        o := Max(0, Min(o, Manager.MaxTabOff()))
        while (o > 0 && !Manager.OffsetOk(o))
            o--
        return o
    }

    static ScrollTabs(d) {
        n := Manager.tabCats.Length
        if (n = 0)
            return
        maxOff := Manager.MaxTabOff()
        o := Min(maxOff, Max(0, Manager.tabOff + d))
        ; 跳过非法偏移：向右跳过尾部截断位，向左同理
        if (d > 0) {
            while (o <= maxOff && !Manager.OffsetOk(o))
                o++
        } else if (d < 0) {
            while (o >= 0 && !Manager.OffsetOk(o))
                o--
        }
        if (o > maxOff || o < 0 || !Manager.OffsetOk(o))
            o := Manager.tabOff
        if (o = Manager.tabOff)
            return
        Manager.tabOff := o
        Manager.LayoutTabs()
    }

    ; 鼠标滚轮：在 Tab 行区域内滚动分类
    static OnWheel(wParam, lParam, msg, hwnd) {
        if (!Manager.ready)
            return
        if !WinActive("ahk_id " Manager.gui.Hwnd)
            return
        MouseGetPos(&mx, &my)
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " Manager.gui.Hwnd)
        if (mx < cx || mx > cx + cw || my < cy || my > cy + ch)
            return
        ry := my - cy
        if (ry < 40 || ry > 78)
            return
        delta := (wParam >> 16) & 0xFFFF
        if (delta > 0x7FFF)
            delta -= 0x10000
        Manager.ScrollTabs(delta > 0 ? -1 : 1)
        return 1
    }

    ; 新增分类
    static AddCategory() {
        ib := InputBox("分类名称（已存在则直接切换）", "新增分类", "w320 h130")
        if (ib.Result != "OK")
            return
        name := Trim(ib.Value)
        if (name = "")
            return
        if Store.AddCategory(name)
            BuildTrayMenu()
        Manager.RefreshCats()
        Manager.SelectCat(name)
        if Editor.ready
            Editor.RefreshCats(Editor.cat.Text)
    }

    static SelectCat(name) {
        name := Trim(name)
        if (name = "")
            name := "全部"
        Manager.curCat := name
        ; 保证选中项在可视范围内
        idx := 0
        for i, c in Manager.tabCats {
            if (c = name) {
                idx := i
                break
            }
        }
        if (idx > 0) {
            last := Manager.tabOff + Manager.tabPlaced      ; 1 基的可见末位
            clippedEnd := (Manager.tabBtns.Has(idx) && Manager.tabBtns[idx].Has("clipped")
                && Manager.tabBtns[idx]["clipped"])
            if (idx <= Manager.tabOff || idx > last || clippedEnd) {
                Manager.tabOff := Manager.NormalizeOff(idx - 1)
                Manager.LayoutTabs()
            }
        }
        Manager.HighlightTabs()
        Manager.Refresh()
    }

    static HighlightTabs() {
        found := false
        for t in Manager.tabBtns {
            b := t["ctl"]
            if (t["cat"] = Manager.curCat) {
                b.SetFont("s10 bold c1668DC")
                b.Opt("-Default")
                ; 下划线跟随选中 Tab
                if Manager.ul {
                    Manager.ul.Move(t["x"], 71, t["w"], 3)
                    Manager.ul.Visible := true
                }
                found := true
            } else {
                b.SetFont("s10 c505050")
                b.Opt("-Default")
            }
        }
        if (!found && Manager.ul)
            Manager.ul.Visible := false
    }

    static Refresh() {
        if (!Manager.ready)
            return
        kw := Trim(Manager.search.Value)
        cat := (Manager.curCat = "" || Manager.curCat = "全部") ? "" : Manager.curCat
        list := Store.Search(kw, cat)
        lv := Manager.lv
        lv.Delete()
        Manager.ids := Array()
        for sn in list {
            typeName := sn["type"] != "text"
                ? (sn["type"] = "image" ? "图片" : "文件")
                : (Template.HasVars(sn.Has("content") ? sn["content"] : "") ? "文本·变量" : "文本")
            lv.Add("", sn["title"], sn["trigger"], sn["category"], typeName,
                sn.Has("tags") ? sn["tags"] : "", sn.Has("usage") ? sn["usage"] : 0)
            Manager.ids.Push(sn["id"])
        }
        lv.ModifyCol()
        lv.ModifyCol(1, 180)
        lv.ModifyCol(2, 90)
        lv.ModifyCol(3, 90)
        lv.ModifyCol(4, 76)
        lv.ModifyCol(5, 134)
        lv.ModifyCol(6, 50, "Integer")
        Manager.status.Text := (list.Length > 0)
            ? "共 " list.Length " 个片段    数据文件：" Store.DbFile
            : "该分类下暂无片段    数据文件：" Store.DbFile
    }

    static SelectedId() {
        if (!Manager.ready)
            return ""
        row := Manager.lv.GetNext(0, "F")
        if (row = 0)
            return ""
        return Manager.ids[row]
    }

    static EditSelected() {
        id := Manager.SelectedId()
        if (id = "")
            return MsgBox("请先选择一个片段。", Manager.Title, "Iconi")
        Editor.Open(id)
    }

    static DeleteSelected() {
        id := Manager.SelectedId()
        if (id = "")
            return MsgBox("请先选择一个片段。", Manager.Title, "Iconi")
        sn := Store.Get(id)
        if MsgBox("确定删除片段「" sn["title"] "」？`n此操作不可恢复。", Manager.Title, "YesNo Icon!") != "Yes"
            return
        Store.Delete(id)
        RefreshHotstrings()
        BuildTrayMenu()
        Manager.RefreshCats()
    }

    static InsertSelected() {
        id := Manager.SelectedId()
        if (id = "")
            return
        Manager.gui.Hide()
        PasteSnippet(id)
    }
}

; ============================================================
; Editor - 新增 / 编辑片段
; ============================================================
class Editor {
    static Title  := "编辑片段"
    static gui    := ""
    static editing:= ""
    static id     := ""
    static titleEdit := ""
    static trig   := ""
    static cat    := ""
    static type   := ""
    static content:= ""
    static spec   := ""
    static tags   := ""
    static file   := ""
    static capturedFile := ""
    static hint   := ""          ; 动态变量标签后的「?」帮助
    static hintSize := 20        ; 「?」控件边长
    static specLabel := ""       ; 动态变量标签控件（量宽度用）
    static phBtn  := ""          ; 「插入占位符」按钮（悬停下拉变量）
    static tplBtn := ""          ; 「插入模板」按钮（悬停下拉 text/memo/select 模板）
    static tipOn  := false       ; 悬浮教程是否正在显示
    static hoverKey := ""        ; 当前停留的悬浮目标：hint / ph / tpl
    static hoverT0  := 0         ; 进入当前悬浮目标的时刻
    static popOpen  := ""        ; 本轮停留已弹出的下拉（移开才允许再弹）
    static menuOpen := false     ; 本窗口弹出的菜单是否仍显示
    static touched := Map()      ; 曾被聚焦过的编辑框 Hwnd（插入位置判断用）
    static tickFn := ""          ; 悬浮轮询定时器回调（复用同一对象）
    static ready  := false

    static Build() {
        if (Editor.ready)
            return
        g := Gui("+Resize", Editor.Title)
        g.BackColor := "FFFFFF"
        g.MarginX := 10
        g.MarginY := 10
        g.SetFont("s10")

        g.Add("Text", "x10 y12 w60 h22 +0x200", "名称")
        t := g.Add("Edit", "x76 y10 w800 h24")
        g.Add("Text", "x10 y44 w60 h22 +0x200", "缩写")
        tr := g.Add("Edit", "x76 y42 w200 h24")
        g.Add("Text", "x290 y44 w40 h22 +0x200", "分类")
        ; 分类下拉框由 RefreshCats() 创建（需按分类数量决定展开高度）
        g.Add("Text", "x10 y76 w60 h22 +0x200", "类型")
        ; DropDownList 的 h 是「编辑框 + 展开列表」的总高，h24 只够半行，列表会被裁掉
        ty := g.Add("DropDownList", "x76 y73 w160 h" (24 + 3 * 20 + 4), ["文本", "图片", "文件"])
        g.Add("Text", "x250 y76 w60 h22 +0x200", "标签")
        tg := g.Add("Edit", "x316 y74 w380 h24")

        g.Add("Text", "x10 y108 w420 h22 +0x200", "内容（type=文本 时粘贴此内容）")
        ; 「插入占位符」：点击插入 {{}} 且光标停在中间；悬停 0.4s 下拉已定义的动态变量
        phb := g.Add("Button", "x440 y106 w108 h24", "插入占位符 ▾")
        phb.OnEvent("Click", (*) => Editor.OnPhClick())
        ct := g.Add("Edit", "x10 y130 w700 h160 +WantReturn VScroll", "")
        ct.OnEvent("Focus", (*) => Editor.MarkTouched(ct))
        g.Add("Button", "x720 y130 w160 h32", "从剪贴板捕获").OnEvent("Click", (*) => Editor.Capture())
        ; 右侧信息区：宽 160 自动换行，高度留足，避免文件路径被截断
        f := g.Add("Text", "x720 y172 w160 h56 c606060", "资源：无")
        g.Add("Text", "x720 y234 w160 h76 c909090", "提示：图片/文件请先复制到剪贴板，再点「从剪贴板捕获」。")

        ; 动态变量规格（标签尽量短，给右侧「?」和「插入模板」留出空位）
        specLabel := "动态变量（可选）：每行 名称|标签|类型|默认值或选项   类型 text/memo/select"
        lb := g.Add("Text", "x10 y298 w720 h20 +0x200", specLabel)
        ; 「?」帮助：鼠标移上去显示动态变量教程（点击可弹窗查看/复制）
        hq := Editor.MakeHintCtrl(g)
        hq.OnEvent("Click", (*) => MsgBox(Editor.HelpText, "动态变量使用教程", "Iconi"))
        ; 「插入模板」：点击或悬停 0.4s 下拉 text / memo / select 三种模板
        tplb := g.Add("Button", "x560 y295 w100 h24", "插入模板 ▾")
        tplb.OnEvent("Click", (*) => Editor.OnTplClick())
        sp := g.Add("Edit", "x10 y320 w700 h100 +WantReturn VScroll", "")
        sp.OnEvent("Focus", (*) => Editor.MarkTouched(sp))
        g.Add("Text", "x720 y320 w160 h104 c909090",
            "内置变量：`n{{date}} {{time}}`n{{datetime}}`n{{date:yyyyMMdd}}`n{{clipboard}}`n{{cursor}} 光标位置")

        g.Add("Button", "x710 y432 w80 h30", "保存").OnEvent("Click", (*) => Editor.Save())
        g.Add("Button", "x800 y432 w80 h30", "取消").OnEvent("Click", (*) => Editor.CloseDlg())
        g.OnEvent("Close", (gObj, *) => Editor.CloseDlg())

        Editor.gui := g
        Editor.hint := hq
        Editor.specLabel := lb
        Editor.phBtn := phb
        Editor.tplBtn := tplb
        Editor.titleEdit := t
        Editor.trig := tr
        Editor.type := ty
        Editor.tags := tg
        Editor.content := ct
        Editor.spec := sp
        Editor.file := f
        Editor.ready := true
        Editor.RefreshCats()
    }

    static Open(id := "") {
        Editor.Build()
        Editor.id := id
        Editor.editing := (id != "")
        Editor.touched := Map()      ; 每次打开重新判定「是否点过编辑框」

        if (id = "") {
            ; 新增：分类默认跟随管理窗口当前高亮的 Tab（「全部」时用第一个分类）
            want := Manager.curCat
            Editor.RefreshCats(want = "全部" ? "" : want)
            Editor.titleEdit.Value := ""
            Editor.trig.Value := ""
            Editor.type.Choose(1)
            Editor.tags.Value := ""
            Editor.content.Value := ""
            Editor.spec.Value := ""
            Editor.capturedFile := ""
            Editor.ShowRes("")
            Editor.gui.Title := "新增片段"
        } else {
            sn := Store.Get(id)
            ; 编辑：默认选中该片段自身的分类
            Editor.RefreshCats(sn["category"])
            Editor.titleEdit.Value := sn["title"]
            Editor.trig.Value := sn["trigger"]
            Editor.tags.Value := sn.Has("tags") ? sn["tags"] : ""
            Editor.content.Value := sn["type"] = "text" ? sn["content"] : ""
            Editor.spec.Value := sn.Has("fields") ? sn["fields"] : ""
            ty := sn["type"] = "text" ? 1 : (sn["type"] = "image" ? 2 : 3)
            Editor.type.Choose(ty)
            Editor.capturedFile := sn.Has("file") ? sn["file"] : ""
            Editor.ShowRes(Editor.capturedFile)
            Editor.gui.Title := "编辑片段 - " sn["title"]
        }
        Editor.gui.Show("w900 h480 Center")
        Editor.PlaceHint()
        Editor.StartHoverWatch()
    }

    ; ---------- 「?」帮助：悬浮显示动态变量教程 ----------
    static HelpText :=
        "动态变量使用教程`n`n"
        . "0) 快捷按钮：`n"
        . "    「插入占位符」点击=插入 {{}}（光标在中间）`n"
        . "    鼠标停在该按钮上 → 下拉已定义的变量，点选即插入`n"
        . "    「插入模板」点击或悬停 → 下拉 text / memo / select 模板`n`n"
        . "① 在「内容」里写占位符 {{变量名}}`n"
        . "    例：这是{{memo1}}测试`n`n"
        . "② 在「动态变量」里逐行定义（一行一个）：`n"
        . "    名称|标签|类型|默认值或选项`n"
        . "    下拉：select|选择题|select|选项1,选项2`n"
        . "    单行：name|姓名|text|张三`n"
        . "    多行：desc|说明|memo|默认内容`n`n"
        . "③ 类型：text 单行 / memo 多行 / select 下拉`n"
        . "    select 的第四列用英文逗号分隔选项`n`n"
        . "④ 内容里有、这里没定义的变量 → 自动弹单行输入框`n`n"
        . "⑤ 内置变量（无需定义）：`n"
        . "    {{date}} {{time}} {{datetime}}`n"
        . "    {{date:yyyyMMdd}} 自定义格式`n"
        . "    {{clipboard}} 剪贴板文本`n"
        . "    {{cursor}} 插入后光标位置"

    ; 「?」帮助控件：直接用问号字符（不用 Segoe MDL2 的 PUA 字形 —— 字体被替换时
    ; 会画成别的符号，这里要的是稳定的问号）；颜色同时写在控件选项和字体里，避免被覆盖
    static MakeHintCtrl(g) {
        c := g.Add("Text", "x620 y298 w" Editor.hintSize " h" Editor.hintSize " +0x201 c1668DC", "?")
        c.SetFont("s11 bold c1668DC", "Segoe UI")
        return c
    }

    ; 把「?」紧贴到标签文字末尾（按控件字体实测宽度，避免 DPI/字体不同错位）
    ; 实测值偏小约 10px（CJK 混排），这里留 18px 余量，避免「?」压住 label 最后一个字
    ; 「插入模板」按钮紧跟「?」，两者都不压到右侧信息栏
    static PlaceHint() {
        if (!Editor.ready || !Editor.hint || !Editor.specLabel)
            return
        w := 0
        try w := Editor.TextWidth(Editor.specLabel, Editor.specLabel.Text)
        if (w <= 0)
            return
        scale := Max(1, A_ScreenDPI / 96)          ; Gui 坐标是逻辑单位，GDI 量出来是物理像素
        x := Min(10 + Round(w / scale) + 22, 560)
        Editor.hint.Move(x, 298, Editor.hintSize, Editor.hintSize)
        if (Editor.tplBtn)
            Editor.tplBtn.Move(Min(x + Editor.hintSize + 10, 596), 295, 100, 24)
    }

    ; 用控件自身的字体量文字像素宽度
    static TextWidth(ctrl, text) {
        hdc := DllCall("GetDC", "ptr", ctrl.Hwnd, "ptr")
        if !hdc
            return 0
        hFont := DllCall("SendMessageW", "ptr", ctrl.Hwnd, "uint", 0x0031, "uptr", 0, "ptr", 0, "ptr")
        old := hFont ? DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr") : 0
        sz := Buffer(8, 0)
        DllCall("GetTextExtentPoint32W", "ptr", hdc, "wstr", text, "int", StrLen(text), "ptr", sz)
        if old
            DllCall("SelectObject", "ptr", hdc, "ptr", old, "ptr")
        DllCall("ReleaseDC", "ptr", ctrl.Hwnd, "ptr", hdc)
        return NumGet(sz, 0, "int")
    }

    ; 静态文本/按钮没有 hover 事件，用 180ms 轮询判断（开销可忽略，窗口隐藏即停）
    static StartHoverWatch() {
        Editor.tipOn := false
        Editor.hoverKey := ""
        Editor.hoverT0 := 0
        Editor.popOpen := ""
        Editor.menuOpen := false
        ; 静态方法不能直接当回调（会多出 this 参数）；且 SetTimer 靠函数对象识别定时器，
        ; 必须复用同一个对象，否则 SetTimer(...,0) 关不掉
        if (Editor.tickFn = "")
            Editor.tickFn := () => Editor.HoverTick()
        SetTimer(Editor.tickFn, 180)
    }

    static StopHoverWatch() {
        if (Editor.tickFn != "")
            SetTimer(Editor.tickFn, 0)
        Editor.ResetHover()
        Editor.menuOpen := false
    }

    static HideTip() {
        if (Editor.tipOn) {
            Editor.tipOn := false
            ToolTip()
        }
    }

    ; 清空停留状态（鼠标离开全部悬浮目标时调用）
    static ResetHover() {
        Editor.hoverKey := ""
        Editor.hoverT0 := 0
        Editor.popOpen := ""
        Editor.HideTip()
    }

    ; 鼠标当前停在哪个悬浮目标上（"" = 都不在）
    static HoverTarget() {
        if (Editor.hint && Editor.CursorOver(Editor.hint))
            return "hint"
        if (Editor.phBtn && Editor.CursorOver(Editor.phBtn))
            return "ph"
        if (Editor.tplBtn && Editor.CursorOver(Editor.tplBtn))
            return "tpl"
        return ""
    }

    ; 悬浮判定：? 停留 300ms 出教程；两个按钮停留 400ms 出下拉菜单
    static HoverTick() {
        if (!Editor.ready || !Editor.hint)
            return Editor.StopHoverWatch()

        ; 下拉菜单还开着：什么都不做，等它自己关（否则会反复弹/被自己关掉）
        if (Editor.menuOpen) {
            if WinExist("ahk_class #32768")
                return
            Editor.menuOpen := false
            ; 菜单关掉但鼠标没离开按钮 → 抑制重弹，直到鼠标移开再回来
            if (Editor.HoverTarget() = Editor.hoverKey)
                Editor.popOpen := Editor.hoverKey
            else
                Editor.ResetHover()
            return
        }

        ; 窗口不在前台（例如「?」点开了提示框）时不弹，避免 tooltip 盖住对话框
        if !WinActive("ahk_id " Editor.gui.Hwnd) {
            Editor.ResetHover()
            return
        }

        key := Editor.HoverTarget()
        if (key = "") {
            Editor.ResetHover()
            return
        }
        if (key != Editor.hoverKey) {          ; 换了目标 → 重新计时
            Editor.hoverKey := key
            Editor.hoverT0 := A_TickCount
            Editor.popOpen := ""
            Editor.HideTip()
            return
        }

        el := A_TickCount - Editor.hoverT0
        if (key = "hint") {
            if (Editor.tipOn || el < 300)
                return
            Editor.tipOn := true
            Editor.ShowTip()
            return
        }

        if (Editor.popOpen = key || el < 400)
            return
        Editor.HideTip()
        Editor.popOpen := key
        Editor.menuOpen := true
        if (key = "ph")
            Editor.ShowVarMenu()
        else
            Editor.ShowTplMenu()
    }

    ; ---------- 在按钮下方弹菜单 ----------
    ; Menu.Show 的坐标默认相对「活动窗口客户区」，这里临时切换到屏幕坐标
    static PopAt(ctrl, m) {
        cx := 0, cy := 0, cw := 0, ch := 0
        ctrl.GetPos(&cx, &cy, &cw, &ch)
        pt := Editor.ToScreen(cx, cy + ch + 2)
        prev := A_CoordModeMenu
        CoordMode("Menu", "Screen")
        try {
            m.Show(NumGet(pt, 0, "int"), NumGet(pt, 4, "int"))
        } finally {
            CoordMode("Menu", prev)
        }
    }

    ; ---------- 插入文本到 Edit 的光标处 ----------
    ; caretBack：插入完成后光标回退的字符数（{{}} 用 2，让光标停在两个花括号中间）
    ; 注意：点按钮会让 Edit 失焦，但控件内部仍保留上次的选区，所以先读选区再聚焦
    static InsertTextAt(ctrl, text, caretBack := 0) {
        if !ctrl
            return
        hwnd := ctrl.Hwnd
        buf := Buffer(8, 0)
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x00B0, "ptr", buf.Ptr, "ptr", buf.Ptr + 4, "ptr")
        selS := NumGet(buf, 0, "int")
        selE := NumGet(buf, 4, "int")
        if (selS < 0 || !Editor.touched.Has(hwnd)) {
            ; 从未聚焦过时 EM_GETSEL 恒为 0，会插到开头 → 追加到末尾
            len := DllCall("SendMessageW", "ptr", hwnd, "uint", 0x000E, "ptr", 0, "ptr", 0, "ptr")
            selS := len
            selE := len
        }
        ctrl.Focus()
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x00B1, "ptr", selS, "ptr", selE, "ptr")
        ; EM_REPLACESEL 覆盖当前选区，wParam=1 保留撤销记录
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x00C2, "uptr", 1, "ptr", StrPtr(text), "ptr")
        pos := selS + StrLen(text) - (caretBack > 0 ? caretBack : 0)
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x00B1, "ptr", pos, "ptr", pos, "ptr")
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x00B7, "ptr", 0, "ptr", 0, "ptr")
    }

    ; 记录编辑框曾被聚焦（用来区分「从未点过」和「光标在开头」）
    static MarkTouched(ctrl) {
        Editor.touched[ctrl.Hwnd] := true
    }

    ; 空的 {{}}，光标停在中间
    static InsertPlaceholder() {
        Editor.InsertTextAt(Editor.content, "{{}}", 2)
    }

    ; 点击「插入占位符」：插入 {{}}，并压制本轮悬浮菜单（否则点完马上弹下拉）
    static OnPhClick() {
        Editor.SuppressHover("ph")
        Editor.InsertPlaceholder()
    }

    ; 点击「插入模板」：与悬停一致，直接弹模板下拉
    static OnTplClick() {
        Editor.SuppressHover("tpl")
        Editor.menuOpen := true
        Editor.ShowTplMenu()
    }

    ; 记录「本次停留已处理过」，鼠标移开才会再触发
    static SuppressHover(key) {
        Editor.hoverKey := key
        Editor.hoverT0 := A_TickCount
        Editor.popOpen := key
        Editor.HideTip()
    }

    ; 变量菜单回调的工厂：每次调用生成独立闭包，避免共用循环变量
    static VarInserter(name) {
        return (*) => Editor.InsertTextAt(Editor.content, "{{" name "}}")
    }

    ; 模板菜单回调的工厂
    static TplInserter(tpl) {
        return (*) => Editor.InsertSpecTpl(tpl)
    }

    ; 规格框插入模板：末尾不是换行时先补一个换行，保证一行一条
    static InsertSpecTpl(tpl) {
        val := Editor.spec.Value
        prefix := ""
        if (Trim(val) != "" && SubStr(val, -1) != "`n")
            prefix := "`n"
        Editor.InsertTextAt(Editor.spec, prefix tpl)
    }

    ; ---------- 「插入占位符」下拉：已定义的动态变量 ----------
    static ShowVarMenu() {
        defs := Template.ParseSpec(Editor.spec.Value)
        m := Menu()
        m.Add("插入空占位符 {{}}", (*) => Editor.InsertPlaceholder())
        m.Add()

        if defs.Length {
            for f in defs {
                tag := "单行"
                if (f["type"] = "select")
                    tag := "下拉"
                else if (f["type"] = "memo")
                    tag := "多行"
                m.Add(f["label"] "  {{" f["name"] "}}  · " tag, Editor.VarInserter(f["name"]))
            }
        } else {
            m.Add("（尚未定义动态变量，可用下方「插入模板」）", (*) => 0)
            m.Disable("（尚未定义动态变量，可用下方「插入模板」）")
        }

        ; 内容里写了但规格里没定义的 → 也列出来，方便统一
        extra := Array()
        for n in Template.Names(Editor.content.Value) {
            if Template.IsBuiltin(n)
                continue
            hit := false
            for f in defs {
                if (StrLower(f["name"]) = StrLower(n)) {
                    hit := true
                    break
                }
            }
            if !hit
                extra.Push(n)
        }
        if extra.Length {
            m.Add()
            for n in extra
                m.Add("{{" n "}}（内容中未定义）", Editor.VarInserter(n))
        }

        ; 内置变量子菜单
        bm := Menu()
        for b in ["date", "time", "datetime", "date:yyyyMMdd", "clipboard", "cursor"] {
            label := (b = "cursor") ? "{{cursor}} 光标位置" : "{{" b "}}"
            bm.Add(label, Editor.VarInserter(b))
        }
        m.Add()
        m.Add("内置变量", bm)
        Editor.PopAt(Editor.phBtn, m)
    }

    ; ---------- 「插入模板」下拉：text / memo / select ----------
    static ShowTplMenu() {
        m := Menu()
        m.Add("text 单行：name|标签|text|默认值", Editor.TplInserter("name|标签|text|默认值"))
        m.Add("memo 多行：desc|说明|memo|默认内容", Editor.TplInserter("desc|说明|memo|默认内容"))
        m.Add("select 下拉：env|环境|select|开发,测试,生产", Editor.TplInserter("env|环境|select|开发,测试,生产"))
        m.Add()
        m.Add("内置变量说明（点击查看）", (*) => MsgBox(Editor.HelpText, "动态变量使用教程", "Iconi"))
        Editor.PopAt(Editor.tplBtn, m)
    }

    static ShowTip() {
        cx := 0, cy := 0, cw := 0, ch := 0
        Editor.hint.GetPos(&cx, &cy, &cw, &ch)
        pt := Editor.ToScreen(cx, cy)
        sx := NumGet(pt, 0, "int"), sy := NumGet(pt, 4, "int")
        Editor.TipAt(sx, sy + ch + 6)
        ; 提示框比屏幕还高时会被裁掉底部，放不下就整体上移
        hwndTT := WinExist("ahk_class tooltips_class32")
        if !hwndTT
            return
        WinGetPos(&tx, &ty, &tw, &th, "ahk_id " hwndTT)
        MonitorGetWorkArea(MonitorGetPrimary(), &ml, &mt, &mr, &mb)
        if (ty + th > mb)
            Editor.TipAt(sx, Max(mt + 4, mb - th - 4))
    }

    static TipAt(x, y) {
        prev := A_CoordModeToolTip
        CoordMode("ToolTip", "Screen")
        ToolTip(Editor.HelpText, x, y, 1)
        CoordMode("ToolTip", prev)
    }

    ; 光标是否在控件矩形内
    static CursorOver(ctrl) {
        cx := 0, cy := 0, cw := 0, ch := 0
        ctrl.GetPos(&cx, &cy, &cw, &ch)
        pt := Editor.ToScreen(cx, cy)
        x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
        prev := A_CoordModeMouse
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        CoordMode("Mouse", prev)
        return (mx >= x && mx <= x + cw && my >= y && my <= y + ch)
    }

    ; 客户区坐标 -> 屏幕坐标（返回 POINT 缓冲）
    static ToScreen(x, y) {
        pt := Buffer(8, 0)
        NumPut("int", x, pt, 0)
        NumPut("int", y, pt, 4)
        DllCall("ClientToScreen", "ptr", Editor.gui.Hwnd, "ptr", pt)
        return pt
    }

    ; 关闭/取消：一并停掉悬浮提示，避免残留 tooltip
    static CloseDlg() {
        Editor.StopHoverWatch()
        Editor.gui.Hide()
    }

    ; 刷新分类下拉框（与管理窗口 Tab 共用同一份 Store.Categories()）
    ; 注意：下拉框的展开高度在「创建时」按条目数确定，事后 Add/Delete 不会变高
    ; （所以之前只创建了 1 项 → 下拉里只能看到 1 个分类），这里每次整只重建。
    static RefreshCats(keep := "") {
        cats := Array()
        for c in Store.Categories() {
            if (Trim(c) != "")
                cats.Push(c)
        }
        if !cats.Length
            cats.Push("常用")

        ; 定位要选中的分类；历史数据里的分类不在列表时补到最前，保证能选上
        idx := 0
        k := Trim(keep)
        if (k != "") {
            for i, c in cats {
                if (c = k) {
                    idx := i
                    break
                }
            }
            if (idx = 0) {
                cats.InsertAt(1, k)
                idx := 1
            }
        }
        if (idx = 0)
            idx := 1

        if (Editor.cat) {
            try Editor.cat.Destroy()
        }
        rows := Min(cats.Length, 12)          ; 分类过多时限制下拉高度
        c := Editor.gui.Add("ComboBox", "x336 y41 w160 h" (24 + rows * 20 + 4), cats)
        c.Choose(idx)
        Editor.cat := c
        return cats
    }

    static Capture() {
        clip := ClipboardAll()
        if (clip.Size = 0) {
            MsgBox("剪贴板为空。", Editor.Title, "Iconi")
            return
        }
        id := Editor.id ? Editor.id : Store.NewId()
        file := Store.CaptureClipboard(id)
        if (file = "")
            return
        Editor.capturedFile := file
        Editor.ShowRes(file)
        ; 自动判定类型：剪贴板含图片则图片，否则文件
        Editor.type.Choose(2)
    }

    ; 资源显示：只显示文件名（完整绝对路径太长，右栏放不下）
    static ShowRes(path := "") {
        if (path = "") {
            Editor.file.Text := "资源：无"
            return
        }
        SplitPath(path, &name)
        Editor.file.Text := "资源：" (name != "" ? name : path)
    }

    static Save() {
        title := Trim(Editor.titleEdit.Value)
        if (title = "")
            return MsgBox("名称不能为空。", Editor.Title, "Icon!")
        trig := Trim(Editor.trig.Value)
        tyIdx := Editor.type.Value
        ty := tyIdx = 1 ? "text" : (tyIdx = 2 ? "image" : "file")
        if (ty = "text" && Editor.content.Value = "")
            return MsgBox("内容不能为空。", Editor.Title, "Icon!")
        if (ty != "text" && (Editor.capturedFile = ""))
            return MsgBox("请先从剪贴板捕获图片或文件。", Editor.Title, "Icon!")

        cat := Editor.cat.Text
        if (cat = "")
            cat := "常用"
        Store.AddCategory(cat)

        data := Map(
            "title", title,
            "trigger", trig,
            "category", cat,
            "type", ty,
            "content", ty = "text" ? Editor.content.Value : "",
            "fields", ty = "text" ? Trim(Editor.spec.Value) : "",
            "file", ty = "text" ? "" : Editor.capturedFile,
            "tags", Trim(Editor.tags.Value),
            "modified", A_Now
        )
        if (Editor.editing) {
            Store.Update(Editor.id, data)
        } else {
            data["id"] := Store.NewId()
            data["created"] := A_Now
            data["usage"] := 0
            Store.Add(data)
        }
        Editor.StopHoverWatch()
        Editor.gui.Hide()
        RefreshHotstrings()
        BuildTrayMenu()
        if Manager.ready
            Manager.RefreshCats()
        ToolTip("已保存：" title)
        SetTimer(() => ToolTip(), -1500)
    }
}

; ============================================================
; Settings - 全局设置
; ============================================================
class Settings {
    static Title := "设置"
    static gui   := ""
    static hSearch := ""
    static hMgr := ""
    static prefix := ""
    static auto := ""
    static limit := ""
    static slashKey := ""
    static slashOn := ""
    static slashWait := ""
    static ready := false

    static Build() {
        if (Settings.ready)
            return
        g := Gui(, Settings.Title)
        g.BackColor := "FFFFFF"
        g.MarginX := 12
        g.MarginY := 10
        g.SetFont("s10")
        g.Add("Text", "x12 y12 w120 h24 +0x200", "搜索面板热键")
        hs := g.Add("Edit", "x140 y10 w200 h24", Store.cfg["hotkey_search"])
        g.Add("Text", "x12 y44 w120 h24 +0x200", "管理窗口热键")
        hm := g.Add("Edit", "x140 y42 w200 h24", Store.cfg["hotkey_manager"])
        g.Add("Text", "x12 y78 w120 h24 +0x200", "缩写前缀")
        px := g.Add("Edit", "x140 y76 w200 h24", Store.cfg["abbrev_prefix"])
        g.Add("Text", "x350 y78 w260 h24 c808080", "例如两个分号加 email 展开")
        au := g.Add("CheckBox", "x140 y108 w260 h24", "启用缩写自动展开")
        au.Value := Store.cfg["auto_expand"]
        g.Add("Text", "x12 y140 w120 h24 +0x200", "搜索结果上限")
        lm := g.Add("Edit", "x140 y138 w200 h24", Store.cfg["search_limit"])

        g.Add("Text", "x12 y172 w120 h24 +0x200", "搜索触发符")
        sk := g.Add("Edit", "x140 y170 w80 h24", Store.cfg["slash_key"])
        g.Add("Text", "x228 y172 w380 h24 c808080", "输入该符号后按 Tab 唤起搜索面板")
        so := g.Add("CheckBox", "x140 y200 w380 h24", "启用「触发符 + Tab」唤起搜索")
        so.Value := Store.cfg["slash_enable"]
        g.Add("Text", "x12 y232 w120 h24 +0x200", "触发等待(ms)")
        sw := g.Add("Edit", "x140 y230 w80 h24", Store.cfg["slash_timeout"])
        g.Add("Text", "x228 y232 w380 h24 c808080", "超时未按 Tab 就当作普通输入")

        g.Add("Text", "x12 y266 w400 h40 c808080",
            "热键语法：^ Ctrl   ! Alt   + Shift   # Win`n例：^!Space 表示 Ctrl+Alt+Space")
        g.Add("Button", "x270 y316 w80 h30", "保存").OnEvent("Click", (*) => Settings.Save())
        g.Add("Button", "x360 y316 w80 h30", "取消").OnEvent("Click", (*) => g.Hide())
        g.OnEvent("Close", (gObj, *) => gObj.Hide())

        Settings.gui := g
        Settings.hSearch := hs
        Settings.hMgr := hm
        Settings.prefix := px
        Settings.auto := au
        Settings.limit := lm
        Settings.slashKey := sk
        Settings.slashOn := so
        Settings.slashWait := sw
        Settings.ready := true
    }

    static Open() {
        Settings.Build()
        Settings.hSearch.Value := Store.cfg["hotkey_search"]
        Settings.hMgr.Value := Store.cfg["hotkey_manager"]
        Settings.prefix.Value := Store.cfg["abbrev_prefix"]
        Settings.auto.Value := Store.cfg["auto_expand"]
        Settings.limit.Value := Store.cfg["search_limit"]
        Settings.slashKey.Value := Store.cfg["slash_key"]
        Settings.slashOn.Value := Store.cfg["slash_enable"]
        Settings.slashWait.Value := Store.cfg["slash_timeout"]
        Settings.gui.Show("Center")
    }

    static Save() {
        Store.cfg["hotkey_search"] := Trim(Settings.hSearch.Value)
        Store.cfg["hotkey_manager"] := Trim(Settings.hMgr.Value)
        Store.cfg["abbrev_prefix"] := Trim(Settings.prefix.Value)
        Store.cfg["auto_expand"] := Settings.auto.Value
        lim := Integer(Settings.limit.Value)
        Store.cfg["search_limit"] := (lim > 0) ? lim : 50

        key := Trim(Settings.slashKey.Value)
        if (key = "")
            key := "/"
        if (key = Trim(Store.cfg["abbrev_prefix"]))
            return MsgBox("触发符不能与缩写前缀相同。", Settings.Title, "Icon!")
        if RegExMatch(key, "[A-Za-z0-9\s]")
            return MsgBox("触发符请用符号，如 / 或 . ，避免纯字母数字或空格。", Settings.Title, "Icon!")
        Store.cfg["slash_key"] := key
        Store.cfg["slash_enable"] := Settings.slashOn.Value
        w := Integer(Settings.slashWait.Value)
        Store.cfg["slash_timeout"] := (w >= 300) ? w : 1500

        Store.SaveConfig()
        RegisterHotkeys()
        RefreshHotstrings()
        RegisterSlashTrigger()
        Settings.gui.Hide()
        ToolTip("设置已保存，热键立即生效")
        SetTimer(() => ToolTip(), -1800)
    }
}
