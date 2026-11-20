#Requires AutoHotkey v2.0
; ============================================================
; FillDialog.ahk - 动态变量填写窗口（模态）
;   按片段 fields 规格生成：单行输入 / 多行输入 / 下拉选择
;   记住上次填写的值（存于片段 lastvals）
; ============================================================

class FillDialog {
    static Title  := "填写变量"
    static gui    := ""
    static items  := Array()
    static sn     := ""
    static result := ""

    ; 弹窗收集变量值：成功返回 Map(变量名 -> 值)，取消返回 ""
    static Collect(sn) {
        fields := Template.MergeFields(sn)
        if !fields.Length
            return Map()

        last := FillDialog.LastValues(sn)
        g := Gui("+AlwaysOnTop", FillDialog.Title " - " sn["title"])
        g.BackColor := "FFFFFF"
        g.MarginX := 12
        g.MarginY := 12
        g.SetFont("s10", "Microsoft YaHei")

        items := Array()
        y := 12
        for f in fields {
            g.SetFont("s9 c505050", "Microsoft YaHei")
            g.Add("Text", "x12 y" (y + 5) " w100 h20 +0x200", FillDialog.Clip(f["label"], 100))
            g.SetFont("s10 c000000", "Microsoft YaHei")

            val := last.Has(f["name"]) ? last[f["name"]] : ""
            if (val = "" && f["default"] != "")
                val := Template.Render(f["default"], Map(), "")["text"]

            switch f["type"] {
                case "select":
                    opts := f["options"].Length ? f["options"] : [""]
                    rows := Min(opts.Length, 10)
                    c := g.Add("DropDownList", "x116 y" y " w330 h" (26 + rows * 22), opts)
                    pick := 1
                    for i, o in opts {
                        if (o = val) {
                            pick := i
                            break
                        }
                    }
                    c.Choose(pick)
                case "memo":
                    c := g.Add("Edit", "x116 y" y " w330 h84 +WantReturn VScroll")
                    c.Value := val
                    y += 56
                default:
                    c := g.Add("Edit", "x116 y" y " w330 h26")
                    c.Value := val
            }
            items.Push(Map("name", f["name"], "type", f["type"], "ctl", c))
            y += 34
        }

        g.SetFont("s9 c808080", "Microsoft YaHei")
        g.Add("Text", "x12 y" (y + 8) " w260 h20 +0x200", "Enter 插入    Esc 取消")
        g.SetFont("s10", "Microsoft YaHei")
        ok := g.Add("Button", "x286 y" (y + 4) " w76 h28 Default", "插入")
        cn := g.Add("Button", "x370 y" (y + 4) " w76 h28", "取消")
        ok.OnEvent("Click", (*) => FillDialog.DoOk())
        cn.OnEvent("Click", (*) => FillDialog.DoCancel())
        g.OnEvent("Escape", (*) => FillDialog.DoCancel())
        g.OnEvent("Close",  (*) => FillDialog.DoCancel())

        FillDialog.gui := g
        FillDialog.items := items
        FillDialog.sn := sn
        FillDialog.result := ""

        g.Show("w458 h" (y + 46) " Center")
        if items.Length
            try items[1]["ctl"].Focus()

        ; 等待窗口关闭：Sleep 期间消息照常处理，按钮回调可执行
        ; （hwnd 必须先取出，Gui 被 Destroy 后再访问对象成员会报错）
        hMain := g.Hwnd
        t0 := A_TickCount
        while WinExist("ahk_id " hMain) {
            if (A_TickCount - t0 > 180000) {      ; 兜底：3 分钟后自动关闭
                try g.Destroy()
                break
            }
            Sleep 20
        }

        res := FillDialog.result
        FillDialog.gui := ""
        FillDialog.items := Array()
        FillDialog.sn := ""
        return res
    }

    static DoOk() {
        vals := Map()
        for it in FillDialog.items {
            v := (it["type"] = "select") ? it["ctl"].Text : it["ctl"].Value
            vals[it["name"]] := v
        }
        ; 记住本次输入，下次直接带出来
        sn := FillDialog.sn
        if (IsObject(sn) && sn.Has("id")) {
            sn["lastvals"] := vals
            Store.SaveDb()
        }
        FillDialog.result := vals
        try FillDialog.gui.Destroy()
    }

    static DoCancel() {
        FillDialog.result := ""
        try FillDialog.gui.Destroy()
    }

    static LastValues(sn) {
        m := Map()
        if (IsObject(sn) && sn.Has("lastvals") && Type(sn["lastvals"]) = "Map") {
            for k, v in sn["lastvals"]
                m[k] := v
        }
        return m
    }

    static Clip(text, w) {
        maxCh := Max(1, Floor((w - 8) / 13))
        if (StrLen(text) <= maxCh)
            return text
        return SubStr(text, 1, maxCh - 1) "…"
    }
}
