# Guide: Installing, Updating, Disabling & Removing Extensions

This guide walks users through managing dynamic extensions in Animestream.

---

## 1. Opening Extension Settings
In Animestream, tap the **Settings** tab in the navigation bar, then select **Manage Extensions**.

---

## 2. Installing an Extension
1. Switch to the **Available in Repos** tab.
2. Find the desired source (e.g. *MangaDex* or *GogoAnime*).
3. Tap **Install**.
4. The system automatically downloads the manifest, validates API compatibility, performs a sandbox dry-run, and activates the extension.

---

## 3. Updating an Extension
- When a newer version of an extension is published to the repository, the button changes to **Update**.
- Tap **Update** to install the update.
- **Safety Rollback:** If the updated script has a syntax error or fails validation, Animestream automatically preserves and rolls back to your last known-working version so your app never breaks!

---

## 4. Enabling / Disabling an Extension
- On the **Installed** tab, toggle the switch next to any extension to disable it.
- Disabling immediately suspends background network activity and unloads its JS context from memory without deleting its files.

---

## 5. Uninstalling an Extension
- Tap the **Trash** icon next to an installed extension.
- Confirm the dialog to remove the files and release storage.

---

## 6. Adding a Custom Extension Repository
1. Tap the **Link (+)** icon in the top right of the Manage Extensions screen.
2. Paste the HTTPS URL of any community repository (e.g. `https://raw.githubusercontent.com/user/extensions/main`).
3. Tap **Add Repo**. Animestream immediately syncs the repository catalog.
