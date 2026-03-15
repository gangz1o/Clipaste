import AppKit

/// 独立的键盘盲打嗅探服务（Service Layer）
///
/// 职责单一：拦截面板上尚未被任何输入框消费的可见字符按键，
/// 通过回调将字符和聚焦请求传递给上层。
///
/// ⚠️ 与 SwiftUI View 完全解耦，不持有任何 View/ViewModel 引用。
/// ⚠️ 必须在主线程调用 start()/stop()，生命周期由调用方管理。
final class TypeToSearchService {

    static let shared = TypeToSearchService()

    // MARK: - 外部同步的状态

    /// 由上层控制：当存在带有文本输入的二级窗口/面板时置 true，
    /// 此时所有按键直接放行，不执行任何拦截和强制聚焦操作。
    var isPaused: Bool = false

    /// 由 View 层实时同步：当搜索框获得焦点时置 true，
    /// 此时所有按键直接放行给 TextField 原生处理。
    var isTextFieldFocused: Bool = false

    // MARK: - 回调

    /// 捕获到可见字符时回调，参数为字符串（通常单字符）
    var onCapture: ((String) -> Void)?

    /// 需要聚焦搜索框时回调（UI 层设置 @FocusState）
    var onRequireFocus: (() -> Void)?

    // MARK: - 内部状态

    private var localMonitor: Any?

    // MARK: - 生命周期

    func start() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    func stop() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        stop()
    }

    // MARK: - 核心拦截逻辑

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // 0. 休眠状态 → 所有按键原封不动还给系统（编辑窗口等二级面板场景）
        if isPaused { return event }

        // 1. 搜索框已聚焦 → 全部放行，由 TextField 原生消费
        if isTextFieldFocused { return event }

        // 2. 修饰键组合 → 放行（Cmd+C / Ctrl+A / Option+… 等系统快捷键）
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return event
        }

        // 3. 提取可见字符
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            return event
        }

        // 4. 过滤控制字符（回车、Esc、Tab、方向键、功能键等）
        let scalar = chars.unicodeScalars.first!
        // 可见 ASCII 范围：0x21 (!) ~ 0x7E (~)，加上非 ASCII 字符（如中文拼音首字母）
        let isPrintable = (scalar.value >= 0x21 && scalar.value <= 0x7E)
                          || scalar.value > 0x7F
        guard isPrintable else { return event }

        // 5. 捕获字符 → 注入搜索词 → 请求聚焦
        onCapture?(chars)
        onRequireFocus?()

        // 6. 消耗事件，防止系统发出 "咚" 的无效按键音
        return nil
    }
}
