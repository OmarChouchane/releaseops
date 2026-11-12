# Bad-release demo and rollback

What `./run.sh demo` does and how recovery works.

`./run.sh demo` (repeatable; a second run is safe):

1. Records the last known-good Git revision, creates a **canary user**, notes the MySQL pod UID.
2. *(Drift)* `kubectl scale` the Deployment → Argo CD detects `OutOfSync` and **self-heals** it.
3. Commits an **invalid release** to Git: a typo in the database host (`DEMO_SCENARIO=bad-image` uses a non-existent digest instead). The bad commit also sets `progressDeadlineSeconds: 60` so Kubernetes reports the failure quickly (the normal default is 180 s, which a legitimate first boot needs).
4. Argo CD syncs it. `verify` must **fail**; if it ever passed, the demo aborts (no faked failure). It then waits (bounded) for the Prometheus alert `ReleaseOpsRolloutStuck` to actually **fire**.
5. Shows real diagnostics. A background probe (`GET /user?id=1`, 2 req/s) runs from before the bad commit until recovery is verified, proving the **old pods kept serving** (`maxUnavailable: 0`).
6. **`git revert`** of the bad commit, pushed to the same source.
7. Argo CD reconciles back; `verify` passes again.
8. Proves data survival: the canary is still readable and the MySQL pod was never restarted.

An `EXIT` trap reverts the bad commit if the script is interrupted, so the cluster is not left on the bad revision.
MySQL and its volume are never touched. Evidence: `reports/out/demo-result.json` and the release report.

**Argo CD does not roll back by itself.** It applies what Git says. This design makes a bad release *contained*
(rolling update with `maxUnavailable: 0` and a progress deadline), *detected* (verification) and *recoverable* (Git revert).
