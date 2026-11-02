# Client releases

Push the commit and its version tag together with `git push --atomic origin main vX.Y.Z`.
The tag must match the version in pubspec.yaml. The branch workflow detects the release
tag on the same commit and leaves quality verification to the release workflow.
Ordinary main pushes and pull requests still run checks. If a tag is pushed later,
its checks run again to verify that release; this deliberately favors correctness.

A release runs analysis, formatting and tests once, then builds Android and Windows
in parallel. Both packages must pass before publishing; checksums use the downloaded
asset basenames. Flutter caches are enabled, and Android also caches Gradle dependencies.
The test step is limited to five minutes, ordinary tests to 60 seconds and the
server selection widget tests explicitly to 60 seconds.

Linux, macOS and unsigned iOS builds are optional. After the main release is published,
select its tag in Multi-Platform Build / Run workflow, disable Android and Windows,
and enable the desired optional platforms. For example:

```sh
gh workflow run build.yml --ref vX.Y.Z -f build_android=false -f build_windows=false -f build_linux=true
```

Successful optional packages are added to the existing release with separate
SHA256SUMS-platform.txt files; they never replace the Android/Windows checksum list.
For unsigned iOS packages, signing is required before installation.
A manual run on a branch produces Actions artifacts without publishing a release.

On failure, inspect the failed step log and use Re-run failed jobs to preserve
successful build results and their artifacts. Re-run promptly while artifacts
remain available (14 days); after expiry, run all jobs again. Fixes require a new
commit and release tag rather than rerunning unchanged failing code.
