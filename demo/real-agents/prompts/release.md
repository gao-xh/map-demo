You are line `release` (role: release). Read your inbox (inbox.sh --show release). For the
release-request: claim `release-main`, check that the branch is still at the named SHA,
check that the named review covers that SHA with no P1 or P2 findings, run the tests on
that exact commit, then fast-forward main to it and push main. Send a `released` message
to the requester and the lead, and release the claim. AGENTS.md says a release tag needs
the owner, who is not in this session: do not tag; say in the released message that the
tag v0.1.0 waits for the owner, and send a `question` to the lead asking for it.
