import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func beginPresentation() {
        isPanelPresentationActive = true
        shouldAutoFollowTopItemDuringPresentation = true
        // Preserve the current selection until the presentation flow resolves the default
        // first-item focus. Clearing first causes a visible deselect/reselect flash when
        // the first item is already active.
        resetSearchForPresentationIfNeeded()

        if hasPreparedPanelData == false {
            hasPreparedPanelData = true
            hydrateFromWarmCacheIfAvailable()
            shouldResetSelectionToFirstDisplayedItem = true
            loadData(mode: .visibleFirst)
            loadCustomGroups()
            return
        }

        guard needsReloadOnNextPresentation else { return }
        needsReloadOnNextPresentation = false
        shouldResetSelectionToFirstDisplayedItem = true
        loadData(mode: .fullRefresh)
        loadCustomGroups()
    }

    func endPresentation() {
        isPanelPresentationActive = false
        shouldAutoFollowTopItemDuringPresentation = false
    }

    func setupDataSubscriptions() {
        NotificationCenter.default.publisher(for: .clipboardDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.hasPreparedPanelData else { return }
                guard self.isPanelPresentationActive else {
                    self.needsReloadOnNextPresentation = true
                    return
                }
                self.loadData()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .didFinishDataMigration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.hasPreparedPanelData else { return }
                guard self.isPanelPresentationActive else {
                    self.needsReloadOnNextPresentation = true
                    return
                }
                self.reloadPanelDataAfterMigration()
            }
            .store(in: &cancellables)
    }

    func setupWarmCacheSubscription() {
        NotificationCenter.default.publisher(for: .clipboardWarmCacheDidChange)
            .compactMap(\.clipboardWarmCacheChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                guard change.routeKey == ClipboardRuntimeStore.shared.rootIdentity else { return }
                self.hydrateFromWarmCacheIfAvailable()
            }
            .store(in: &cancellables)
    }

    func reloadPanelDataAfterMigration() {
        loadData()
        loadCustomGroups()
    }

    func resetSearchForPresentationIfNeeded() {
        guard settingsViewModel.clearSearchOnPanelActivation else { return }
        guard !searchInput.isEmpty || !activeSearchQuery.isEmpty else { return }

        searchInput = ""
        activeSearchQuery = ""
    }

    func triggerAutoCleanup() {
        let retentionRaw = UserDefaults.standard.string(forKey: "historyRetention") ?? HistoryRetention.oneMonth.rawValue
        guard let retention = HistoryRetention(rawValue: retentionRaw),
              let expirationDate = retention.expirationDate else { return }

        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            StorageManager.shared.performAutoCleanup(before: expirationDate)
        }
    }

    func hydrateFromWarmCacheIfAvailable() {
        guard searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              currentFilter == nil,
              selectedBuiltInGroup == nil,
              selectedGroupId == nil else {
            return
        }

        let routeKey = ClipboardRuntimeStore.shared.rootIdentity
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let cachedItems = await ClipboardHistoryWarmCache.shared.snapshot(for: routeKey) else { return }
            guard self.items.isEmpty || self.hasPreparedPanelData == false else { return }
            self.applyLoadedItems(cachedItems)
            self.loadedHistoryCount = cachedItems.count
            self.hasLoadedFullHistory = cachedItems.count < ClipboardHistoryWarmCache.defaultLimit
        }
    }
}
