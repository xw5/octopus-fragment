#Requires AutoHotkey v2.0
; ============================================================
; Store.ahk - 数据存储层 (snippets.json / config.json / assets)
; ============================================================

class Store {
    static Root      := ""
    static DataDir   := ""
    static AssetDir  := ""
    static DbFile    := ""
    static CfgFile   := ""
    static db        := Map()
    static cfg       := Map()

    static Init(root := "") {
        Store.Root := root ? root : A_ScriptDir
        Store.DataDir  := Store.Root "\data"
        Store.AssetDir := Store.DataDir "\assets"
        Store.DbFile   := Store.DataDir "\snippets.json"
        Store.CfgFile  := Store.DataDir "\config.json"
        if !DirExist(Store.DataDir)
            DirCreate(Store.DataDir)
        if !DirExist(Store.AssetDir)
            DirCreate(Store.AssetDir)
        Store.LoadConfig()
        Store.LoadDb()
    }

    ; ---------- 默认配置 ----------
    static DefaultConfig() {
        return Map(
            "hotkey_search",   "^!Space",   ; Ctrl+Alt+Space
            "hotkey_manager",  "^!m",       ; Ctrl+Alt+M
            "abbrev_prefix",   ";;",        ; 缩写前缀
            "auto_expand",     1,           ; 是否启用缩写自动展开
            "case_sensitive",  0,
            "search_limit",    50,
            "theme",           "light",
            "slash_enable",    1,           ; 是否启用「触发符 + Tab」唤起搜索
            "slash_key",       "/",         ; 触发符（可自定义，如 / 或 ; 或 .b）
            "slash_timeout",   1500         ; 等待 Tab 的时长(ms)，超时按普通输入处理
        )
    }

    static DefaultDb() {
        return Map(
            "version",    1,
            "snippets",   Array(),
            "categories", Array("常用", "工作", "代码")
        )
    }

    ; ---------- 读写 ----------
    static WriteText(path, text) {
        f := FileOpen(path, "w", "UTF-8")
        if !IsObject(f)
            throw Error("无法写入文件：" path)
        try
            f.Write(text)
        finally
            f.Close()
    }

    static LoadConfig() {
        if !FileExist(Store.CfgFile) {
            Store.cfg := Store.DefaultConfig()
            Store.SaveConfig()
            return
        }
        try {
            raw := FileRead(Store.CfgFile, "UTF-8")
            obj := JSON.Parse(raw)
            if (Type(obj) != "Map")
                throw Error("config root is not object")
            def := Store.DefaultConfig()
            for k, v in def {
                if !obj.Has(k)
                    obj[k] := v
            }
            Store.cfg := obj
        } catch as e {
            Store.cfg := Store.DefaultConfig()
            ToolTip("配置读取失败，已使用默认配置：`n" e.Message)
            SetTimer(() => ToolTip(), -4000)
        }
    }

    static SaveConfig() {
        try
            Store.WriteText(Store.CfgFile, JSON.Stringify(Store.cfg, true))
        catch as e {
            MsgBox("配置保存失败：`n" e.Message, "片段管理", "Icon!")
        }
    }

    static LoadDb() {
        if !FileExist(Store.DbFile) {
            Store.db := Store.DefaultDb()
            Store.SeedExamples()
            Store.SaveDb()
            return
        }
        try {
            raw := FileRead(Store.DbFile, "UTF-8")
            obj := JSON.Parse(raw)
            if (Type(obj) != "Map")
                throw Error("database root is not object")
            if !obj.Has("snippets") || Type(obj["snippets"]) != "Array"
                obj["snippets"] := Array()
            if !obj.Has("categories") || Type(obj["categories"]) != "Array"
                obj["categories"] := Array("常用")
            obj["version"] := 1
            Store.db := obj
        } catch as e {
            Store.db := Store.DefaultDb()
            MsgBox("片段数据读取失败，已使用空数据。`n原文件未被覆盖：`n" Store.DbFile "`n`n" e.Message, "片段管理", "Icon!")
        }
    }

    static SaveDb() {
        try
            Store.WriteText(Store.DbFile, JSON.Stringify(Store.db, true))
        catch as e {
            MsgBox("数据保存失败：`n" e.Message, "片段管理", "Icon!")
        }
    }

    static SeedExamples() {
        now := A_Now
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", "我的邮箱",
            "trigger", "email",
            "category", "常用",
            "type", "text",
            "content", "hello@example.com",
            "file", "",
            "tags", "邮箱 联系方式",
            "usage", 0,
            "created", now,
            "modified", now
        ))
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", "常用收货地址",
            "trigger", "addr",
            "category", "常用",
            "type", "text",
            "content", "广东省深圳市南山区`n科技园南区 1 栋`n518000",
            "file", "",
            "tags", "地址 快递",
            "usage", 0,
            "created", now,
            "modified", now
        ))
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", "Console.log",
            "trigger", "log",
            "category", "代码",
            "type", "text",
            "content", "console.log('DEBUG:', );",
            "file", "",
            "tags", "js 调试",
            "usage", 0,
            "created", now,
            "modified", now
        ))
    }

    static NewId() {
        return "s" A_Now Format("{:03}", Random(0, 999))
    }

    ; ---------- CRUD ----------
    static Get(id) {
        for sn in Store.db["snippets"] {
            if (sn["id"] = id)
                return sn
        }
        return ""
    }

    static IndexOf(id) {
        for i, sn in Store.db["snippets"] {
            if (sn["id"] = id)
                return i
        }
        return 0
    }

    static Add(sn) {
        Store.db["snippets"].Push(sn)
        Store.SaveDb()
    }

    static Update(id, data) {
        i := Store.IndexOf(id)
        if (i = 0)
            return false
        old := Store.db["snippets"][i]
        for k, v in data
            old[k] := v
        old["modified"] := A_Now
        Store.SaveDb()
        return true
    }

    static Delete(id) {
        i := Store.IndexOf(id)
        if (i = 0)
            return false
        sn := Store.db["snippets"][i]
        if (sn.Has("file") && sn["file"] != "") {
            path := Store.AssetDir "\" sn["file"]
            if FileExist(path) {
                try FileDelete path
            }
        }
        Store.db["snippets"].RemoveAt(i)
        Store.SaveDb()
        return true
    }

    static BumpUsage(id) {
        sn := Store.Get(id)
        if (sn = "")
            return
        sn["usage"] := (sn.Has("usage") ? sn["usage"] : 0) + 1
        Store.SaveDb()
    }

    static Search(keyword := "", category := "") {
        result := Array()
        kw := StrLower(Trim(keyword))
        for sn in Store.db["snippets"] {
            if (category != "" && sn["category"] != category)
                continue
            if (kw != "") {
                hay := StrLower(sn["title"] " " sn["trigger"] " "
                    . (sn.Has("tags") ? sn["tags"] : "") " "
                    . (sn["type"] = "text" ? sn["content"] : ""))
                if !InStr(hay, kw)
                    continue
            }
            result.Push(sn)
        }
        return result
    }

    static Categories() {
        cats := Array()
        for c in Store.db["categories"]
            cats.Push(c)
        for sn in Store.db["snippets"] {
            c := sn["category"]
            found := false
            for x in cats {
                if (x = c) {
                    found := true
                    break
                }
            }
            if !found
                cats.Push(c)
        }
        return cats
    }

    static AddCategory(name) {
        name := Trim(name)
        if (name = "")
            return false
        for c in Store.db["categories"] {
            if (c = name)
                return false
        }
        Store.db["categories"].Push(name)
        Store.SaveDb()
        return true
    }

    ; ---------- 导入导出 ----------
    static Export(path) {
        try {
            Store.WriteText(path, JSON.Stringify(Store.db, true))
            return true
        }
        return false
    }

    static Import(path) {
        try {
            raw := FileRead(path, "UTF-8")
            obj := JSON.Parse(raw)
            if (Type(obj) != "Map" || Type(obj["snippets"]) != "Array")
                return 0
            n := 0
            for sn in obj["snippets"] {
                if (Type(sn) != "Map" || !sn.Has("id") || !sn.Has("title"))
                    continue
                sn["id"] := Store.NewId()
                if !sn.Has("type")
                    sn["type"] := "text"
                if !sn.Has("usage")
                    sn["usage"] := 0
                Store.db["snippets"].Push(sn)
                n++
            }
            Store.SaveDb()
            return n
        }
        return 0
    }

    ; ---------- 资源 (剪贴板图片/文件) ----------
    static CaptureClipboard(id) {
        ; 将当前剪贴板完整内容保存到 assets\{id}.clip
        clip := ClipboardAll()
        if (clip.Size = 0)
            return ""
        name := id ".clip"
        path := Store.AssetDir "\" name
        try
            FileOpen(path, "w").RawWrite(clip)
        catch as e {
            MsgBox("资源保存失败：`n" e.Message, "片段管理", "Icon!")
            return ""
        }
        return name
    }

    static RestoreClipboard(file) {
        if (file = "")
            return false
        path := Store.AssetDir "\" file
        if !FileExist(path)
            return false
        try {
            buf := FileRead(path, "RAW")
            A_Clipboard := ClipboardAll(buf)
            return true
        }
        return false
    }

    static AssetExists(file) {
        return (file != "" && FileExist(Store.AssetDir "\" file))
    }
}
