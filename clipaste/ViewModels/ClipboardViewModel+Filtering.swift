import AppKit
import Combine
import SwiftUI

extension ClipboardViewModel {
    func setupFilterPipeline() {
        let searchQueries = $searchInput
            .map { query -> AnyPublisher<String, Never> in
                let isEffectivelyEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if isEffectivelyEmpty {
                    return Just(query)
                        .eraseToAnyPublisher()
                }

                return Just(query)
                    .delay(for: .milliseconds(200), scheduler: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()

        let dataChanges = Publishers.CombineLatest3($items, $selectedGroupId, $currentFilter)

        Publishers.CombineLatest(searchQueries, dataChanges)
            .sink { [weak self] (query, triple) in
                guard let self else { return }
                let (allItems, groupId, filter) = triple
                self.activeSearchQuery = query
                self.performAsyncFilter(query: query, items: allItems, groupId: groupId, typeFilter: filter)
            }
            .store(in: &cancellables)
    }

    func performAsyncFilter(query: String, items: [ClipboardItem], groupId: String?, typeFilter: ClipboardContentType?) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        filterGeneration &+= 1
        let thisGeneration = filterGeneration

        if cleanQuery.isEmpty && groupId == nil && typeFilter == nil {
            self.displayedItemIDs = items.map(\.id)
            reconcileSelectionAfterDisplayedItemsChange()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let filteredIDs = items.compactMap { item -> UUID? in
                if let filter = typeFilter, item.contentType != filter {
                    return nil
                }

                if let gid = groupId, item.groupIDs.contains(gid) == false {
                    return nil
                }

                if !cleanQuery.isEmpty {
                    let searchable = item.searchableText ?? item.rawText ?? item.textPreview
                    let matchesText = searchable.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    let matchesApp = item.appName.range(of: cleanQuery, options: [.caseInsensitive]) != nil

                    guard matchesText || matchesApp else {
                        return nil
                    }
                }

                return item.id
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.filterGeneration == thisGeneration else { return }
                self.displayedItemIDs = filteredIDs
                self.reconcileSelectionAfterDisplayedItemsChange()
            }
        }
    }

    func loadData(mode: DataLoadMode = .fullRefresh) {
        let container = StorageManager.shared.container
        dataLoadGeneration &+= 1
        let generation = dataLoadGeneration

        if items.isEmpty {
            isInitialHistoryLoading = true
        }

        Task(priority: .userInitiated) {
            let searcher = ClipboardSearcher(modelContainer: container)

            if mode == .visibleFirst {
                let previewItems = await searcher.searchAndMap(
                    searchText: "",
                    fetchLimit: Self.initialVisibleItemBatchSize
                )

                guard !Task.isCancelled else { return }
                guard generation == self.dataLoadGeneration else { return }

                self.applyLoadedItems(previewItems)
            }

            let mappedItems = await searcher.searchAndMap(searchText: "")

            guard !Task.isCancelled else { return }
            guard generation == self.dataLoadGeneration else { return }

            self.applyLoadedItems(mappedItems)
        }
    }

    func applyLoadedItems(_ mappedItems: [ClipboardItem]) {
        replaceItems(mappedItems)
        isInitialHistoryLoading = false

        if searchInput.isEmpty && currentFilter == nil && selectedGroupId == nil {
            displayedItemIDs = mappedItems.map(\.id)
            reconcileSelectionAfterDisplayedItemsChange()
        }

        let validIDs = Set(mappedItems.map(\.id))
        let staleIDs = selectedItemIDs.subtracting(validIDs)
        if !staleIDs.isEmpty {
            selectedItemIDs.subtract(staleIDs)
        }
        if let anchor = lastSelectedID, !validIDs.contains(anchor) {
            lastSelectedID = nil
        }

        reconcileSelectionAfterDisplayedItemsChange()
    }
}
