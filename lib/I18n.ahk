#Requires AutoHotkey v2.0
; ============================================================
; I18n.ahk - 中英文国际化（界面文案 / 窗口标题 / 托盘菜单）
;
;   I18n.Init("auto")            初始化（auto / zh / en）
;   I18n.T("mgr.search")         取文案
;   I18n.T("mgr.copied", "名称")  带参数：文案里写 {1} {2} …
;   I18n.ApplyLang("en")         切换语言：存配置 + 重建全部界面
; ============================================================

class I18n {
    static Lang    := "zh"
    static UiFont  := "Microsoft YaHei"
    static Strings := Map()

    static Init(pref := "auto") {
        I18n.Lang    := I18n.Resolve(pref)
        I18n.Strings := I18n.Table(I18n.Lang)
        I18n.UiFont  := (I18n.Lang = "en") ? "Segoe UI" : "Microsoft YaHei"
        I18n.ApplyTitles()
        return I18n.Lang
    }

    ; auto：按系统默认界面语言判断（主语言 ID 0x04 = 中文）
    static Resolve(pref) {
        p := StrLower(Trim(pref))
        if (p = "zh" || p = "cn" || p = "zh-cn" || p = "chinese")
            return "zh"
        if (p = "en" || p = "en-us" || p = "english")
            return "en"
        try {
            id := DllCall("GetUserDefaultUILanguage", "ushort")
            return ((id & 0x3FF) = 0x04) ? "zh" : "en"
        }
        return "zh"
    }

    static T(key, args*) {
        s := I18n.Strings.Has(key) ? I18n.Strings[key] : key
        if args.Length {
            for i, a in args
                s := StrReplace(s, "{" i "}", a)
        }
        return s
    }

    ; 窗口标题（多处用 WinActive(Title) 判断，必须跟着语言走）
    static ApplyTitles() {
        Manager.Title     := I18n.T("mgr.title")
        SearchPanel.Title := I18n.T("search.title")
        Editor.Title      := I18n.T("editor.title")
        Settings.Title    := I18n.T("settings.title")
        FillDialog.Title  := I18n.T("fill.title")
    }

    ; 类型列的显示名（文本 / 文本·变量 / 图片 / 文件）
    static TypeName(sn) {
        if (IsObject(sn) && sn.Has("type") && sn["type"] != "text")
            return I18n.T(sn["type"] = "image" ? "type.image" : "type.file")
        content := (IsObject(sn) && sn.Has("content")) ? sn["content"] : ""
        return I18n.T(Template.HasVars(content) ? "type.textvar" : "type.text")
    }

    ; 切换语言：写配置 -> 换文案 -> 重建所有界面 -> 重开设置窗口
    static ApplyLang(pref) {
        Store.cfg["lang"] := pref
        Store.SaveConfig()
        I18n.Init(pref)
        I18n.RebuildUi()
        BuildTrayMenu()
        Settings.Open()
        ToolTip(I18n.T("settings.saved"))
        SetTimer(() => ToolTip(), -1800)
    }

    ; 销毁全部窗口按新语言重建；管理窗口原来开着就再打开
    static RebuildUi() {
        mgrVisible := false
        try {
            if (Manager.ready && IsObject(Manager.gui) && Manager.gui)
                mgrVisible := DllCall("IsWindowVisible", "ptr", Manager.gui.Hwnd) ? true : false
        }
        SearchPanel.Reset()
        Editor.Reset()
        Settings.Reset()
        Manager.Reset()
        if mgrVisible
            Manager.Show()
    }

    ; ---------- 文案表 ----------
    static Table(lang) {
        en := (lang = "en")
        m := Map()

        ; 通用 / 类型
        m["app.msgTitle"]        := en ? "Snippets"                       : "片段管理"
        m["type.text"]           := en ? "Text"                           : "文本"
        m["type.textvar"]        := en ? "Text·Vars"                      : "文本·变量"
        m["type.image"]          := en ? "Image"                          : "图片"
        m["type.file"]           := en ? "File"                           : "文件"

        ; 搜索面板
        m["search.title"]        := en ? "Octopus Fragment · Quick Search" : "octopus-fragment 快速搜索"
        m["search.hint"]         := en ? "↑↓ select   Enter insert   Esc close"
                                       : "↑↓ 选择   Enter 插入   Esc 关闭"
        m["search.empty"]        := en ? "(no matching snippet)"           : "（无匹配片段）"

        ; 管理窗口
        m["mgr.title"]           := en ? "Octopus Fragment · Snippets"     : "octopus-fragment 片段管理"
        m["mgr.search"]          := en ? "Search"                          : "搜索"
        m["mgr.refresh"]         := en ? "Refresh"                         : "刷新"
        m["mgr.all"]             := en ? "All"                             : "全部"
        m["mgr.col.name"]        := en ? "Name"                            : "名称"
        m["mgr.col.abbr"]        := en ? "Abbr"                            : "缩写"
        m["mgr.col.category"]    := en ? "Category"                        : "分类"
        m["mgr.col.type"]        := en ? "Type"                            : "类型"
        m["mgr.col.tags"]        := en ? "Tags"                            : "标签"
        m["mgr.col.uses"]        := en ? "Uses"                            : "次数"
        m["mgr.more.new"]        := en ? "New snippet"                     : "新增片段"
        m["mgr.more.edit"]       := en ? "Edit selected"                   : "编辑选中"
        m["mgr.more.delete"]     := en ? "Delete selected"                 : "删除选中"
        m["mgr.more.dup"]        := en ? "Duplicate selected"              : "复制选中"
        m["mgr.more.insert"]     := en ? "Insert selected"                 : "插入选中"
        m["mgr.more.settings"]   := en ? "Settings"                        : "设置"
        m["mgr.more.datadir"]    := en ? "Open data folder"                : "打开数据目录"
        m["mgr.more.reload"]     := en ? "Reload data"                     : "重新加载数据"
        m["mgr.more.rescript"]   := en ? "Reload script (after code edits)" : "重载脚本（改代码后用）"
        m["mgr.more.exit"]       := en ? "Exit"                            : "退出"
        m["mgr.ctx.insert"]      := en ? "Insert"                          : "插入"
        m["mgr.ctx.edit"]        := en ? "Edit"                            : "编辑"
        m["mgr.ctx.delete"]      := en ? "Delete"                          : "删除"
        m["mgr.ctx.dup"]         := en ? "Duplicate"                       : "复制"
        m["mgr.selectFirst"]     := en ? "Select a snippet first."         : "请先选择一个片段。"
        m["mgr.copied"]          := en ? "Duplicated: {1}"                 : "已复制：{1}"
        m["mgr.newcat.title"]    := en ? "New category"                    : "新增分类"
        m["mgr.newcat.prompt"]   := en ? "Category name (an existing one just selects it)"
                                       : "分类名称（已存在则直接切换）"
        m["mgr.status.count"]    := en ? "{1} snippet(s)    Data: {2}"     : "共 {1} 个片段    数据文件：{2}"
        m["mgr.status.empty"]    := en ? "No snippets in this category    Data: {1}"
                                       : "该分类下暂无片段    数据文件：{1}"
        m["mgr.del.confirm"]     := en ? "Delete snippet `"{1}`"?`nThis cannot be undone."
                                       : "确定删除片段「{1}」？`n此操作不可恢复。"

        ; 编辑窗口
        m["editor.title"]        := en ? "Edit snippet"                    : "编辑片段"
        m["editor.titleNew"]     := en ? "New snippet"                     : "新增片段"
        m["editor.titleEdit"]    := en ? "Edit snippet - {1}"              : "编辑片段 - {1}"
        m["editor.name"]         := en ? "Name"                            : "名称"
        m["editor.abbr"]         := en ? "Abbr"                            : "缩写"
        m["editor.category"]     := en ? "Category"                        : "分类"
        m["editor.type"]         := en ? "Type"                            : "类型"
        m["editor.tags"]         := en ? "Tags"                            : "标签"
        m["editor.contentLabel"] := en ? "Content (pasted when type = Text)"
                                       : "内容（type=文本 时粘贴此内容）"
        m["editor.insertPh"]     := en ? "Placeholder ▾"                   : "插入占位符 ▾"
        m["editor.capture"]      := en ? "Capture clipboard"               : "从剪贴板捕获"
        m["editor.res.none"]     := en ? "Resource: none"                  : "资源：无"
        m["editor.res.some"]     := en ? "Resource: {1}"                   : "资源：{1}"
        m["editor.res.tip"]      := en ? "Tip: copy the image/file to the clipboard first."
                                       : "提示：图片/文件请先复制到剪贴板，再点「从剪贴板捕获」。"
        m["editor.specLabel"]    := en ? "Dynamic variables (optional): name|label|type|default, one per line"
                                       : "动态变量（可选）：每行 名称|标签|类型|默认值或选项   类型 text/memo/select"
        m["editor.insertTpl"]    := en ? "Template ▾"                      : "插入模板 ▾"
        m["editor.builtinHint"]  := en ? "Built-in:`n{{date}} {{time}}`n{{datetime}}`n{{date:yyyyMMdd}}`n{{clipboard}}`n{{cursor}} caret"
                                       : "内置变量：`n{{date}} {{time}}`n{{datetime}}`n{{date:yyyyMMdd}}`n{{clipboard}}`n{{cursor}} 光标位置"
        m["editor.save"]         := en ? "Save"                            : "保存"
        m["editor.cancel"]       := en ? "Cancel"                          : "取消"
        m["editor.help.title"]   := en ? "Dynamic variables guide"         : "动态变量使用教程"
        m["editor.ph.empty"]     := en ? "Insert empty placeholder {{}}"   : "插入空占位符 {{}}"
        m["editor.ph.noVars"]    := en ? "(No dynamic variables yet — use `"Insert template`" below)"
                                       : "（尚未定义动态变量，可用下方「插入模板」）"
        m["editor.ph.extra"]     := en ? "{{1}} (not defined in content)"  : "{{1}}（内容中未定义）"
        m["editor.ph.builtin"]   := en ? "Built-in variables"              : "内置变量"
        m["editor.ph.cursor"]    := en ? "{{cursor}} caret position"       : "{{cursor}} 光标位置"
        m["editor.tag.text"]     := en ? "single"                          : "单行"
        m["editor.tag.select"]   := en ? "dropdown"                        : "下拉"
        m["editor.tag.memo"]     := en ? "multiline"                       : "多行"
        m["editor.tpl.text"]     := en ? "text  single: name|Label|text|Default"
                                       : "text 单行：name|标签|text|默认值"
        m["editor.tpl.memo"]     := en ? "memo  multi: desc|Notes|memo|Default text"
                                       : "memo 多行：desc|说明|memo|默认内容"
        m["editor.tpl.select"]   := en ? "select dropdown: env|Environment|select|Dev,Test,Prod"
                                       : "select 下拉：env|环境|select|开发,测试,生产"
        m["editor.tpl.help"]     := en ? "Built-in variables guide (click)" : "内置变量说明（点击查看）"
        m["editor.tpl.fLabel"]   := en ? "Label"                           : "标签"
        m["editor.tpl.fDefault"] := en ? "Default"                         : "默认值"
        m["editor.tpl.fNote"]    := en ? "Notes"                           : "说明"
        m["editor.tpl.fMemoDefault"] := en ? "Default text"                : "默认内容"
        m["editor.tpl.fEnv"]     := en ? "Environment"                     : "环境"
        m["editor.tpl.fOptions"] := en ? "Dev,Test,Prod"                   : "开发,测试,生产"
        m["editor.err.clipEmpty"]  := en ? "The clipboard is empty."       : "剪贴板为空。"
        m["editor.err.nameEmpty"]  := en ? "Name cannot be empty."         : "名称不能为空。"
        m["editor.err.contentEmpty"] := en ? "Content cannot be empty."    : "内容不能为空。"
        m["editor.err.needCapture"]  := en ? "Capture an image or file from the clipboard first."
                                           : "请先从剪贴板捕获图片或文件。"
        m["editor.saved"]        := en ? "Saved: {1}"                      : "已保存：{1}"
        m["editor.cat.default"]  := en ? "Common"                          : "常用"

        m["editor.help.body"] := en
            ? "Dynamic variables guide`n`n"
            . "0) Shortcut buttons:`n"
            . "    `"Insert placeholder`": click inserts {{}} (caret in the middle)`n"
            . "    Hover it → dropdown of defined variables, click to insert`n"
            . "    `"Insert template`": click or hover → text / memo / select templates`n`n"
            . "1) Write {{variable}} placeholders in Content`n"
            . "    e.g. this is a {{memo1}} test`n`n"
            . "2) Define them under Dynamic variables, one per line:`n"
            . "    name|label|type|default or options`n"
            . "    select: env|Environment|select|Dev,Test,Prod`n"
            . "    single: name|Name|text|John`n"
            . "    multi : desc|Notes|memo|default text`n`n"
            . "3) Types: text single line / memo multiline / select dropdown`n"
            . "    separate select options with commas`n`n"
            . "4) Used in Content but not defined here`n"
            . "    → a single-line input is added automatically`n`n"
            . "5) Built-ins (no definition needed):`n"
            . "    {{date}} {{time}} {{datetime}}`n"
            . "    {{date:yyyyMMdd}} custom format`n"
            . "    {{clipboard}} clipboard text`n"
            . "    {{cursor}} caret position after insert"
            : "动态变量使用教程`n`n"
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

        ; 设置窗口
        m["settings.title"]       := en ? "Settings"                        : "设置"
        m["settings.hotkeySearch"] := en ? "Search panel hotkey"            : "搜索面板热键"
        m["settings.hotkeyMgr"]   := en ? "Manager hotkey"                  : "管理窗口热键"
        m["settings.prefix"]      := en ? "Abbreviation prefix"             : "缩写前缀"
        m["settings.prefixTip"]   := en ? "e.g. two semicolons + email"     : "例如两个分号加 email 展开"
        m["settings.auto"]        := en ? "Enable abbreviation auto-expand" : "启用缩写自动展开"
        m["settings.limit"]       := en ? "Max search results"              : "搜索结果上限"
        m["settings.slashKey"]    := en ? "Search trigger key"              : "搜索触发符"
        m["settings.slashKeyTip"] := en ? "Type this symbol then Tab to open search"
                                        : "输入该符号后按 Tab 唤起搜索面板"
        m["settings.slashOn"]     := en ? "Enable trigger key + Tab search" : "启用「触发符 + Tab」唤起搜索"
        m["settings.slashWait"]   := en ? "Trigger wait (ms)"               : "触发等待(ms)"
        m["settings.slashWaitTip"]:= en ? "If Tab is not pressed in time, type normally"
                                        : "超时未按 Tab 就当作普通输入"
        m["settings.hotkeyHelp"]  := en ? "Hotkey syntax: ^ Ctrl   ! Alt   + Shift   # Win`ne.g. ^!Space means Ctrl+Alt+Space"
                                        : "热键语法：^ Ctrl   ! Alt   + Shift   # Win`n例：^!Space 表示 Ctrl+Alt+Space"
        m["settings.lang"]        := en ? "Language"                        : "语言"
        m["settings.langAuto"]    := en ? "Follow system"                   : "跟随系统"
        m["settings.langZh"]      := en ? "简体中文"                        : "简体中文"
        m["settings.langEn"]      := en ? "English"                         : "English"
        m["settings.save"]        := en ? "Save"                            : "保存"
        m["settings.cancel"]      := en ? "Cancel"                          : "取消"
        m["settings.err.sameKey"] := en ? "Trigger key cannot equal the abbreviation prefix."
                                        : "触发符不能与缩写前缀相同。"
        m["settings.err.badKey"]  := en ? "Use a symbol for the trigger key (e.g. / or .), not letters, digits or spaces."
                                        : "触发符请用符号，如 / 或 . ，避免纯字母数字或空格。"
        m["settings.saved"]       := en ? "Settings saved — hotkeys take effect immediately"
                                        : "设置已保存，热键立即生效"

        ; 变量填写窗口
        m["fill.title"]           := en ? "Fill variables"                  : "填写变量"
        m["fill.hint"]            := en ? "Enter insert    Esc cancel"      : "Enter 插入    Esc 取消"
        m["fill.ok"]              := en ? "Insert"                          : "插入"
        m["fill.cancel"]          := en ? "Cancel"                          : "取消"

        ; 行为 / 托盘 / 关于
        m["act.noSnippet"]        := en ? "Snippet not found"               : "片段不存在"
        m["act.backFail"]         := en ? "Could not switch back to the original window — insertion cancelled"
                                        : "未能切回原窗口，已取消插入"
        m["act.pasteFail"]        := en ? "Insert failed:`n{1}"             : "插入失败：`n{1}"
        m["act.assetMissing"]     := en ? "Resource file missing: {1}"     : "资源文件丢失：{1}"
        m["act.slashRegFail"]     := en ? "Trigger key registration failed: {1}"
                                        : "触发符注册失败：{1}"
        m["act.reloaded"]         := en ? "Snippets reloaded"               : "片段已重新加载"
        m["tray.search"]          := en ? "Quick search"                    : "快速搜索"
        m["tray.manager"]         := en ? "Manage snippets"                 : "管理片段"
        m["tray.empty"]           := en ? "(empty)"                         : "(空)"
        m["tray.reload"]          := en ? "Reload data"                     : "重新加载数据"
        m["tray.rescript"]        := en ? "Reload script (after code edits)" : "重载脚本（改代码后用）"
        m["tray.about"]           := en ? "About"                           : "关于"
        m["tray.exit"]            := en ? "Exit"                            : "退出"
        m["about.body"]           := en ? "A FastKeys-like snippet manager (AutoHotkey " A_AhkVersion ")`n`nData folder: {1}"
                                        : "类 FastKeys 的片段管理工具（AutoHotkey " A_AhkVersion "）`n`n数据目录：{1}"

        ; 存储层提示
        m["store.writeFail"]      := en ? "Cannot write file: {1}"          : "无法写入文件：{1}"
        m["store.cfgLoadFail"]    := en ? "Failed to read config, defaults used:`n{1}"
                                        : "配置读取失败，已使用默认配置：`n{1}"
        m["store.cfgSaveFail"]    := en ? "Failed to save config:`n{1}"     : "配置保存失败：`n{1}"
        m["store.dbLoadFail"]     := en ? "Failed to read snippet data, using empty data.`nOriginal file untouched:`n{1}`n`n{2}"
                                        : "片段数据读取失败，已使用空数据。`n原文件未被覆盖：`n{1}`n`n{2}"
        m["store.dbSaveFail"]     := en ? "Failed to save data:`n{1}"       : "数据保存失败：`n{1}"
        m["store.assetFail"]      := en ? "Failed to save resource:`n{1}"   : "资源保存失败：`n{1}"

        ; 首次运行的示例数据
        m["seed.cat1"]            := en ? "Common"                          : "常用"
        m["seed.cat2"]            := en ? "Work"                            : "工作"
        m["seed.cat3"]            := en ? "Code"                            : "代码"
        m["seed.email.title"]     := en ? "My email"                        : "我的邮箱"
        m["seed.email.tags"]      := en ? "email contact"                   : "邮箱 联系方式"
        m["seed.addr.title"]      := en ? "Shipping address"                : "常用收货地址"
        m["seed.addr.tags"]       := en ? "address delivery"                : "地址 快递"
        m["seed.addr.content"]    := en ? "88 Keji South 1st Rd`nNanshan, Shenzhen`nChina"
                                        : "广东省深圳市南山区`n科技园南区 1 栋`n518000"
        m["seed.log.tags"]        := en ? "js debug"                        : "js 调试"
        m["seed.daily.title"]     := en ? "Daily report"                    : "日报模板"
        m["seed.daily.tags"]      := en ? "template daily variables"         : "模板 日报 变量"
        m["seed.daily.content"]   := en ? "[Daily] {{date}}`nName: {{name}}`nEnv: {{env}}`n`nDone today: {{done}}`nPlan: {{cursor}}"
                                        : "【日报】{{date}}`n姓名：{{name}}`n环境：{{env}}`n`n今日完成：{{done}}`n明日计划：{{cursor}}"
        m["seed.daily.fields"]    := en ? "name|Name|text|`nenv|Environment|select|Dev,Test,Prod`ndone|Done today|memo|"
                                        : "name|姓名|text|`nenv|环境|select|开发,测试,生产`ndone|今日完成|memo|"

        return m
    }
}
