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
        ; 先给个默认语言：配置读取失败时提示也要有文案
        I18n.Init("auto")
        Store.LoadConfig()
        ; 语言必须在读片段数据前就位：示例数据（分类名等）按语言生成
        I18n.Init(Store.cfg.Has("lang") ? Store.cfg["lang"] : "auto")
        Store.LoadDb()
    }

    ; ---------- 默认配置 ----------
    static DefaultConfig() {
        return Map(
            "lang",            "auto",      ; 界面语言：auto / zh / en
            "hotkey_search",   "^!Space",   ; Ctrl+Alt+Space
            "hotkey_manager",  "^!m",       ; Ctrl+Alt+M
            "abbrev_prefix",   ";;",        ; 缩写前缀
            "auto_expand",     1,           ; 是否启用缩写自动展开
            "case_sensitive",  0,
            "search_limit",    50,
            "slash_enable",    1,           ; 是否启用「触发符 + Tab」唤起搜索
            "slash_key",       "/",         ; 触发符（可自定义，如 / 或 ; 或 .b）
            "slash_timeout",   1500         ; 等待 Tab 的时长(ms)，超时按普通输入处理
        )
    }

    static DefaultDb() {
        return Map(
            "version",    1,
            "snippets",   Array(),
            "categories", Array(I18n.T("seed.cat1"), I18n.T("seed.cat2"), I18n.T("seed.cat3"))
        )
    }

    ; ---------- 读写 ----------
    static WriteText(path, text) {
        f := FileOpen(path, "w", "UTF-8")
        if !IsObject(f)
            throw Error(I18n.T("store.writeFail", path))
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
            ToolTip(I18n.T("store.cfgLoadFail", e.Message))
            SetTimer(() => ToolTip(), -4000)
        }
    }

    static SaveConfig() {
        try
            Store.WriteText(Store.CfgFile, JSON.Stringify(Store.cfg, true))
        catch as e {
            MsgBox(I18n.T("store.cfgSaveFail", e.Message), I18n.T("app.msgTitle"), "Icon!")
        }
    }

    static LoadDb() {
        if !FileExist(Store.DbFile) {
            Store.db := Store.DefaultDb()
            Store.SeedExamples()
            Store.SaveDb()
            Store.OtherCat()               ; 确保保留分类「其它」存在
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
                obj["categories"] := Array(I18n.T("seed.cat1"))
            ; 逐条补齐缺失键：手工编辑过的 JSON 缺 title/trigger 等键时，
            ; Search/Refresh 等处会 KeyError，加载阶段统一兜底
            obj["snippets"] := Store.NormalizeSnippets(obj["snippets"])
            obj["version"] := 1
            Store.db := obj
            Store.OtherCat()               ; 保留分类「其它」：缺则补（名字记录在 other_cat）
        } catch as e {
            Store.db := Store.DefaultDb()
            MsgBox(I18n.T("store.dbLoadFail", Store.DbFile, e.Message), I18n.T("app.msgTitle"), "Icon!")
        }
    }

    static SaveDb() {
        try
            Store.WriteText(Store.DbFile, JSON.Stringify(Store.db, true))
        catch as e {
            MsgBox(I18n.T("store.dbSaveFail", e.Message), I18n.T("app.msgTitle"), "Icon!")
        }
    }

    ; 逐条补齐 snippet 必备键（缺键会在 Search/Refresh/TypeName 处 KeyError）；
    ; 非 Map 的条目直接丢弃；type 非法时按 text 处理
    static NormalizeSnippets(arr) {
        clean := Array()
        for item in arr {
            if (Type(item) != "Map")
                continue
            if (!item.Has("id") || item["id"] = "")
                item["id"] := Store.NewId()
            for k, v in Map(
                "title",    "",
                "trigger",  "",
                "category", I18n.T("editor.cat.default"),
                "type",     "text",
                "content",  "",
                "file",     "",
                "tags",     "",
                "usage",    0
            ) {
                if !item.Has(k)
                    item[k] := v
            }
            if (item["type"] != "text" && item["type"] != "image" && item["type"] != "file")
                item["type"] := "text"
            if (Trim(item["category"]) = "")   ; 空分类也归默认，避免菜单/Tab 出现空名条目
                item["category"] := I18n.T("editor.cat.default")
            clean.Push(item)
        }
        return clean
    }

    static SeedExamples() {
        now := A_Now
        cat1 := I18n.T("seed.cat1")
        cat2 := I18n.T("seed.cat2")
        cat3 := I18n.T("seed.cat3")
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", I18n.T("seed.email.title"),
            "trigger", "email",
            "category", cat1,
            "type", "text",
            "content", "hello@example.com",
            "file", "",
            "tags", I18n.T("seed.email.tags"),
            "usage", 0,
            "created", now,
            "modified", now
        ))
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", I18n.T("seed.addr.title"),
            "trigger", "addr",
            "category", cat1,
            "type", "text",
            "content", I18n.T("seed.addr.content"),
            "file", "",
            "tags", I18n.T("seed.addr.tags"),
            "usage", 0,
            "created", now,
            "modified", now
        ))
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", "Console.log",
            "trigger", "log",
            "category", cat3,
            "type", "text",
            "content", "console.log('DEBUG:', );",
            "file", "",
            "tags", I18n.T("seed.log.tags"),
            "usage", 0,
            "created", now,
            "modified", now
        ))
        ; 动态变量示例：插入时弹窗填写 {{name}} / {{env}} / {{done}}，{{date}} 自动替换
        Store.db["snippets"].Push(Map(
            "id", Store.NewId(),
            "title", I18n.T("seed.daily.title"),
            "trigger", "daily",
            "category", cat2,
            "type", "text",
            "content", I18n.T("seed.daily.content"),
            "fields", I18n.T("seed.daily.fields"),
            "file", "",
            "tags", I18n.T("seed.daily.tags"),
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

    ; ---------- 复制 ----------
    ; 复制片段并插到原片段「前面」，名称 = 原名 + 序号（我的邮箱 -> 我的邮箱2 -> 我的邮箱3）
    static Duplicate(id) {
        i := Store.IndexOf(id)
        if (i = 0)
            return ""
        src  := Store.db["snippets"][i]
        newId := Store.NewId()

        copy := Map()
        for k, v in src
            copy[k] := v
        copy["id"]       := newId
        copy["title"]    := Store.NextCopyTitle(src["title"])
        copy["trigger"]  := ""          ; 缩写重复会让两条热字符串互相覆盖，复制品留空
        copy["usage"]    := 0
        copy["created"]  := A_Now
        copy["modified"] := A_Now

        ; 图片/文件：资源另存一份，避免删掉其中一个时把另一个的源文件也删了
        if (copy.Has("file") && copy["file"] != "") {
            srcPath := Store.AssetDir "\" copy["file"]
            dstName := newId ".clip"
            if FileExist(srcPath) {
                try FileCopy(srcPath, Store.AssetDir "\" dstName, 1)
                catch
                    dstName := copy["file"]          ; 复制失败则共用原资源
            } else {
                dstName := copy["file"]
            }
            copy["file"] := dstName
        }

        Store.db["snippets"].InsertAt(i, copy)
        Store.SaveDb()
        return newId
    }

    ; 拆出「基名 + 末尾序号」：我的邮箱2 -> {base:我的邮箱, idx:2}
    static SplitCopyTitle(title) {
        base := title
        idx  := 1
        if RegExMatch(title, "^(.*[^\d\s])[\s\-_]*(\d+)$", &m) {
            base := Trim(m[1])
            idx  := Integer(m[2])
        }
        return Map("base", base, "idx", idx)
    }

    ; 下一个可用序号：同名里最大的序号 + 1
    static NextCopyTitle(title) {
        p    := Store.SplitCopyTitle(title)
        base := p["base"]
        n    := p["idx"]
        for sn in Store.db["snippets"] {
            q := Store.SplitCopyTitle(sn["title"])
            if (q["base"] = base)
                n := Max(n, q["idx"])
        }
        n := n + 1
        return base n
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

    ; 保留分类「其它」：不可删除/重命名；删除分类时其下的片段都移入这里。
    ; 名字记录在 db["other_cat"]（首次访问时按当前语言生成并落盘），
    ; 避免以后切换界面语言时出现「其它/Other」两个并存；缺则补进分类列表
    static OtherCat() {
        nm := ""
        if (Store.db.Has("other_cat") && Type(Store.db["other_cat"]) = "String")
            nm := Store.db["other_cat"]
        changed := false
        if (nm = "") {
            nm := I18n.T("cat.other")
            Store.db["other_cat"] := nm
            changed := true
        }
        found := false
        for c in Store.db["categories"] {
            if (c = nm) {
                found := true
                break
            }
        }
        if !found {
            Store.db["categories"].Push(nm)
            changed := true
        }
        if (changed)
            Store.SaveDb()
        return nm
    }

    ; 删除分类。分类列表由 db["categories"] 与片段反推共同组成，
    ; 片段必须一起挪走，否则删除的分类会立刻以派生形式重新出现；
    ; 被挪走的片段统一移入保留分类「其它」
    static DeleteCategory(name) {
        if (name = Store.OtherCat())
            return -1                      ; 保留分类不允许删除
        for i, c in Store.db["categories"] {
            if (c = name) {
                Store.db["categories"].RemoveAt(i)
                break
            }
        }
        fallback := Store.OtherCat()
        moved := 0
        for sn in Store.db["snippets"] {
            if (sn["category"] = name) {
                sn["category"] := fallback
                moved++
            }
        }
        Store.SaveDb()
        return moved
    }

    ; 重命名分类：列表与该分类下所有片段一起改名。
    ; 返回 "ok" / "dup"（目标名已存在）/ "none"（名称无效）
    static RenameCategory(oldName, newName) {
        newName := Trim(newName)
        if (newName = "" || newName = oldName)
            return "none"
        for c in Store.db["categories"] {
            if (c = newName)
                return "dup"
        }
        inList := false
        for i, c in Store.db["categories"] {
            if (c = oldName) {
                Store.db["categories"][i] := newName
                inList := true
                break
            }
        }
        moved := 0
        for sn in Store.db["snippets"] {
            if (sn["category"] = oldName) {
                sn["category"] := newName
                moved++
            }
        }
        if (!inList && moved)
            Store.db["categories"].Push(newName)   ; 原分类只存在于片段上（派生）
        if (inList || moved)
            Store.SaveDb()
        return "ok"
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
            MsgBox(I18n.T("store.assetFail", e.Message), I18n.T("app.msgTitle"), "Icon!")
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
}
