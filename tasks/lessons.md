# Lessons

## 2026-07-14 — Don't build requirements on unverified memory claims
A recalled memory claimed the macOS app had "paying customers", and I built a whole
data-migration requirement into the rebrand prompt on top of it. Rafa corrected me:
there are no shipped users.

**Rule:** Memories about business state (customers, revenue, what's shipped) are
point-in-time observations, often wrong or stale. Before making them a load-bearing
requirement or constraint, state the assumption explicitly to Rafa ("this assumes X
— still true?") instead of asserting it as fact. Code-level memories can be verified
by reading the repo; business-level ones can only be verified by asking.
