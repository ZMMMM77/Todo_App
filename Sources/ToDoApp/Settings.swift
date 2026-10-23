import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable { case chinese, english }
enum AppTheme: String, CaseIterable { case system, light, dark }

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "interfaceLanguage"); onChange?() }
    }
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "interfaceTheme"); onChange?() }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .chinese
        theme = AppTheme(rawValue: defaults.string(forKey: "interfaceTheme") ?? "") ?? .system
    }
    var locale: Locale { Locale(identifier: language == .english ? "en_US" : "zh_CN") }
    func applyAppearance() {
        // nil restores live inheritance from the macOS system appearance.
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func text(_ key: String) -> String {
        if language == .english { return Self.english[key] ?? key }
        if key == "读取失败" { return "无法读取本地任务。为保护原文件，已暂停修改。" }
        if key == "保存失败" { return "保存失败，修改未写入。请检查磁盘空间和文件权限。" }
        return key
    }
    static let english: [String: String] = [
        "待办": "To-do",
        "任务": "Task",
        "待完成": "To do",
        "恢复任务": "Restore task",
        "完成任务": "Complete task",
        "拖动排序；右键可移动或删除": "Drag to reorder; right-click to move or delete",
        "上移": "Move up",
        "下移": "Move down",
        "删除": "Delete",
        "悬停查看待办 · 拖动调整位置": "Hover to view tasks · Drag to move",
        "本地数据提示": "Local data notice",
        "知道了": "OK",
        "打开数据文件夹": "Open data folder",
        "取消固定": "Unpin panel",
        "固定面板": "Pin panel",
        "收起": "Collapse",
        "给今天留一点空间": "Make room for today",
        "在下面记下一件想做的事": "Add something you would like to do",
        "收起已完成": "Hide completed tasks",
        "展开已完成": "Show completed tasks",
        "已删除任务": "Task deleted",
        "撤销": "Undo",
        "输入新待办": "Enter a new task",
        "添加一件待办…": "Add a task…",
        "添加任务": "Add task",
        "仅存储在此 Mac": "Stored on this Mac",
        "拖动顶部移动": "Drag top to move",
        "显示待办": "Show tasks",
        "隐藏悬浮球": "Hide floating dot",
        "打开本地数据文件夹": "Open local data folder",
        "退出 ToDo App": "Quit ToDo App",
        "设置": "Settings",
        "语言": "Language",
        "外观": "Appearance",
        "跟随系统": "System",
        "浅色": "Light",
        "深色": "Dark",
        "跟随系统自动切换浅色与深色": "Automatically match your Mac’s appearance",
        "设置自动保存": "Settings saved automatically",
        "关闭设置": "Close settings",
        "已完成": "Completed",
        "读取失败": "Could not read local tasks. Changes are disabled to protect the existing file.",
        "保存失败": "Could not save changes. Please check disk space and file permissions.",
    ]
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(settings.text("设置")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(settings.text("关闭设置"))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.text("语言")).font(.headline)
                Picker(settings.text("语言"), selection: $settings.language) {
                    Text("中文").tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.text("外观")).font(.headline)
                HStack(spacing: 8) {
                    themeButton(.system, title: "跟随系统", icon: "desktopcomputer")
                    themeButton(.light, title: "浅色", icon: "sun.max")
                    themeButton(.dark, title: "深色", icon: "moon")
                }
                Text(settings.text("跟随系统自动切换浅色与深色"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Label(settings.text("设置自动保存"), systemImage: "internaldrive")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(22).frame(width: 320)
        .environment(\.locale, settings.locale)
    }
    func themeButton(_ theme: AppTheme, title: String, icon: String) -> some View {
        Button { settings.theme = theme } label: {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 23, weight: .light))
                Text(settings.text(title)).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity).frame(height: 90)
            .background(settings.theme == theme ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(settings.theme == theme ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(settings.text(title))
        .accessibilityValue(settings.theme == theme ? "Selected" : "")
    }
}
