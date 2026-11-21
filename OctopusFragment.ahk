#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================
; Octopus Fragment - 类 FastKeys 片段管理工具
; 入口脚本
; ============================================================
;@Ahk2Exe-SetName Octopus Fragment
;@Ahk2Exe-SetVersion 1.0.3
;@Ahk2Exe-SetDescription 类 FastKeys 的片段管理工具（AutoHotkey v2）
;@Ahk2Exe-SetProductName Octopus Fragment
;@Ahk2Exe-SetMainIcon assets\OctopusFragment.ico

#Include lib/I18n.ahk
#Include lib/JSON.ahk
#Include lib/Store.ahk
#Include lib/Template.ahk
#Include lib/FillDialog.ahk
#Include lib/Actions.ahk
#Include lib/SearchPanel.ahk
#Include lib/Manager.ahk

; 启动
Store.Init(A_ScriptDir)
RegisterHotkeys()
RefreshHotstrings()
RegisterSlashTrigger()
BuildTrayMenu()

IconFile := A_ScriptDir "\assets\OctopusFragment.ico"
if FileExist(IconFile)
    TraySetIcon(IconFile)
else
    TraySetIcon(A_AhkPath, 1)

; 提示：首次运行会在 data\ 下生成示例数据
; 如需改数据后自动热重载，可自行加入目录监控

; ============================================================
; 热键标签必须放在 auto-execute 区末尾（标签会终止自动执行区）
; 搜索面板导航热键：仅在面板激活时生效
; ============================================================
#HotIf WinActive(SearchPanel.Title)
Up::SearchPanel.Move(-1)
Down::SearchPanel.Move(1)
Enter::SearchPanel.Confirm()
Escape::SearchPanel.Cancel()
#HotIf
