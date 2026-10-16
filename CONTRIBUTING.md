# Contributing to Glee

Glee is maintained by **dumpydon**. Thanks for helping improve it. Small, focused changes are welcome—especially clearer setup, reliable session behavior, accessibility, and documentation.

## Report a bug

[Open an issue](https://github.com/dumpydon/glee/issues/new) with:

- Your Mac model and chip, macOS version, and Glee version.
- What you expected, what happened, and steps to reproduce it.
- A screenshot or the relevant error message.
- For power or closed-lid issues: charger state, selected mode, and any message in **Setup details**.

Remove passwords and personal information before posting. If the issue affects sleep or lid behavior, keep the lid open while collecting details.

## Make a change

1. Fork the repository and create a branch for your change.
2. Follow the [development guide](docs/DEVELOPMENT.md) to build locally.
3. Keep the change focused. For larger changes to power behavior, local installation, or the helper protocol, open an issue to discuss the approach first.
4. Run the checks relevant to your change:

   ```sh
   ./script/check.sh
   ```

5. Open a pull request describing the problem, the resulting behavior, and how you checked it. Include before/after screenshots for interface changes.

Documentation-only changes do not need an app build; check links, commands, and wording against the current source.

## Keep the project easy to maintain

- Put session and policy logic in `GleeCore`; keep platform integration in the app or helper.
- Preserve power limits, authenticated XPC, and recovery behavior. A timer running is not proof that closed-lid mode is ready.
- Use test doubles for privileged power settings. Do not install a root helper or alter the host's sleep policy in unit tests.
- Keep generated bundles, credentials, Keychain exports, and private signing material out of commits.
- Say which behavior you tested on hardware and which you checked only in code or simulations.

Contributions are made under the repository's [GNU Affero General Public License, version 3 only](LICENSE) (`AGPL-3.0-only`).
