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
    static more    := ""          ; 「⋯」下拉菜单按钮
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
        g.OnEvent("Size", (gObj, minMax, w, h) => Manager.OnSize(gObj, minMax, w, h))
        g.OnEvent("Close", (gObj, *) => gObj.Hide())

        Manager.gui := g
        Manager.lv := lv
        Manager.search := ed
        Manager.status := st
        Manager.more := more
        Manager.addTab := addTab
        Manager.arrowL := arrowL
        Manager.arrowR := arrowR
        Manager.ready := true
        Manager.RefreshCats()
        ; 鼠标滚轮在 Tab 行上横向滚动
        OnMessage(0x020A, (w, l, m, h) => Manager.OnWheel(w, l, m, h))
    }

    static OnSize(gObj, minMax := 0, w := 0, h := 0) {
        ; 最小化/最大化事件 (minMax: -1 最小化)
        if (minMax = -1)
            return
        if !Manager.ready
            return
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
        m.Add("插入选中", (*) => Manager.InsertSelected())
        m.Add()
        m.Add("设置", (*) => Settings.Open())
        m.Add("打开数据目录", (*) => Run('explorer.exe "' Store.DataDir '"'))
        m.Add("重新加载数据", (*) => ReloadAll())
        m.Add()
        m.Add("退出", (*) => ExitApp())
        if (Manager.SelectedId() = "") {
            m.Disable("编辑选中")
            m.Disable("删除选中")
            m.Disable("插入选中")
        }
        m.Show()          ; 在鼠标处弹出，正好贴着「⋯」按钮下方
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
            typeName := sn["type"] = "text" ? "文本" : (sn["type"] = "image" ? "图片" : "文件")
            lv.Add("", sn["title"], sn["trigger"], sn["category"], typeName,
                sn.Has("tags") ? sn["tags"] : "", sn.Has("usage") ? sn["usage"] : 0)
            Manager.ids.Push(sn["id"])
        }
        lv.ModifyCol()
        lv.ModifyCol(1, 180)
        lv.ModifyCol(2, 90)
        lv.ModifyCol(3, 90)
        lv.ModifyCol(4, 60)
        lv.ModifyCol(5, 150)
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
    static tags   := ""
    static file   := ""
    static capturedFile := ""
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
        ct := g.Add("Edit", "x10 y130 w700 h230 +WantReturn VScroll", "")
        g.Add("Button", "x720 y130 w160 h32", "从剪贴板捕获").OnEvent("Click", (*) => Editor.Capture())
        ; 右侧信息区：宽 160 自动换行，高度留足，避免文件路径被截断
        f := g.Add("Text", "x720 y172 w160 h96 c606060", "资源：无")
        g.Add("Text", "x720 y274 w160 h96 c909090", "提示：图片/文件请先复制到剪贴板，再点「从剪贴板捕获」。")

        g.Add("Button", "x710 y380 w80 h30", "保存").OnEvent("Click", (*) => Editor.Save())
        g.Add("Button", "x800 y380 w80 h30", "取消").OnEvent("Click", (*) => g.Hide())
        g.OnEvent("Close", (gObj, *) => gObj.Hide())

        Editor.gui := g
        Editor.titleEdit := t
        Editor.trig := tr
        Editor.type := ty
        Editor.tags := tg
        Editor.content := ct
        Editor.file := f
        Editor.ready := true
        Editor.RefreshCats()
    }

    static Open(id := "") {
        Editor.Build()
        Editor.id := id
        Editor.editing := (id != "")

        if (id = "") {
            ; 新增：分类默认跟随管理窗口当前高亮的 Tab（「全部」时用第一个分类）
            want := Manager.curCat
            Editor.RefreshCats(want = "全部" ? "" : want)
            Editor.titleEdit.Value := ""
            Editor.trig.Value := ""
            Editor.type.Choose(1)
            Editor.tags.Value := ""
            Editor.content.Value := ""
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
            ty := sn["type"] = "text" ? 1 : (sn["type"] = "image" ? 2 : 3)
            Editor.type.Choose(ty)
            Editor.capturedFile := sn.Has("file") ? sn["file"] : ""
            Editor.ShowRes(Editor.capturedFile)
            Editor.gui.Title := "编辑片段 - " sn["title"]
        }
        Editor.gui.Show("w900 h430 Center")
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
