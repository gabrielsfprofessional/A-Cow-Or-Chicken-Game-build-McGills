# Setup (Windows, about 45 minutes, once)

Do every step in order. Each step ends with a **Check**. Stuck? Send a screenshot to the family chat.

You need: a Windows 10 or 11 PC, a Claude Pro plan ($20/month) and a free GitHub account.

## 1. GitHub account and invite
1. Sign up or sign in at https://github.com.
2. Send Gabe your GitHub username.
3. Open the invite email from GitHub and click **View invitation**, then **Accept invitation**.

**Check:** https://github.com/gabrielsfprofessional/A-Cow-Or-Chicken-Game-build-McGills opens and shows files.

## 2. Install Git for Windows
1. Click **Start**, type `PowerShell`, open **Windows PowerShell**.
2. Paste this and press **Enter** (click **Yes** if Windows asks for permission):
   ```powershell
   winget install --id Git.Git -e --source winget
   ```
3. Close PowerShell.

**Check:** open a new PowerShell and run `git --version`. It prints `git version 2...`.

## 3. Install GitHub Desktop
1. In PowerShell:
   ```powershell
   winget install --id GitHub.GitHubDesktop -e --source winget
   ```
2. Open **GitHub Desktop** from the Start menu, click **Sign in to GitHub.com** and finish in the browser.

**Check:** GitHub Desktop shows your account under **File > Options > Accounts**.

## 4. Install the GitHub CLI and sign in
1. In PowerShell:
   ```powershell
   winget install --id GitHub.cli -e --source winget
   ```
2. Close PowerShell, open a new one, run:
   ```powershell
   gh auth login
   ```
3. Answer: **GitHub.com**, then **HTTPS**, then **Yes** (authenticate Git), then **Login with a web browser**.
4. Copy the 8-character code, press **Enter**, paste the code in the browser, click **Authorize**.

**Check:** `gh auth status` says `Logged in to github.com`.

## 5. Install Godot 4.7.2 (this exact version)
1. Download: https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip
2. Create the folder `C:\Godot`.
3. Right-click the downloaded zip > **Extract All...** > type `C:\Godot` > **Extract**.
4. `C:\Godot` now holds exactly these two files:
   - `Godot_v4.7.2-stable_win64.exe`: the editor. You double-click this one.
   - `Godot_v4.7.2-stable_win64_console.exe`: Claude Code uses this one for tests.

**Check:** in PowerShell run
```powershell
& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --version
```
It prints `4.7.2.stable.official...`.

Never install another Godot version for this game. Godot 4.8 will come out during the project; ignore it until Gabe says otherwise.

## 6. Clone the game (not Download ZIP)
1. GitHub Desktop > **File > Clone repository... >** the **URL** tab.
2. Paste: `https://github.com/gabrielsfprofessional/A-Cow-Or-Chicken-Game-build-McGills`
3. Keep the local path `C:\Users\<you>\Documents\GitHub\A-Cow-Or-Chicken-Game-build-McGills` and click **Clone**.

**Check:** GitHub Desktop shows **Current branch: main** and **No local changes**.

## 7. Open the game in Godot
1. Double-click `C:\Godot\Godot_v4.7.2-stable_win64.exe`. If Windows says "Windows protected your PC", click **More info > Run anyway**.
2. In the Project Manager click **Import**, browse to the cloned folder, select `project.godot`, then confirm the import (**Import** or **Import & Edit**).
3. Wait for the first import (1-2 minutes).
4. Press **F5**. A dark screen titled "A Cow or Chicken" with a version number appears. Close it.

**Check:** the menu appeared and the **Output** panel at the bottom shows no red errors.
If Godot offers to convert or upgrade the project, click **Cancel** and tell Gabe: your Godot version is wrong.

## 8. Install Claude and open the game in the Code tab
1. Download the Claude desktop app for Windows from https://claude.com/download, install it, open it from the Start menu and sign in with your Claude Pro account.
2. Click the **Code** tab at the top center. If it asks for Git for Windows, finish step 2, then restart the app.
3. Choose **Local**, click **Select folder**, pick `Documents\GitHub\A-Cow-Or-Chicken-Game-build-McGills`.
4. Model: pick **Sonnet** in the dropdown next to the send button. Use Opus only for hard bugs.
5. Permission mode: **Manual** for your first session (you approve each change). Switch to **Accept edits** once you're comfortable.

**Check:** type `Which folder are you working in?` and send. Claude names the game folder.

You're ready. Go back to the README and paste your Prompt 1.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `winget` is not recognized | Update **App Installer** in the Microsoft Store, or install from the websites: git-scm.com, desktop.github.com, cli.github.com |
| `git` or `gh` not recognized right after installing | Close and reopen PowerShell or the Claude app |
| Push fails with "permission denied" or "403" | You haven't accepted Gabe's GitHub invite (step 1) |
| Godot says the project is from another version | You opened the wrong Godot. Use `C:\Godot\Godot_v4.7.2-stable_win64.exe` |
| The Code tab asks you to upgrade | Claude Code needs the Pro plan |
| Claude says you hit your usage limit | Stop and come back later; limits reset on a rolling 5-hour window. Check Settings > Usage on claude.ai |
| Claude can't run the smoke test | Make sure step 5's Check works, then tell Claude the exact Godot path |
