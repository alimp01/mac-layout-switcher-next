# 0014. Next: Keyboop detection and buffered keyboard replacement

Status: accepted for experimental Next fork by explicit user request 2026-11-06.

The stable 1.4.12 repository retains ADR0013. In this separate fork, the user explicitly requests Keyboop recognition and replacement. For newly typed text tracked since a known context boundary, absence of AX is no longer a prerequisite failure: bounded Backspace/Unicode synthesis is allowed with context invalidation, secure-input checks, ordered physical events and no retry after mutation. AX remains available for selected/preexisting text and dictation. This changes the assurance from exact editor readback to best-effort event delivery where AX is unavailable. Do not label posted events as confirmed text.

Port the actual upstream mechanism with its restrictions and keep provenance/licenses. No clipboard access is added to automatic correction. Main app identity/update channel/config and installed stable app remain separate. See keyboop-fork-spec for acceptance and test boundaries.
