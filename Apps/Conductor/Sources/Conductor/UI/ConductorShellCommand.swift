import AppKit
import ConductorCore
import Foundation

@MainActor
enum ConductorShellCommand: String, CaseIterable {
    case newWorkspace
    case newTerminal
    case newWebTab
    case focusWebAddress
    case goBackSelectedWebTab
    case goForwardSelectedWebTab
    case reloadSelectedWebTab
    case openSelectedWebTabExternally
    case copySelectedWebTabURL
    case copySelectedWebTabReference
    case openSelectedFileExternally
    case revealSelectedFileInFinder
    case closeSelectedTab
    case closeOtherTabs
    case closeTabsToRight
    case closeFocusedPane
    case splitRight
    case splitDown
    case selectNextTab
    case selectPreviousTab
    case focusNextPane
    case focusPreviousPane
    case focusPaneLeft
    case focusPaneRight
    case focusPaneUp
    case focusPaneDown
    case resizePaneLeft
    case resizePaneRight
    case resizePaneUp
    case resizePaneDown
    case equalizeSplits
    case toggleZoom
    case moveTabLeft
    case moveTabRight
    case moveTabToNextPane
    case moveTabToNewRightSplit
    case moveTabToNewDownSplit
    case toggleCommandPalette
    case toggleWorkspaceOverview
    case toggleSettings
    case toggleFileManager
    case jumpLatestUnreadAttention
    case markCurrentWorkspaceAttentionRead
    case openTokenRecords
    case toggleFullScreen
    case resetWorkspace
    case showTerminalSearch
    case findNext
    case findPrevious
    case flashFocusedPane
    case duplicateSelectedTab
    case newTerminalAtFocusedDirectory
    case openFocusedDirectory
    case copyFocusedDirectory
    case openCurrentWorkspaceRoot
    case openCurrentWorkspaceFirstService
    case renameCurrentWorkspace
    case duplicateWorkspace
    case closeOtherWorkspaces
    case closeWorkspacesToRight
    case closeCurrentWorkspace
    case restorePreviousSession
    case resumeCurrentWorkspaceAgents

    struct Descriptor: Equatable {
        var id: String
        var category: String
        var title: String
        var outcome: String
        var keywords: String
        var shortcutFallback: String
        var systemImage: String
        var protocolMethod: String
    }

    var descriptor: Descriptor {
        func t(zh: String, en: String) -> String {
            ConductorLocalization.text(zh: zh, en: en)
        }
        let categoryCreate = t(zh: "创建", en: "Create")
        let categoryNavigate = t(zh: "导航", en: "Navigate")
        let categoryOrganize = t(zh: "整理", en: "Organize")
        let categoryWeb = t(zh: "网页", en: "Web")
        let categoryContext = t(zh: "上下文", en: "Context")
        let categoryView = t(zh: "视图", en: "View")
        let categorySearch = t(zh: "搜索", en: "Search")
        let categoryRecovery = t(zh: "恢复", en: "Recovery")
        let categoryAttention = t(zh: "注意力", en: "Attention")

        switch self {
        case .newWorkspace:
            return Descriptor(id: "new-workspace", category: categoryCreate, title: t(zh: "新建工作区", en: "New Workspace"), outcome: t(zh: "创建一个独立工作区，用来承载一组终端、网页和文件。", en: "Creates an isolated workspace for a set of terminals, web tabs, and files."), keywords: "workspace new project", shortcutFallback: "Cmd-N", systemImage: WorkspaceChromeGlyph.systemName(selected: false), protocolMethod: "command.run")
        case .newTerminal:
            return Descriptor(id: "new-terminal", category: categoryCreate, title: t(zh: "新开终端", en: "New Terminal"), outcome: t(zh: "在当前工作区添加一个终端标签。", en: "Adds a terminal tab to the current workspace."), keywords: "terminal pane shell", shortcutFallback: "Cmd-T", systemImage: "plus.rectangle.on.rectangle", protocolMethod: "command.run")
        case .newWebTab:
            return Descriptor(id: "new-web-tab", category: categoryCreate, title: t(zh: "新建网页标签", en: "New Web Tab"), outcome: t(zh: "打开一个工作区网页标签，可用于文档、预览或本地服务。", en: "Opens a workspace web tab for docs, previews, or local services."), keywords: "web browser tab url docs preview localhost", shortcutFallback: "Cmd-Shift-T", systemImage: "globe", protocolMethod: "command.run")
        case .focusWebAddress:
            return Descriptor(id: "web-address", category: categoryWeb, title: t(zh: "聚焦网页地址栏", en: "Focus Web Address"), outcome: t(zh: "把输入焦点移到当前网页的地址栏。", en: "Moves focus to the selected web tab address field."), keywords: "web url address location search", shortcutFallback: "Cmd-L", systemImage: "link", protocolMethod: "command.run")
        case .goBackSelectedWebTab:
            return Descriptor(id: "web-back", category: categoryWeb, title: t(zh: "网页后退", en: "Web Back"), outcome: t(zh: "让当前网页标签回到上一页。", en: "Moves the selected web tab back in history."), keywords: "web browser back history previous", shortcutFallback: "Back", systemImage: "chevron.left", protocolMethod: "command.run")
        case .goForwardSelectedWebTab:
            return Descriptor(id: "web-forward", category: categoryWeb, title: t(zh: "网页前进", en: "Web Forward"), outcome: t(zh: "让当前网页标签前进到下一页。", en: "Moves the selected web tab forward in history."), keywords: "web browser forward history next", shortcutFallback: "Forward", systemImage: "chevron.right", protocolMethod: "command.run")
        case .reloadSelectedWebTab:
            return Descriptor(id: "web-reload", category: categoryWeb, title: t(zh: "重新载入网页", en: "Reload Web Page"), outcome: t(zh: "重新载入或停止当前网页标签。", en: "Reloads or stops the selected web tab."), keywords: "web reload refresh stop", shortcutFallback: "Cmd-R", systemImage: "arrow.clockwise", protocolMethod: "command.run")
        case .openSelectedWebTabExternally:
            return Descriptor(id: "web-open-external", category: categoryWeb, title: t(zh: "在浏览器中打开当前网页", en: "Open Current Web Page in Browser"), outcome: t(zh: "用系统默认浏览器打开当前网页。", en: "Opens the selected web page in the system browser."), keywords: "web external browser open", shortcutFallback: "Browser", systemImage: "arrow.up.right.square", protocolMethod: "command.run")
        case .copySelectedWebTabURL:
            return Descriptor(id: "web-copy-url", category: categoryWeb, title: t(zh: "复制当前网页链接", en: "Copy Current Web URL"), outcome: t(zh: "把当前网页 URL 放到剪贴板。", en: "Copies the selected web tab URL to the clipboard."), keywords: "web url copy link", shortcutFallback: "Copy", systemImage: "link.badge.plus", protocolMethod: "command.run")
        case .copySelectedWebTabReference:
            return Descriptor(id: "web-copy-reference", category: categoryWeb, title: t(zh: "复制当前网页引用", en: "Copy Current Web Reference"), outcome: t(zh: "把当前网页标题和链接复制成 Markdown 引用。", en: "Copies the selected web page title and link as a Markdown reference."), keywords: "web markdown reference copy link", shortcutFallback: "Markdown", systemImage: "doc.on.clipboard", protocolMethod: "command.run")
        case .openSelectedFileExternally:
            return Descriptor(id: "file-open-external", category: categoryContext, title: t(zh: "系统应用打开当前文件", en: "Open Current File in System App"), outcome: t(zh: "用 macOS 默认应用打开当前文件标签。", en: "Opens the selected file tab in the macOS default app."), keywords: "file open external system app", shortcutFallback: "System App", systemImage: "arrow.up.right.square", protocolMethod: "command.run")
        case .revealSelectedFileInFinder:
            return Descriptor(id: "file-reveal-finder", category: categoryContext, title: t(zh: "在 Finder 中显示当前文件", en: "Reveal Current File in Finder"), outcome: t(zh: "在 Finder 中定位当前文件标签。", en: "Reveals the selected file tab in Finder."), keywords: "file reveal finder show", shortcutFallback: "Finder", systemImage: "folder", protocolMethod: "command.run")
        case .closeSelectedTab:
            return Descriptor(id: "close-tab", category: categoryOrganize, title: t(zh: "关闭标签", en: "Close Tab"), outcome: t(zh: "关闭当前选中的终端、网页或文件标签。", en: "Closes the selected terminal, web, or file tab."), keywords: "close tab", shortcutFallback: "Cmd-W", systemImage: "xmark", protocolMethod: "command.run")
        case .closeOtherTabs:
            return Descriptor(id: "close-other-tabs", category: categoryOrganize, title: t(zh: "关闭其他标签", en: "Close Other Tabs"), outcome: t(zh: "保留当前终端标签，关闭同一分屏里的其他标签。", en: "Keeps the selected terminal tab and closes the other tabs in that pane."), keywords: "close other tabs", shortcutFallback: "Close Others", systemImage: "xmark.rectangle", protocolMethod: "command.run")
        case .closeTabsToRight:
            return Descriptor(id: "close-tabs-to-right", category: categoryOrganize, title: t(zh: "关闭右侧标签", en: "Close Tabs to the Right"), outcome: t(zh: "关闭当前分屏中位于右侧的终端标签。", en: "Closes terminal tabs to the right in the current pane."), keywords: "close tabs right", shortcutFallback: "Close Right", systemImage: "xmark.rectangle.fill", protocolMethod: "command.run")
        case .closeFocusedPane:
            return Descriptor(id: "close-pane", category: categoryOrganize, title: t(zh: "关闭分屏", en: "Close Pane"), outcome: t(zh: "关闭当前分屏，并保持至少一个分屏可用。", en: "Closes the focused pane while keeping at least one pane available."), keywords: "close pane split", shortcutFallback: "Cmd-Shift-W", systemImage: "xmark", protocolMethod: "command.run")
        case .splitRight:
            return Descriptor(id: "split-right", category: categoryCreate, title: t(zh: "向右分屏", en: "Split Right"), outcome: t(zh: "在当前分屏右侧创建一个新终端分屏。", en: "Creates a new terminal pane to the right of the current pane."), keywords: "split right vertical", shortcutFallback: "Cmd-D", systemImage: "rectangle.split.2x1", protocolMethod: "command.run")
        case .splitDown:
            return Descriptor(id: "split-down", category: categoryCreate, title: t(zh: "向下分屏", en: "Split Down"), outcome: t(zh: "在当前分屏下方创建一个新终端分屏。", en: "Creates a new terminal pane below the current pane."), keywords: "split down horizontal", shortcutFallback: "Cmd-Shift-D", systemImage: "rectangle.split.1x2", protocolMethod: "command.run")
        case .selectNextTab:
            return Descriptor(id: "next-tab", category: categoryNavigate, title: t(zh: "下一个标签", en: "Next Tab"), outcome: t(zh: "切到当前分屏里的下一个标签。", en: "Selects the next tab in the current pane."), keywords: "next tab", shortcutFallback: "Cmd-]", systemImage: "arrow.right", protocolMethod: "command.run")
        case .selectPreviousTab:
            return Descriptor(id: "previous-tab", category: categoryNavigate, title: t(zh: "上一个标签", en: "Previous Tab"), outcome: t(zh: "切到当前分屏里的上一个标签。", en: "Selects the previous tab in the current pane."), keywords: "previous tab", shortcutFallback: "Cmd-[", systemImage: "arrow.left", protocolMethod: "command.run")
        case .focusNextPane:
            return Descriptor(id: "next-pane", category: categoryNavigate, title: t(zh: "下一个分屏", en: "Next Pane"), outcome: t(zh: "把焦点移到下一个分屏。", en: "Moves focus to the next pane."), keywords: "next pane focus", shortcutFallback: "Cmd-Shift-]", systemImage: "arrow.right", protocolMethod: "command.run")
        case .focusPreviousPane:
            return Descriptor(id: "previous-pane", category: categoryNavigate, title: t(zh: "上一个分屏", en: "Previous Pane"), outcome: t(zh: "把焦点移到上一个分屏。", en: "Moves focus to the previous pane."), keywords: "previous pane focus", shortcutFallback: "Cmd-Shift-[", systemImage: "arrow.left", protocolMethod: "command.run")
        case .focusPaneLeft:
            return Descriptor(id: "focus-left", category: categoryNavigate, title: t(zh: "聚焦左侧分屏", en: "Focus Pane Left"), outcome: t(zh: "把焦点移到左侧相邻分屏。", en: "Moves focus to the pane on the left."), keywords: "focus pane left", shortcutFallback: "Cmd-Opt-←", systemImage: "arrow.left", protocolMethod: "command.run")
        case .focusPaneRight:
            return Descriptor(id: "focus-right", category: categoryNavigate, title: t(zh: "聚焦右侧分屏", en: "Focus Pane Right"), outcome: t(zh: "把焦点移到右侧相邻分屏。", en: "Moves focus to the pane on the right."), keywords: "focus pane right", shortcutFallback: "Cmd-Opt-→", systemImage: "arrow.right", protocolMethod: "command.run")
        case .focusPaneUp:
            return Descriptor(id: "focus-up", category: categoryNavigate, title: t(zh: "聚焦上方分屏", en: "Focus Pane Up"), outcome: t(zh: "把焦点移到上方相邻分屏。", en: "Moves focus to the pane above."), keywords: "focus pane up", shortcutFallback: "Cmd-Opt-↑", systemImage: "arrow.up", protocolMethod: "command.run")
        case .focusPaneDown:
            return Descriptor(id: "focus-down", category: categoryNavigate, title: t(zh: "聚焦下方分屏", en: "Focus Pane Down"), outcome: t(zh: "把焦点移到下方相邻分屏。", en: "Moves focus to the pane below."), keywords: "focus pane down", shortcutFallback: "Cmd-Opt-↓", systemImage: "arrow.down", protocolMethod: "command.run")
        case .resizePaneLeft:
            return Descriptor(id: "resize-left", category: categoryOrganize, title: t(zh: "向左调整分屏", en: "Resize Pane Left"), outcome: t(zh: "收缩或扩展当前分屏的水平尺寸。", en: "Adjusts the focused pane width to the left."), keywords: "resize split left", shortcutFallback: "Cmd-Shift-←", systemImage: "arrow.left.and.right", protocolMethod: "command.run")
        case .resizePaneRight:
            return Descriptor(id: "resize-right", category: categoryOrganize, title: t(zh: "向右调整分屏", en: "Resize Pane Right"), outcome: t(zh: "收缩或扩展当前分屏的水平尺寸。", en: "Adjusts the focused pane width to the right."), keywords: "resize split right", shortcutFallback: "Cmd-Shift-→", systemImage: "arrow.left.and.right", protocolMethod: "command.run")
        case .resizePaneUp:
            return Descriptor(id: "resize-up", category: categoryOrganize, title: t(zh: "向上调整分屏", en: "Resize Pane Up"), outcome: t(zh: "收缩或扩展当前分屏的垂直尺寸。", en: "Adjusts the focused pane height upward."), keywords: "resize split up", shortcutFallback: "Cmd-Shift-↑", systemImage: "arrow.up.and.down", protocolMethod: "command.run")
        case .resizePaneDown:
            return Descriptor(id: "resize-down", category: categoryOrganize, title: t(zh: "向下调整分屏", en: "Resize Pane Down"), outcome: t(zh: "收缩或扩展当前分屏的垂直尺寸。", en: "Adjusts the focused pane height downward."), keywords: "resize split down", shortcutFallback: "Cmd-Shift-↓", systemImage: "arrow.up.and.down", protocolMethod: "command.run")
        case .equalizeSplits:
            return Descriptor(id: "equalize-splits", category: categoryView, title: t(zh: "均分分屏", en: "Equalize Splits"), outcome: t(zh: "把当前工作区里的分屏尺寸重新平均分配。", en: "Redistributes split sizes evenly in the current workspace."), keywords: "equalize split layout", shortcutFallback: "Cmd-Shift-=", systemImage: "equal.square", protocolMethod: "command.run")
        case .toggleZoom:
            return Descriptor(id: "toggle-zoom", category: categoryView, title: t(zh: "放大当前分屏", en: "Zoom Current Pane"), outcome: t(zh: "在专注当前分屏和恢复完整布局之间切换。", en: "Toggles between focusing the current pane and restoring the full layout."), keywords: "zoom pane", shortcutFallback: "Cmd-Opt-Z", systemImage: "arrow.up.left.and.arrow.down.right", protocolMethod: "command.run")
        case .moveTabLeft:
            return Descriptor(id: "move-tab-left", category: categoryOrganize, title: t(zh: "标签左移", en: "Move Tab Left"), outcome: t(zh: "把当前标签移动到同一分屏的左侧。", en: "Moves the selected tab left within the current pane."), keywords: "move tab left", shortcutFallback: "Cmd-Shift-,", systemImage: "arrow.left.to.line", protocolMethod: "command.run")
        case .moveTabRight:
            return Descriptor(id: "move-tab-right", category: categoryOrganize, title: t(zh: "标签右移", en: "Move Tab Right"), outcome: t(zh: "把当前标签移动到同一分屏的右侧。", en: "Moves the selected tab right within the current pane."), keywords: "move tab right", shortcutFallback: "Cmd-Shift-.", systemImage: "arrow.right.to.line", protocolMethod: "command.run")
        case .moveTabToNextPane:
            return Descriptor(id: "move-tab-next-pane", category: categoryOrganize, title: t(zh: "移到下一个分屏", en: "Move to Next Pane"), outcome: t(zh: "把当前终端标签移到另一个分屏。", en: "Moves the selected terminal tab to another pane."), keywords: "move tab pane", shortcutFallback: "Cmd-Opt-M", systemImage: "arrowshape.turn.up.right", protocolMethod: "command.run")
        case .moveTabToNewRightSplit:
            return Descriptor(id: "move-tab-new-right-split", category: categoryOrganize, title: t(zh: "移到右侧新分屏", en: "Move to New Right Split"), outcome: t(zh: "把当前终端标签拆到右侧新分屏。", en: "Moves the selected terminal tab into a new right split."), keywords: "move tab new split right", shortcutFallback: "Cmd-Opt-Shift-M", systemImage: "rectangle.split.2x1", protocolMethod: "command.run")
        case .moveTabToNewDownSplit:
            return Descriptor(id: "move-tab-new-down-split", category: categoryOrganize, title: t(zh: "移到下方新分屏", en: "Move to New Down Split"), outcome: t(zh: "把当前终端标签拆到下方新分屏。", en: "Moves the selected terminal tab into a new lower split."), keywords: "move tab new split down", shortcutFallback: "New Down Split", systemImage: "rectangle.split.1x2", protocolMethod: "command.run")
        case .toggleCommandPalette:
            return Descriptor(id: "command-palette", category: categoryView, title: t(zh: "命令面板", en: "Command Palette"), outcome: t(zh: "打开或关闭可搜索的命令面板。", en: "Opens or closes the searchable command palette."), keywords: "command palette quick open", shortcutFallback: "Cmd-K", systemImage: "command", protocolMethod: "command.run")
        case .toggleWorkspaceOverview:
            return Descriptor(id: "workspace-overview", category: categoryView, title: t(zh: "工作区面板", en: "Workspaces"), outcome: t(zh: "打开工作区面板，查看项目、服务、标签和状态。", en: "Opens the workspace panel for projects, services, tabs, and status."), keywords: "workspace overview inspector mission control", shortcutFallback: "Cmd-O", systemImage: WorkspaceChromeGlyph.systemName(selected: false), protocolMethod: "command.run")
        case .toggleSettings:
            return Descriptor(id: "appearance-settings", category: categoryView, title: t(zh: "设置", en: "Settings"), outcome: t(zh: "打开设置，调整外观、终端、通知、更新和快捷键。", en: "Opens settings for appearance, terminal, notifications, updates, and shortcuts."), keywords: "appearance theme settings preferences", shortcutFallback: "Cmd-,", systemImage: "slider.horizontal.3", protocolMethod: "command.run")
        case .toggleFileManager:
            return Descriptor(id: "file-manager", category: categoryContext, title: t(zh: "文件管理器", en: "File Manager"), outcome: t(zh: "打开当前目录的文件浏览和预览面板。", en: "Opens file browsing and preview for the current directory."), keywords: "file files browser manager cwd folder directory preview", shortcutFallback: "Files", systemImage: "folder", protocolMethod: "command.run")
        case .jumpLatestUnreadAttention:
            return Descriptor(id: "jump-latest-unread", category: categoryAttention, title: t(zh: "跳到最新未读", en: "Jump to Latest Unread"), outcome: t(zh: "优先跳到当前工作区最新未读；当前工作区没有时，跳到全局最新未读。", en: "Jumps to the latest unread item in the current workspace first, then the latest unread item globally."), keywords: "attention notification unread latest jump focus", shortcutFallback: "Latest", systemImage: "arrow.right.circle", protocolMethod: "notification.focusLatest")
        case .markCurrentWorkspaceAttentionRead:
            return Descriptor(id: "mark-workspace-read", category: categoryAttention, title: t(zh: "当前工作区标记已读", en: "Mark Current Workspace Read"), outcome: t(zh: "把当前工作区的未读事件标记为已读，不影响其他工作区。", en: "Marks unread events in the current workspace as read without touching other workspaces."), keywords: "attention notification unread read workspace clear", shortcutFallback: "Read", systemImage: "checkmark.circle", protocolMethod: "notification.markRead")
        case .openTokenRecords:
            return Descriptor(id: "usage-records", category: categoryContext, title: t(zh: "Token 记录", en: "Usage Records"), outcome: t(zh: "打开用量记录和本地消耗信息。", en: "Opens usage records and local consumption details."), keywords: "usage token records cost quota", shortcutFallback: "Usage", systemImage: "chart.bar.doc.horizontal", protocolMethod: "command.run")
        case .toggleFullScreen:
            return Descriptor(id: "toggle-fullscreen", category: categoryView, title: t(zh: "切换全屏", en: "Toggle Full Screen"), outcome: t(zh: "让当前窗口进入或退出 macOS 全屏。", en: "Enters or exits macOS full screen for the current window."), keywords: "fullscreen window mac", shortcutFallback: "Ctrl-Cmd-F", systemImage: "arrow.up.left.and.arrow.down.right.circle", protocolMethod: "command.run")
        case .resetWorkspace:
            return Descriptor(id: "reset-workspace", category: categoryOrganize, title: t(zh: "重置工作区", en: "Reset Workspace"), outcome: t(zh: "清空当前工作区并重建一个干净终端布局。", en: "Clears the current workspace and recreates a clean terminal layout."), keywords: "workspace reset clean", shortcutFallback: "Reset", systemImage: "arrow.counterclockwise", protocolMethod: "command.run")
        case .showTerminalSearch:
            return Descriptor(id: "context-search", category: categorySearch, title: t(zh: "搜索当前上下文", en: "Search Current Context"), outcome: t(zh: "在当前终端、文件、网页或文件面板里打开搜索。", en: "Opens search in the current terminal, file, web tab, or file panel."), keywords: "search find terminal file document context", shortcutFallback: "Cmd-F", systemImage: "magnifyingglass", protocolMethod: "command.run")
        case .findNext:
            return Descriptor(id: "find-next", category: categorySearch, title: t(zh: "下一个搜索结果", en: "Next Search Result"), outcome: t(zh: "跳到当前搜索的下一个匹配项。", en: "Jumps to the next match in the current search."), keywords: "search find next match", shortcutFallback: "Cmd-G", systemImage: "arrow.down.doc", protocolMethod: "command.run")
        case .findPrevious:
            return Descriptor(id: "find-previous", category: categorySearch, title: t(zh: "上一个搜索结果", en: "Previous Search Result"), outcome: t(zh: "跳到当前搜索的上一个匹配项。", en: "Jumps to the previous match in the current search."), keywords: "search find previous match", shortcutFallback: "Cmd-Shift-G", systemImage: "arrow.up.doc", protocolMethod: "command.run")
        case .flashFocusedPane:
            return Descriptor(id: "flash-focused-pane", category: categoryView, title: t(zh: "闪烁当前分屏", en: "Flash Focused Pane"), outcome: t(zh: "短暂高亮当前焦点分屏，帮助定位。", en: "Briefly highlights the focused pane so it is easier to locate."), keywords: "flash highlight focused pane", shortcutFallback: "Cmd-Shift-H", systemImage: "scope", protocolMethod: "command.run")
        case .duplicateSelectedTab:
            return Descriptor(id: "duplicate-tab", category: categoryCreate, title: t(zh: "复制当前标签", en: "Duplicate Current Tab"), outcome: t(zh: "复制当前终端、网页或文件标签的工作上下文。", en: "Duplicates the selected terminal, web, or file tab context."), keywords: "copy tab duplicate", shortcutFallback: "Duplicate", systemImage: "plus.square.on.square", protocolMethod: "command.run")
        case .newTerminalAtFocusedDirectory:
            return Descriptor(id: "new-terminal-current-directory", category: categoryCreate, title: t(zh: "从当前目录新开终端", en: "New Terminal at Current Directory"), outcome: t(zh: "用当前终端目录创建一个新终端。", en: "Creates a new terminal using the current terminal directory."), keywords: "terminal cwd current directory folder", shortcutFallback: "Current CWD", systemImage: "arrow.turn.down.right", protocolMethod: "command.run")
        case .openFocusedDirectory:
            return Descriptor(id: "open-current-directory", category: categoryContext, title: t(zh: "打开当前目录", en: "Open Current Directory"), outcome: t(zh: "在 Finder 中打开当前终端目录。", en: "Opens the current terminal directory in Finder."), keywords: "open reveal finder cwd folder directory", shortcutFallback: "Finder", systemImage: "folder", protocolMethod: "command.run")
        case .copyFocusedDirectory:
            return Descriptor(id: "copy-current-directory", category: categoryContext, title: t(zh: "复制当前目录路径", en: "Copy Current Directory Path"), outcome: t(zh: "把当前终端目录路径复制到剪贴板。", en: "Copies the current terminal directory path to the clipboard."), keywords: "copy path cwd folder directory", shortcutFallback: "Copy", systemImage: "doc.on.doc", protocolMethod: "command.run")
        case .openCurrentWorkspaceRoot:
            return Descriptor(id: "workspace-open-root", category: categoryContext, title: t(zh: "打开当前工作区根目录", en: "Open Current Workspace Root"), outcome: t(zh: "在 Finder 中打开当前工作区的项目根目录。", en: "Opens the current workspace project root in Finder."), keywords: "workspace root finder project folder", shortcutFallback: "Workspace Root", systemImage: "folder", protocolMethod: "command.run")
        case .openCurrentWorkspaceFirstService:
            return Descriptor(id: "workspace-open-service", category: categoryContext, title: t(zh: "打开当前工作区本地服务", en: "Open Current Workspace Local Service"), outcome: t(zh: "用工作区检测到的第一个本地服务打开网页标签。", en: "Opens a web tab for the first local service detected in the current workspace."), keywords: "workspace port service localhost browser web", shortcutFallback: "Local Service", systemImage: "network", protocolMethod: "command.run")
        case .renameCurrentWorkspace:
            return Descriptor(id: "rename-workspace", category: categoryOrganize, title: t(zh: "重命名当前工作区", en: "Rename Current Workspace"), outcome: t(zh: "在顶部标签条进入当前工作区名称编辑。", en: "Starts inline editing for the current workspace name in the top tab strip."), keywords: "workspace rename title edit", shortcutFallback: "Rename", systemImage: "pencil", protocolMethod: "command.run")
        case .duplicateWorkspace:
            return Descriptor(id: "duplicate-workspace", category: categoryCreate, title: t(zh: "复制工作区", en: "Duplicate Workspace"), outcome: t(zh: "复制当前工作区布局，快速开一份相同上下文。", en: "Duplicates the current workspace layout for a second copy of the context."), keywords: "workspace duplicate", shortcutFallback: "Duplicate", systemImage: "plus.square.on.square", protocolMethod: "command.run")
        case .closeOtherWorkspaces:
            return Descriptor(id: "close-other-workspaces", category: categoryOrganize, title: t(zh: "关闭其他工作区", en: "Close Other Workspaces"), outcome: t(zh: "保留当前工作区，关闭其余工作区。", en: "Keeps the current workspace and closes the others."), keywords: "workspace close others", shortcutFallback: "Close Others", systemImage: "xmark.rectangle", protocolMethod: "command.run")
        case .closeWorkspacesToRight:
            return Descriptor(id: "close-workspaces-to-right", category: categoryOrganize, title: t(zh: "关闭右侧工作区", en: "Close Workspaces to the Right"), outcome: t(zh: "关闭当前工作区右侧的所有工作区。", en: "Closes all workspaces to the right of the current workspace."), keywords: "workspace close right", shortcutFallback: "Close Right", systemImage: "xmark.rectangle.fill", protocolMethod: "command.run")
        case .closeCurrentWorkspace:
            return Descriptor(id: "close-current-workspace", category: categoryOrganize, title: t(zh: "关闭当前工作区", en: "Close Current Workspace"), outcome: t(zh: "关闭当前工作区，并切到剩余工作区。", en: "Closes the current workspace and switches to another one."), keywords: "workspace close", shortcutFallback: "Close Workspace", systemImage: "xmark.rectangle", protocolMethod: "command.run")
        case .restorePreviousSession:
            return Descriptor(id: "restore-previous-session", category: categoryRecovery, title: t(zh: "恢复上一份会话", en: "Restore Previous Session"), outcome: t(zh: "用上一份有效快照替换当前工作台，并保留当前快照作为新的上一份。", en: "Replaces the current workbench with the previous valid snapshot while keeping the current snapshot as the new previous one."), keywords: "session restore previous fallback recovery snapshot", shortcutFallback: "Recovery", systemImage: "clock.arrow.circlepath", protocolMethod: "session.restorePrevious")
        case .resumeCurrentWorkspaceAgents:
            return Descriptor(id: "resume-workspace-agents", category: categoryRecovery, title: t(zh: "恢复当前工作区 Agent", en: "Resume Workspace Agents"), outcome: t(zh: "把当前工作区里可续跑的 Agent 恢复命令发送回对应终端。", en: "Sends supported agent resume commands back to matching terminals in the current workspace."), keywords: "agent resume restore workspace terminal codex claude", shortcutFallback: "Resume", systemImage: "arrow.clockwise.circle", protocolMethod: "terminal.resumeAgents")
        }
    }

    static var paletteOrder: [ConductorShellCommand] {
        [
            .newWorkspace, .newTerminal, .newWebTab, .newTerminalAtFocusedDirectory,
            .duplicateSelectedTab, .duplicateWorkspace,
            .focusWebAddress, .goBackSelectedWebTab, .goForwardSelectedWebTab,
            .reloadSelectedWebTab, .openSelectedWebTabExternally,
            .copySelectedWebTabURL, .copySelectedWebTabReference,
            .openSelectedFileExternally, .revealSelectedFileInFinder,
            .openFocusedDirectory, .copyFocusedDirectory,
            .openCurrentWorkspaceRoot, .openCurrentWorkspaceFirstService,
            .toggleFileManager,
            .openTokenRecords, .showTerminalSearch, .findNext, .findPrevious,
            .splitRight, .splitDown, .selectNextTab, .selectPreviousTab,
            .focusNextPane, .focusPreviousPane, .focusPaneLeft, .focusPaneRight,
            .focusPaneUp, .focusPaneDown, .closeSelectedTab, .closeOtherTabs,
            .closeTabsToRight, .closeFocusedPane, .moveTabLeft, .moveTabRight,
            .moveTabToNextPane, .moveTabToNewRightSplit, .moveTabToNewDownSplit,
            .resizePaneLeft, .resizePaneRight, .resizePaneUp, .resizePaneDown,
            .toggleZoom, .equalizeSplits, .flashFocusedPane, .toggleWorkspaceOverview,
            .toggleCommandPalette, .toggleSettings,
            .toggleFullScreen, .restorePreviousSession, .resumeCurrentWorkspaceAgents,
            .resetWorkspace, .renameCurrentWorkspace, .closeOtherWorkspaces, .closeWorkspacesToRight, .closeCurrentWorkspace
        ]
    }

    func displayTitle(model: ConductorWindowModel) -> String {
        switch self {
        case .reloadSelectedWebTab where model.selectedWorkspaceWebTab?.isLoading == true:
            return ConductorLocalization.text(zh: "停止载入网页", en: "Stop Loading Web Page")
        case .toggleZoom where model.workspace.isZoomed:
            return ConductorLocalization.text(zh: "还原当前分屏", en: "Restore Current Pane")
        default:
            return descriptor.title
        }
    }

    func disabledReason(model: ConductorWindowModel) -> String? {
        func t(zh: String, en: String) -> String {
            ConductorLocalization.text(zh: zh, en: en)
        }
        switch self {
        case .closeOtherTabs:
            return t(zh: "当前分屏没有其他标签", en: "Current pane has no other tabs")
        case .closeTabsToRight:
            return t(zh: "右侧没有可关闭的标签", en: "There are no tabs to the right")
        case .closeFocusedPane:
            return t(zh: "至少保留一个分屏", en: "Keep at least one pane")
        case .splitRight, .splitDown:
            return t(zh: "当前布局已到可用分屏上限", en: "Current layout has reached the split limit")
        case .equalizeSplits, .toggleZoom,
             .resizePaneLeft, .resizePaneRight, .resizePaneUp, .resizePaneDown:
            return t(zh: "需要多个分屏", en: "Requires multiple panes")
        case .moveTabLeft:
            return t(zh: "已经在最左侧", en: "Already on the left")
        case .moveTabRight:
            return t(zh: "已经在最右侧", en: "Already on the right")
        case .moveTabToNextPane:
            return t(zh: "需要另一个分屏", en: "Requires another pane")
        case .moveTabToNewRightSplit, .moveTabToNewDownSplit:
            return t(zh: "需要可移动标签和可用分屏空间", en: "Requires a movable tab and split space")
        case .duplicateSelectedTab:
            return t(zh: "当前没有可复制的标签", en: "No duplicable tab is selected")
        case .focusWebAddress:
            return t(zh: "当前没有网页标签", en: "No web tab is selected")
        case .goBackSelectedWebTab:
            return t(zh: "当前网页没有上一页", en: "Current web tab has no previous page")
        case .goForwardSelectedWebTab:
            return t(zh: "当前网页没有下一页", en: "Current web tab has no next page")
        case .reloadSelectedWebTab, .openSelectedWebTabExternally, .copySelectedWebTabURL, .copySelectedWebTabReference:
            return t(zh: "当前网页还没有地址", en: "Current web tab has no address")
        case .openSelectedFileExternally, .revealSelectedFileInFinder:
            return t(zh: "当前没有文件标签", en: "No file tab is selected")
        case .showTerminalSearch:
            return t(zh: "当前没有可搜索的终端、文件、网页或文件面板", en: "No searchable terminal, file, web tab, or file panel is active")
        case .findNext, .findPrevious:
            return t(zh: "先打开搜索", en: "Open search first")
        case .toggleFileManager, .newTerminalAtFocusedDirectory, .openFocusedDirectory, .copyFocusedDirectory:
            return t(zh: "当前终端还没有可用目录", en: "Current terminal has no available directory")
        case .openCurrentWorkspaceRoot:
            return t(zh: "当前工作区还没有项目根目录", en: "Current workspace has no project root")
        case .openCurrentWorkspaceFirstService:
            return t(zh: "当前工作区没有检测到本地服务", en: "Current workspace has no detected local service")
        case .closeCurrentWorkspace:
            return t(zh: "至少保留一个工作区", en: "Keep at least one workspace")
        case .closeOtherWorkspaces:
            return t(zh: "没有其他工作区可关闭", en: "No other workspaces to close")
        case .closeWorkspacesToRight:
            return t(zh: "右侧没有工作区", en: "No workspaces to the right")
        case .restorePreviousSession:
            return t(zh: "没有可用的上一份会话快照", en: "No previous session snapshot is available")
        case .resumeCurrentWorkspaceAgents:
            return t(zh: "当前工作区没有可续跑的 Agent", en: "Current workspace has no resumable agents")
        case .jumpLatestUnreadAttention:
            return t(zh: "没有未读事件", en: "No unread attention items")
        case .markCurrentWorkspaceAttentionRead:
            return t(zh: "当前工作区没有未读事件", en: "Current workspace has no unread attention items")
        default:
            return nil
        }
    }

    var allowsWhenSettingsPanelVisible: Bool {
        switch self {
        case .toggleSettings:
            true
        default:
            false
        }
    }

    var signpostName: StaticString {
        switch self {
        case .newWorkspace:
            return "command-new-workspace"
        case .newTerminal, .newTerminalAtFocusedDirectory:
            return "command-new-terminal"
        case .newWebTab:
            return "command-new-web-tab"
        case .focusWebAddress, .goBackSelectedWebTab, .goForwardSelectedWebTab,
             .reloadSelectedWebTab, .openSelectedWebTabExternally, .copySelectedWebTabURL, .copySelectedWebTabReference:
            return "command-web-tab"
        case .openSelectedFileExternally, .revealSelectedFileInFinder:
            return "command-file-tab"
        case .closeSelectedTab, .closeOtherTabs, .closeTabsToRight:
            return "command-close-tab"
        case .closeFocusedPane:
            return "command-close-pane"
        case .splitRight, .splitDown:
            return "command-split"
        case .selectNextTab, .selectPreviousTab:
            return "command-select-tab"
        case .focusNextPane, .focusPreviousPane, .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown:
            return "command-focus-pane"
        case .resizePaneLeft, .resizePaneRight, .resizePaneUp, .resizePaneDown:
            return "command-resize-pane"
        case .equalizeSplits:
            return "command-equalize-splits"
        case .toggleZoom:
            return "command-toggle-zoom"
        case .moveTabLeft, .moveTabRight, .moveTabToNextPane, .moveTabToNewRightSplit, .moveTabToNewDownSplit:
            return "command-move-tab"
        case .toggleCommandPalette:
            return "command-toggle-palette"
        case .toggleWorkspaceOverview:
            return "command-toggle-overview"
        case .toggleSettings:
            return "command-toggle-settings"
        case .toggleFileManager:
            return "command-file-manager"
        case .jumpLatestUnreadAttention, .markCurrentWorkspaceAttentionRead:
            return "command-attention-action"
        case .openTokenRecords:
            return "command-token-records"
        case .toggleFullScreen:
            return "command-toggle-fullscreen"
        case .resetWorkspace:
            return "command-reset-workspace"
        case .showTerminalSearch, .findNext, .findPrevious:
            return "command-terminal-search"
        case .flashFocusedPane:
            return "command-flash-pane"
        case .duplicateSelectedTab:
            return "command-duplicate-tab"
        case .openFocusedDirectory, .copyFocusedDirectory, .openCurrentWorkspaceRoot, .openCurrentWorkspaceFirstService:
            return "command-directory"
        case .renameCurrentWorkspace, .duplicateWorkspace, .closeOtherWorkspaces, .closeWorkspacesToRight, .closeCurrentWorkspace:
            return "command-workspace"
        case .restorePreviousSession, .resumeCurrentWorkspaceAgents:
            return "command-restore-session"
        }
    }

    func canPerform(model: ConductorWindowModel) -> Bool {
        return switch self {
        case .closeOtherTabs:
            model.workspace.canCloseOtherTabs(in: model.workspace.focusedPaneID)
        case .closeTabsToRight:
            if let pane = model.workspace.focusedPane {
                model.workspace.canCloseTabsToRight(of: pane.selectedTabID, in: pane.id)
            } else {
                false
            }
        case .closeFocusedPane:
            model.canCloseFocusedPane
        case .splitRight, .splitDown:
            model.canSplit
        case .equalizeSplits, .toggleZoom,
             .resizePaneLeft, .resizePaneRight, .resizePaneUp, .resizePaneDown:
            model.workspace.root.leaves.count > 1
        case .moveTabLeft:
            model.canMoveSelectedTabLeft
        case .moveTabRight:
            model.canMoveSelectedTabRight
        case .moveTabToNextPane:
            model.canMoveSelectedTabToNextPane
        case .moveTabToNewRightSplit, .moveTabToNewDownSplit:
            model.canMoveSelectedTabToNewSplit
        case .duplicateSelectedTab:
            model.selectedWorkspaceWebTab != nil || model.selectedWorkspaceFileTab != nil || model.workspace.focusedPane != nil
        case .focusWebAddress:
            model.selectedWorkspaceWebTab != nil
        case .goBackSelectedWebTab:
            model.selectedWorkspaceWebTab?.canGoBack == true
        case .goForwardSelectedWebTab:
            model.selectedWorkspaceWebTab?.canGoForward == true
        case .reloadSelectedWebTab:
            model.selectedWorkspaceWebTab?.url != nil
        case .openSelectedWebTabExternally, .copySelectedWebTabURL, .copySelectedWebTabReference:
            model.selectedWorkspaceWebTab?.url != nil
        case .openSelectedFileExternally, .revealSelectedFileInFinder:
            model.selectedWorkspaceFileTab != nil
        case .showTerminalSearch:
            model.selectedWorkspaceWebTab != nil || model.selectedWorkspaceFileTab != nil || model.fileManagerPanelRequest != nil || model.focusedTerminalID != nil
        case .findNext, .findPrevious:
            model.selectedWorkspaceWebTab?.url != nil || model.terminalSearchVisible || model.selectedWorkspaceFileTab != nil || model.fileManagerPanelRequest != nil
        case .toggleFileManager:
            model.fileManagerPanelRequest != nil || model.focusedWorkingDirectoryURL != nil
        case .openCurrentWorkspaceRoot:
            model.currentWorkspaceRootURL != nil
        case .openCurrentWorkspaceFirstService:
            model.currentWorkspaceFirstLocalServiceURL != nil
        case .closeOtherWorkspaces:
            model.workspaces.count > 1
        case .closeWorkspacesToRight:
            if let index = model.workspaces.firstIndex(where: { $0.id == model.workspace.id }) {
                index < model.workspaces.count - 1
            } else {
                false
            }
        case .closeCurrentWorkspace:
            model.workspaces.count > 1
        case .restorePreviousSession:
            model.canRestorePreviousSessionSnapshot
        case .resumeCurrentWorkspaceAgents:
            !model.controlResumableTerminalAgents().isEmpty
        case .jumpLatestUnreadAttention:
            model.hasUnreadAttentionEvent()
        case .markCurrentWorkspaceAttentionRead:
            model.hasUnreadAttentionEvent(in: model.controlSelectedWorkspaceID)
        case .newTerminalAtFocusedDirectory, .openFocusedDirectory, .copyFocusedDirectory:
            model.focusedWorkingDirectoryURL != nil
        default:
            true
        }
    }

    @discardableResult
    func perform(model: ConductorWindowModel, window: NSWindow? = nil) -> Bool {
        guard canPerform(model: model) else { return false }
        switch self {
        case .newWorkspace:
            model.newWorkspace()
        case .newTerminal:
            model.newTerminal()
        case .newWebTab:
            model.newWorkspaceWebTab()
        case .focusWebAddress:
            model.focusSelectedWorkspaceWebAddress()
        case .goBackSelectedWebTab:
            if let tabID = model.selectedWorkspaceWebTabID {
                model.goBackWorkspaceWebTab(tabID)
            }
        case .goForwardSelectedWebTab:
            if let tabID = model.selectedWorkspaceWebTabID {
                model.goForwardWorkspaceWebTab(tabID)
            }
        case .reloadSelectedWebTab:
            model.reloadOrStopSelectedWorkspaceWebTab()
        case .openSelectedWebTabExternally:
            model.openSelectedWorkspaceWebTabExternally()
        case .copySelectedWebTabURL:
            model.copySelectedWorkspaceWebTabURL()
        case .copySelectedWebTabReference:
            model.copySelectedWorkspaceWebTabReference()
        case .openSelectedFileExternally:
            model.openSelectedWorkspaceFileTabExternally()
        case .revealSelectedFileInFinder:
            model.revealSelectedWorkspaceFileTabInFinder()
        case .closeSelectedTab:
            model.closeSelectedTab()
        case .closeOtherTabs:
            model.closeOtherTabs(in: model.workspace.focusedPaneID)
        case .closeTabsToRight:
            model.closeTabsToRight(in: model.workspace.focusedPaneID)
        case .closeFocusedPane:
            model.closePane(model.workspace.focusedPaneID)
        case .splitRight:
            model.splitRight()
        case .splitDown:
            model.splitDown()
        case .selectNextTab:
            model.selectNextTab()
        case .selectPreviousTab:
            model.selectPreviousTab()
        case .focusNextPane:
            model.focusNextPane()
        case .focusPreviousPane:
            model.focusPreviousPane()
        case .focusPaneLeft:
            model.focusPane(direction: .left)
        case .focusPaneRight:
            model.focusPane(direction: .right)
        case .focusPaneUp:
            model.focusPane(direction: .up)
        case .focusPaneDown:
            model.focusPane(direction: .down)
        case .resizePaneLeft:
            model.resizeFocusedSplit(direction: .left)
        case .resizePaneRight:
            model.resizeFocusedSplit(direction: .right)
        case .resizePaneUp:
            model.resizeFocusedSplit(direction: .up)
        case .resizePaneDown:
            model.resizeFocusedSplit(direction: .down)
        case .equalizeSplits:
            model.equalizeSplits()
        case .toggleZoom:
            model.toggleZoom()
        case .moveTabLeft:
            model.moveSelectedTabLeft()
        case .moveTabRight:
            model.moveSelectedTabRight()
        case .moveTabToNextPane:
            model.moveSelectedTabToNextPane()
        case .moveTabToNewRightSplit:
            model.moveSelectedTabToNewSplit(.right)
        case .moveTabToNewDownSplit:
            model.moveSelectedTabToNewSplit(.down)
        case .toggleCommandPalette:
            model.toggleCommandPalette()
        case .toggleWorkspaceOverview:
            model.toggleWorkspaceOverview()
        case .toggleSettings:
            model.toggleSettingsPanel()
        case .toggleFileManager:
            model.toggleFileManagerPanel()
        case .jumpLatestUnreadAttention:
            model.focusLatestUnreadAttentionEvent()
        case .markCurrentWorkspaceAttentionRead:
            model.markCurrentWorkspaceAttentionRead()
        case .openTokenRecords:
            model.openTokenRecordsPanel()
        case .toggleFullScreen:
            (window ?? NSApp.keyWindow)?.toggleFullScreen(nil)
        case .resetWorkspace:
            model.resetWorkspace()
        case .showTerminalSearch:
            model.showTerminalSearch()
        case .findNext:
            model.navigateTerminalSearch(previous: false)
        case .findPrevious:
            model.navigateTerminalSearch(previous: true)
        case .flashFocusedPane:
            model.flashFocusedPane()
        case .duplicateSelectedTab:
            model.duplicateSelectedTab()
        case .newTerminalAtFocusedDirectory:
            model.newTerminalAtFocusedDirectory()
        case .openFocusedDirectory:
            model.openFocusedDirectory()
        case .copyFocusedDirectory:
            model.copyFocusedDirectory()
        case .openCurrentWorkspaceRoot:
            model.openCurrentWorkspaceRootInFinder()
        case .openCurrentWorkspaceFirstService:
            model.openCurrentWorkspaceFirstLocalService()
        case .renameCurrentWorkspace:
            model.requestRenameCurrentWorkspace()
        case .duplicateWorkspace:
            model.duplicateWorkspace(model.workspace.id)
        case .closeOtherWorkspaces:
            model.closeOtherWorkspaces(keeping: model.workspace.id)
        case .closeWorkspacesToRight:
            model.closeWorkspacesToRight(of: model.workspace.id)
        case .closeCurrentWorkspace:
            model.closeWorkspace(model.workspace.id)
        case .restorePreviousSession:
            model.restorePreviousSessionSnapshot()
        case .resumeCurrentWorkspaceAgents:
            _ = model.controlResumeTerminalAgents()
        }
        return true
    }
}
