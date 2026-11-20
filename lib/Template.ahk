#Requires AutoHotkey v2.0
; ============================================================
; Template.ahk - 动态变量模板（变量解析 / 规格解析 / 渲染）
;
; 内容里写 {{变量名}}，插入时弹窗填写。内置变量：
;   {{date}} {{time}} {{datetime}} {{year}} {{month}} {{day}}
;   {{date:yyyyMMdd}}    自定义格式（FormatTime 语法）
;   {{clipboard}}        插入时的剪贴板文本
;   {{cursor}}           插入完成后光标停留的位置
;
; 变量规格（片段 fields 字段，每行一条）：
;   名称 | 标签 | 类型 | 默认值或选项
;   类型：text 单行 / memo 多行 / select 下拉（第四列用逗号分隔选项）
;   例：env|环境|select|开发,测试,生产
; ============================================================

class Template {
    static Builtins := ["date", "time", "datetime", "year", "month", "day", "clipboard", "cursor"]
    static _clip := ""

    ; 内容里是否出现 {{...}}
    static HasVars(text) {
        if (text = "")
            return false
        return RegExMatch(text, "\{\{[^{}\r\n]{1,40}\}\}") ? true : false
    }

    ; 插入前是否需要弹窗填写（只含内置变量时不弹）
    static NeedsFill(sn) {
        if (!IsObject(sn) || !sn.Has("type") || sn["type"] != "text")
            return false
        content := sn.Has("content") ? sn["content"] : ""
        if !Template.HasVars(content)
            return false
        for name in Template.Names(content) {
            if !Template.IsBuiltin(name)
                return true
        }
        return false
    }

    ; 内容中出现过的变量名（按出现顺序、忽略大小写去重）
    static Names(text) {
        names := Array()
        pos := 1
        while RegExMatch(text, "\{\{([^{}\r\n]{1,40})\}\}", &m, pos) {
            pos := m.Pos + m.Len
            nm := Trim(m[1])
            if (nm = "")
                continue
            dup := false
            for x in names {
                if (StrLower(x) = StrLower(nm)) {
                    dup := true
                    break
                }
            }
            if !dup
                names.Push(nm)
        }
        return names
    }

    ; 内置变量名（支持 name:format 写法）
    static IsBuiltin(name) {
        base := StrLower(Trim(name))
        p := InStr(base, ":")
        if (p > 0)
            base := SubStr(base, 1, p - 1)
        for b in Template.Builtins {
            if (b = base)
                return true
        }
        return false
    }

    static StripBraces(name) {
        s := Trim(name)
        if (SubStr(s, 1, 2) = "{{")
            s := SubStr(s, 3)
        if (SubStr(s, -1) = "}}")
            s := SubStr(s, 1, StrLen(s) - 2)
        return Trim(s)
    }

    ; 解析 fields 规格文本 -> [{name,label,type,options,default}, ...]
    static ParseSpec(spec) {
        fields := Array()
        if (Trim(spec) = "")
            return fields
        for line in StrSplit(spec, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
                continue
            parts := StrSplit(line, "|", , 4)
            name := Template.StripBraces(parts[1])
            if (name = "")
                continue
            label := (parts.Length >= 2) ? Trim(parts[2]) : ""
            typ   := (parts.Length >= 3) ? StrLower(Trim(parts[3])) : "text"
            rest  := (parts.Length >= 4) ? Trim(parts[4]) : ""

            opts := Array()
            def  := ""
            if (typ = "select" || typ = "dropdown" || typ = "下拉" || typ = "list") {
                typ := "select"
                for o in StrSplit(rest, ",") {
                    o := Trim(o)
                    if (o != "")
                        opts.Push(o)
                }
                if !opts.Length
                    opts.Push("")
            } else if (typ = "memo" || typ = "multiline" || typ = "多行" || typ = "textbox") {
                typ := "memo"
                def := rest
            } else {
                typ := "text"
                def := rest
            }

            if (label = "")
                label := name
            fields.Push(Map(
                "name", name,
                "label", label,
                "type", typ,
                "options", opts,
                "default", def
            ))
        }
        return fields
    }

    ; 规格里定义的变量 + 内容里出现但未定义的变量（自动补单行输入框）
    static MergeFields(sn) {
        defs := Array()
        if (IsObject(sn) && sn.Has("fields"))
            defs := Template.ParseSpec(sn["fields"])

        have := Map()
        for f in defs
            have[StrLower(f["name"])] := true

        content := (IsObject(sn) && sn.Has("content")) ? sn["content"] : ""
        for name in Template.Names(content) {
            key := StrLower(name)
            if have.Has(key)
                continue
            if Template.IsBuiltin(name)
                continue
            have[key] := true
            defs.Push(Map(
                "name", name,
                "label", name,
                "type", "text",
                "options", Array(),
                "default", ""
            ))
        }
        return defs
    }

    ; 渲染：返回 Map("text", 结果, "caret", 光标位置或 -1)
    ;   values : 变量名 -> 值（可为 0 表示无用户输入）
    ;   clipText: {{clipboard}} 的取值
    static Render(content, values := 0, clipText := "") {
        text := content
        Template._clip := clipText

        if IsObject(values) {
            for name, v in values {
                if (name = "")
                    continue
                ; 允许 {{name}} / {{ name }} 等写法（StrReplace 默认忽略大小写）
                text := StrReplace(text, "{{" name "}}", v)
                text := StrReplace(text, "{{ " name "}}", v)
                text := StrReplace(text, "{{" name " }}", v)
                text := StrReplace(text, "{{ " name " }}", v)
            }
        }

        ; 内置变量：逐个替换（替换值里可能还含占位符，不能递归）
        pos := 1
        loops := 0
        while (loops++ < 200) {
            if !RegExMatch(text,
                "i)\{\{\s*(date|datetime|time|year|month|day|clipboard)(?::([^{}\r\n]*))?\s*\}\}",
                &m, pos)
                break
            repl := Template._Builtin(m)
            text := SubStr(text, 1, m.Pos - 1) . repl . SubStr(text, m.Pos + m.Len)
            pos := m.Pos + StrLen(repl)
        }

        ; 光标标记先换成不可见哨兵，避免被下面的兜底清理吃掉
        marker := Chr(0xE000)
        text := RegExReplace(text, "i)\{\{\s*cursor\s*\}\}", marker)

        ; 未定义/拼错的变量占位符直接清掉，避免输出脏字符
        text := RegExReplace(text, "\{\{[^{}\r\n]{1,40}\}\}", "")

        caret := -1
        if (p := InStr(text, marker)) {
            before := SubStr(text, 1, p - 1)
            text := StrReplace(text, marker, "")
            caret := StrLen(before)
        }
        return Map("text", text, "caret", caret)
    }

    static _Builtin(m) {
        nm  := StrLower(m[1])
        fmt := m[2]
        switch nm {
            case "date":      return FormatTime(A_Now, fmt != "" ? fmt : "yyyy-MM-dd")
            case "time":      return FormatTime(A_Now, fmt != "" ? fmt : "HH:mm")
            case "datetime":  return FormatTime(A_Now, fmt != "" ? fmt : "yyyy-MM-dd HH:mm:ss")
            case "year":      return FormatTime(A_Now, "yyyy")
            case "month":     return FormatTime(A_Now, "MM")
            case "day":       return FormatTime(A_Now, "dd")
            case "clipboard": return Template._clip
        }
        return ""
    }
}
