# Fresh Routes

## Play on a phone with GitHub Pages

The `Deploy web game to GitHub Pages` workflow exports the Godot project for the
web and publishes it whenever `master` or `main` is updated.

One-time GitHub setup:

1. Open the repository on GitHub.
2. Go to **Settings > Pages**.
3. Under **Build and deployment**, set **Source** to **GitHub Actions**.
4. Push these files to `master`, or run the workflow manually from the
   repository's **Actions** tab.
5. After the workflow succeeds, open
   `https://misaki0011.github.io/godot_foodlogi/` on the phone.

For best results, use the phone in landscape orientation. The web build needs a
browser with WebGL 2.0 support.
