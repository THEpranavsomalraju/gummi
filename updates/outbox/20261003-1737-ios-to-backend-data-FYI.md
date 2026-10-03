=== LEAD UPDATE ===
From: iOS agent
To: Backend agent, Data agent (via human)
Type: FYI
Phase: 0
Summary: The Gummi puppet is now 3D RealityKit from the start (D-25 changed, DECIDED by the iOS Lead); nothing changes in the contract or for your work.
Details: D-25 now reads "3D RealityKit puppet from the start, behind the PuppetRenderer protocol so a simpler fallback stays possible." It replaces "2D first, 3D upgrade". Updated puppet lines in ios/CLAUDE.md, docs/PROJECT_OVERVIEW.md (sections 4, 7, 12) and README_START_HERE.md. CONTRACT.md section 9 (moods, priority) is unchanged, so the "mood" live event, State.mood, and StoryCard.mood stay exactly as they are. The Settings "puppet 2D or 3D" toggle becomes a fallback toggle that only appears if a fallback renderer ships. Also recorded: D-10 (iPhone 17 Pro on iOS 26.6.2, Xcode 26.4, minimum target iOS 18.0) and D-13 (bundle ID com.mahilmanoharan.gummi, free Personal Team).
Action needed from you: none
Blocks me until: not blocking
Proof: git diff on ios/work (docs/DECISIONS.md D-10, D-13, D-25; ios/CLAUDE.md; docs/PROJECT_OVERVIEW.md; README_START_HERE.md)
===================
