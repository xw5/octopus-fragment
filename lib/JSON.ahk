#Requires AutoHotkey v2.0
; ============================================================
; JSON.ahk - 轻量 JSON 编解码 (AutoHotkey v2, 零依赖)
; 对象 -> Map(), 数组 -> Array()
; true/false -> 1/0, null -> JSON.Null (单例)
; ============================================================

class JSON {
    static Null := {__json_null: true}

    ; ---------- 编码 ----------
    static Stringify(value, pretty := true) {
        return JSON._dump(value, pretty, 0)
    }

    static _pad(n) {
        s := ""
        loop n * 2
            s .= " "
        return s
    }

    static _dump(v, pretty, level) {
        t := Type(v)
        if (t = "Map") {
            if (v.Count = 0)
                return "{}"
            parts := Array()
            for key, val in v {
                k := JSON.Quote(String(key))
                vs := JSON._dump(val, pretty, level + 1)
                if (pretty)
                    parts.Push(k ": " vs)
                else
                    parts.Push(k ":" vs)
            }
            if (!pretty)
                return "{" JSON._join(parts, ",") "}"
            pad := JSON._pad(level + 1)
            return "{" "`n" pad JSON._join(parts, "," "`n" pad) "`n" JSON._pad(level) "}"
        }
        if (t = "Array") {
            if (v.Length = 0)
                return "[]"
            parts := Array()
            for item in v
                parts.Push(JSON._dump(item, pretty, level + 1))
            if (!pretty)
                return "[" JSON._join(parts, ",") "]"
            pad := JSON._pad(level + 1)
            return "[" "`n" pad JSON._join(parts, "," "`n" pad) "`n" JSON._pad(level) "]"
        }
        if (t = "String")
            return JSON.Quote(v)
        if (t = "Integer" || t = "Float")
            return String(v)
        if (t = "Object" && v.HasProp("__json_null"))
            return "null"
        return JSON.Quote(String(v))
    }

    static _join(arr, sep) {
        s := ""
        for item in arr
            s .= (A_Index = 1 ? "" : sep) item
        return s
    }

    static Quote(s) {
        out := '"'
        loop Parse s {
            c := A_LoopField
            if (c = '"')
                out .= '\"'
            else if (c = '\')
                out .= '\\'
            else if (c = "`b")
                out .= '\b'
            else if (c = "`f")
                out .= '\f'
            else if (c = "`n")
                out .= '\n'
            else if (c = "`r")
                out .= '\r'
            else if (c = "`t")
                out .= '\t'
            else if (Ord(c) < 32)
                out .= '\u' Format("{:04x}", Ord(c))
            else
                out .= c
        }
        return out '"'
    }

    ; ---------- 解码 ----------
    static Parse(text) {
        p := 1
        v := JSON._parseValue(text, &p)
        return v
    }

    static _skipWs(s, &p) {
        while (p <= StrLen(s) && InStr(" `t`r`n", SubStr(s, p, 1)))
            p++
    }

    static _parseValue(s, &p) {
        JSON._skipWs(s, &p)
        if (p > StrLen(s))
            throw Error("JSON: unexpected end of input")
        c := SubStr(s, p, 1)
        if (c = '"')
            return JSON._parseString(s, &p)
        if (c = '{')
            return JSON._parseObject(s, &p)
        if (c = '[')
            return JSON._parseArray(s, &p)
        if (c = 't') {
            p += 4
            return 1
        }
        if (c = 'f') {
            p += 5
            return 0
        }
        if (c = 'n') {
            p += 4
            return JSON.Null
        }
        ; number
        start := p
        if (c = "-")
            p++
        while (p <= StrLen(s) && RegExMatch(SubStr(s, p, 1), "[0-9.eE+-]"))
            p++
        num := SubStr(s, start, p - start)
        if (num = "")
            throw Error("JSON: invalid value at position " p)
        return num + 0
    }

    static _parseString(s, &p) {
        p++ ; skip opening quote
        buf := ""
        while (p <= StrLen(s)) {
            c := SubStr(s, p, 1)
            if (c = '"') {
                p++
                return buf
            }
            if (c = '\') {
                p++
                e := SubStr(s, p, 1)
                if (e = '"')
                    buf .= '"'
                else if (e = '\')
                    buf .= '\'
                else if (e = '/')
                    buf .= '/'
                else if (e = 'b')
                    buf .= "`b"
                else if (e = 'f')
                    buf .= "`f"
                else if (e = 'n')
                    buf .= "`n"
                else if (e = 'r')
                    buf .= "`r"
                else if (e = 't')
                    buf .= "`t"
                else if (e = 'u') {
                    hex := SubStr(s, p + 1, 4)
                    if (StrLen(hex) = 4)
                        buf .= Chr("0x" hex)
                    p += 4
                } else
                    buf .= e
                p++
            } else {
                buf .= c
                p++
            }
        }
        throw Error("JSON: unterminated string")
    }

    static _parseObject(s, &p) {
        p++ ; skip {
        obj := Map()
        JSON._skipWs(s, &p)
        if (SubStr(s, p, 1) = '}') {
            p++
            return obj
        }
        loop {
            JSON._skipWs(s, &p)
            key := JSON._parseString(s, &p)
            JSON._skipWs(s, &p)
            if (SubStr(s, p, 1) != ':')
                throw Error("JSON: expected ':' at position " p)
            p++
            val := JSON._parseValue(s, &p)
            obj[key] := val
            JSON._skipWs(s, &p)
            sep := SubStr(s, p, 1)
            if (sep = ',') {
                p++
                continue
            }
            if (sep = '}') {
                p++
                break
            }
            throw Error("JSON: expected ',' or '}' at position " p)
        }
        return obj
    }

    static _parseArray(s, &p) {
        p++ ; skip [
        arr := Array()
        JSON._skipWs(s, &p)
        if (SubStr(s, p, 1) = ']') {
            p++
            return arr
        }
        loop {
            arr.Push(JSON._parseValue(s, &p))
            JSON._skipWs(s, &p)
            sep := SubStr(s, p, 1)
            if (sep = ',') {
                p++
                continue
            }
            if (sep = ']') {
                p++
                break
            }
            throw Error("JSON: expected ',' or ']' at position " p)
        }
        return arr
    }
}
