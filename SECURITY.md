# Security

SendIt is an offline single-player game. It has no accounts, no server, no telemetry, and makes no network requests. The only file it writes is your personal best, in Godot's per-user data folder (`best.cfg`).

If you find a security problem, please report it privately through GitHub: **Security** tab, then **Report a vulnerability**. Please don't open a public issue for it.

Release downloads are built by the [Release workflow](.github/workflows/release.yml) from this repository, and each release includes a `SHA256SUMS` file so you can verify your download.
