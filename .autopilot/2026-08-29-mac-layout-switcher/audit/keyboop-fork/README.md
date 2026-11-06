# Reproducibility evidence

The directories retain result logs, source SHA256 provenance and fixture-seam
patches from owned AppKit tests. The original scratch directories also contained
compiled binaries/source copies; those generated files are deliberately not
committed here. Original SHA256SUMS may describe that larger scratch directory.
The seams replace external AX/PID/secure input and the final event-post sink,
not production Engine decisions or native TIS translation. These are not tests
of hardware input through WindowServer into a third-party editor.

Linux logs are actual SwiftPM XCTest runs, separately identified by commit.
Native core logs use the documented supplemental XCTest assertion adapter
because the available macOS Command Line Tools lack the XCTest module.
No microphone recording, private editor automation or TCC manipulation was used.
