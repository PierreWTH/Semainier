# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Semainier: SwiftUI app for iOS 26 (Liquid Glass) with SwiftData. Everything is in French: UI strings, comments, and many identifiers (`fond`, `texte2`, `depassement`, `Arrondi`, `Police`). Write new code the same way.

## Commands

- Unit tests (Swift Testing, ~40 s with the build): `xcodebuild -project Semainier.xcodeproj -scheme Semainier -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SemainierTests`
- UI tests (XCTest, ~1 min): same command with `-only-testing:SemainierUITests`. Run them only when gestures or the UI tests' identifiers/labels may be affected; for model or calculation changes, the unit tests are enough.
- Simulator screenshots: `scripts/shots.sh <dir> planning:semaine planning:jour courses recettes ingredients` (`recettes` / `ingredients` open the Cuisine tab on that side). It writes the `tab` and `planning.mode` prefs directly, because the value the app has saved wins over the launch argument.
- Install on the iPhone: `scripts/install-iphone.sh`. Signing uses a free account and expires after 7 days. Ignore the "No provider was found" warning from devicectl.
- Launch arguments (DEBUG): `-UITestData` uses an in-memory store with a "Skyr test" recipe. `-PerfData` uses an in-memory store with a year of planning (~2 500 dishes), for performance checks. Also `-tab planning|courses|cuisine`, `-cuisine.mode plats|ingredients` and `-planning.mode semaine|jour`. A launch argument freezes that `@AppStorage` value for the whole session (the argument domain wins over the app's writes): don't pass one for a value the test then changes in-app (e.g. tapping the Plats/Ingrédients picker), and don't pass `-tab recettes|ingredients` (the migration to `cuisine` can't apply, so no tab is selected). Write the pref with `simctl spawn … defaults write` instead. `-DisableAnimations` turns off UIKit animations; UI tests must pass it, otherwise an open context menu keeps the app from going idle and each XCUITest action waits 60 s.

## Pitfalls

- The project uses synchronized folders (objectVersion 77). Any file added under `Semainier/` is compiled automatically, so never edit `project.pbxproj` to add one.
- `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO`: the colours are declared by hand in `Semainier/UI/Theme.swift`. Generated symbols would clash with them.
- `semainier-da/Theme.swift` is the design-direction reference and is not compiled. The app's version is `Semainier/UI/Theme.swift`. Its `Rayon` enum is renamed `Arrondi`, because `Rayon` is the shop-aisle enum in `Nutrition.swift`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure types in `Core/` are marked `nonisolated`.
- The SwiftData schema is versioned (`Model/Schema.swift`: `SchemaV1` + `PlanDeMigration`), so existing stores keep opening. Never change a stored property of the `@Model` classes in place: add a `SchemaV2` and a migration stage. `SchemaTests` checks that a pre-versioning store still opens.
- Errors go to `Journal` (os `Logger`), never a silent `try?`: use `context.lire(…)`, `context.compter(…)` and `context.enregistrer()`.
- The UI tests depend on the identifiers `cell-<column>-<meal>` and `entry-<title>` and on the "Ajouter un plat" label. Keep them.
- If you add temporary data to `Model/UITestData.swift` for screenshots, always restore the file afterwards.
- The Week grid is UIKit (`Planning/WeekGrid.swift`: `UICollectionView` + custom layout, SwiftUI content via `UIHostingConfiguration`). Row heights are measured from the cells' SwiftUI content (`measuring: true` variant, no `maxHeight: .infinity`); `WeekView.layoutKey` must change whenever a row height can change, or the grid won't remeasure. `matchedGeometryEffect` can't cross into the grid's cells.

## Design direction

- Visual reference: `semainier-da/DA.md`, plus colours in `Semainier/Couleurs.xcassets`. When a visual decision changes, update DA.md.
- Use tokens (`Color.fond`, `.police(...)`, `Arrondi`, `Espace`) and never literal colours.
- UI text, README and script messages never address the user as « tu »: use the infinitive (« Toucher un jour pour l'ouvrir », « Recopier les valeurs ») or an impersonal phrasing (« Le planning attend ses premiers plats »).
- Restyle system components; never replace them.
- Macro order: Glucides · Protéines · Lipides.
- Numbers use `.monospacedDigit()` and fr_FR formatting through `Fmt`.
- A value is over target above +3 % (`Seuil`, `etatJour`). Bars are capped at 100 %.
- Support Dynamic Type through `@ScaledMetric`.
- A design change must not change any feature or gesture unless asked.

## Workflow

- After a UI change: run the tests (see above for which ones), check simulator screenshots in light and dark mode, then install on the iPhone. The `/verifier` skill does all of this. When the user says to skip the tests, just reinstall.
- Commit messages: short, in English.
