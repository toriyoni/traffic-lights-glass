# Easier menu entry and removal of retired appearances

Validated on macOS 27.2.1 with the macOS 26.5 SDK, 2026-11-14.

## Menu entry

The previous green-to-arrow corridor was narrow. Diagonal movement, especially while the green light shrank back, could leave that corridor before reaching the menu body.

The menu now uses separate **retention** and **click** regions:

- While moving toward the menu, a wider funnel from the live green button to the full near edge of the menu protects entry for up to **0.35 seconds**. Both above-window and below-window placement are supported.
- Once inside, a **6 pt** edge tolerance lasts up to **0.18 seconds**, allowing small accidental excursions and re-entry.
- Entering the actual menu or green circle clears the expiry. Continued mouse events in empty space do not renew it; a timer also closes the menu if the pointer stops there.
- Turning away, leaving the protection area, or moving into the actual red/yellow hit lanes closes immediately. Other-light hit testing runs before retention, including when the menu is clamped against the right display edge.
- Clicks and scrolls outside the menu still dismiss it. `ignoresMouseEvents` is determined exclusively by the visible menu shape, so the larger retention region never intercepts buttons, window dragging or background content. The anchor does not move.

`ZoomMenuHoverProtection` contains the time/direction policy separately from the panel. `ZoomMenuPanel` owns and cancels the expiry; `WindowOverlay` supplies live geometry, pointer position and the red/yellow hit lanes. Opening still requires dwelling on the actual green circle for 0.5 seconds.

## Appearance cleanup

Liquid Glass is now the sole appearance. The two retired picker options, their drawing/layout branches, classic hover reset and three unused individual overlay windows have been removed. Standalone button windows remain only as test fixtures. Older systems and Reduce Transparency keep the existing material fallback.

Stored `macOS`, `edgeSquares` or invalid appearance values migrate to `liquidGlass`. Sizes, application rules, actions, transparency policy and unrelated preferences are retained. Old spacing/reveal values are left in storage for rollback but no longer appear as settings for retired styles. The settings preview uses a separate glass background so its AppKit button views remain visible.

## Checks

144 Swift tests passed. Added coverage includes diagonal entry with a shrinking source, placement above/below and at the right screen edge, reversal, finite expiry, small edge excursions, cancellation after successful entry, click pass-through, and preference migration.

A separate native window fixture exercised the production `WindowOverlay` and menu with controlled pointer coordinates. It confirmed that only one grouped overlay window is created, red/yellow never trigger the menu, late hover requests are cancelled, diagonal entry is protected, menu input stays active after expiry is cancelled, external padding passes clicks through, and yellow magnification remains responsive after dismissal. The result is recorded in [native-window-checks.txt](menu-approach-protection/native-window-checks.txt).

These are automated and native fixture checks on this Mac. They do not replace subjective feel evaluation, every third-party application's behavior, or testing on other macOS versions.
