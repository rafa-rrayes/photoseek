# iOS UI/UX Revamp — 2026-07-14

## Root cause of "Select doesn't work"
The iOS UI put Select / media filter / gear in the navigation toolbar and used
`.searchable`. On iOS 26 the search field renders as a floating bottom pill and,
while a query is active, the nav toolbar is minimized away — so Select, the
All/Photos/Videos picker, and Settings are all unreachable exactly when there
are results. The selection logic itself (view model + action bar) already works.

## Plan
- [x] Diagnose select-mode bug (toolbar hidden by iOS 26 search UX)
- [ ] `iOSSearchHeader.swift` (new): always-visible glass header — search field
      (magnifier, clear button, spinner), gear; second row when results:
      All/Photos/Videos segmented + Select/Done. Liquid Glass on iOS 26,
      material fallback for iOS 17–18.
- [ ] `iOSContentView.swift`: drop `.searchable`/nav toolbar; safe-area-inset
      header; indexing progress banner on main screen; full-screen photo viewer;
      keep sheets/alerts.
- [ ] `iOSPhotoGrid.swift`: Photos-app-style 3-column grid, 2pt gutters,
      scroll-dismisses-keyboard, long-press to enter selection.
- [ ] `iOSPhotoCell.swift`: Photos-style selection (dim + checkmark bottom-right),
      long-press support, haptics.
- [ ] `iOSActionBar.swift`: redesigned floating glass bar — count, Select All,
      favorite, unfavorite, add-to-album, delete, dismiss.
- [ ] `iOSPhotoViewer.swift` (new): in-app full-screen viewer — swipe between
      results, pinch/double-tap zoom (UIScrollView-backed), video playback,
      favorite/share/delete, replaces "kick out to Photos app" openPhoto UX.
- [ ] Core: `SearchViewModel.removeFromResults` + select-mode entry helper;
      `deletePhotos` returns success so deleted items leave the results grid.
- [ ] Verify: xcodegen + xcodebuild (iOS sim) and `swift build` (macOS) both green.

## Review
(to fill in after implementation)
