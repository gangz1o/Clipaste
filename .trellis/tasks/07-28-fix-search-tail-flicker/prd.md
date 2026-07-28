# 修复搜索结果尾部闪烁

## Goal

Stop clipboard search results at the end of the list from repeatedly disappearing and reappearing.

## Requirements

- Database search supplements must append only items that can actually be merged into the in-memory item store.
- Duplicate records with a different UUID but an already-present content hash must not retrigger the search pipeline.
- Publishing an unchanged filtered ID sequence must be a no-op so stable search results do not invalidate the list again.
- Keep filtering and deduplication in the ViewModel/model layer; SwiftUI views remain render-only.

## Acceptance Criteria

- [x] A regression test covers supplemental results that duplicate an existing content hash under a different UUID.
- [x] Supplemental item IDs always resolve to items in the ViewModel after merge.
- [x] Re-running a filter with the same result IDs does not republish the displayed list.
- [x] The macOS app builds successfully.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
