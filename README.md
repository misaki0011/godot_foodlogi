# Fresh Routes

## Play on a phone with GitHub Pages

The `Web build and Pages deployment` workflow exports the Godot project and
publishes it whenever any branch is pushed. All branches share one Pages URL,
so the most recently pushed branch is the version available to test.

One-time GitHub setup:

1. Open the repository on GitHub.
2. Go to **Settings > Pages**.
3. Under **Build and deployment**, set **Source** to **GitHub Actions**.
4. Push a branch, or run the workflow manually from the
   repository's **Actions** tab.
5. After the workflow succeeds, open
   `https://misaki0011.github.io/godot_foodlogi/` on the phone.

For best results, use the phone in landscape orientation. The web build needs a
browser with WebGL 2.0 support.

## Review a Web build before merging

Every branch push runs the **Build web game** check, attaches a
`web-build-<commit>` artifact, and deploys that build to the shared Pages URL.
If another branch is pushed while a deployment is running, the older workflow
is canceled so it cannot overwrite the newer build.

Make the build mandatory in GitHub:

1. Open **Settings > Rules > Rulesets** and create a branch ruleset for `main`.
2. Enable **Require a pull request before merging**.
3. Enable **Require status checks to pass** and select **Build web game**.
4. Save and activate the ruleset.

The status check may not appear in the selector until it has run once. In that
case, push a feature branch, wait for its workflow to finish, and then add the
check to the ruleset.

Before merging, push the latest feature commit, wait for the deployment to
succeed, and test the shared Pages URL. Merging into `main` triggers another
deployment, so the URL returns to the merged `main` version. Do not use the URL
to review one branch while another branch is being pushed.
