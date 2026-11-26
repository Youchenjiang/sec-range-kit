# CTF 賽前檢查清單

適用：自備電腦、有線網路、比賽期間手機上鎖的 jeopardy 賽。逐項打勾，**每位隊員各做一次**。

## 前一晚

### 網路與電源
- [ ] USB／Type-C 轉 RJ45 網卡：插上有線網路後能上網（驅動已裝好，不要等現場才裝）。
- [ ] 充電器、電源轉接頭、延長線（主辦方只提供插座）。
- [ ] 隊內決定 3 條網路線怎麼分；需要的話帶一台小型交換器（switch）。

### 帳號（手機上鎖後簡訊與驗證 App 都不能用）
- [ ] 比賽會用到的帳號全部先登入，並勾選「信任此裝置」：比賽系統、Claude、GitHub、Google、雲端 VM。
- [ ] 每個帳號的**備援碼**存在電腦裡或印出來。
- [ ] 每台要用的電腦都先開過一次 Claude Code 並完成登入。
- [ ] 能改成不靠手機的兩步驟驗證（硬體金鑰、電腦上的密碼管理器）就先改。

### 解題環境
- [ ] Linux VM 或 WSL2：`bash rangekit/ctf/setup/ctf_setup.sh --with-wordlists --with-pwndbg`，結尾沒有 `not installed` 或只剩不需要的項目。
- [ ] Windows 主機：`powershell -NoProfile -ExecutionPolicy Bypass -File rangekit\ctf\setup\ctf_windows_gui.ps1`。
- [ ] WSL2：先 `wsl --update`；GUI 工具（Ghidra、Burp、Wireshark）在 Windows 主機上開。
- [ ] VM 裝好後**做一個快照**，壞掉時直接回復。
- [ ] 抽查工具能跑：`source ~/ctf-venv/bin/activate && python -c "import pwn, Crypto, z3"`、`gdb --version`、`vol -h`、Ghidra 能開。
- [ ] 解題目錄：`powershell -NoProfile -ExecutionPolicy Bypass -File rangekit\ctf\setup\ctf_workspace.ps1 -Workspace C:\Users\<你>\Downloads\Sec`，完成後目錄裡有 `.claude\skills\ctf-*`、`CLAUDE.md`、`cheatsheets\`、`templates\` 和各題型資料夾。
- [ ] 在解題目錄啟動 Claude Code（`cd` 到該目錄再執行 `claude`），問它「有哪些 ctf skills」確認有載入。
- [ ] 用 WSL2 解 pwn 題時，把題目檔複製到 Linux 家目錄再執行（`/mnt/c` 上的檔案權限和速度都不適合）。

### 分工
- [ ] 每個題型指定主要負責人：Reverse、Web、Pwn、Crypto、Misc、Forensic、情境題。
- [ ] 約好卡住多久要換題或求援（建議 20 分鐘）。
- [ ] 約好在哪裡同步進度（共用文件、聊天室、白板）。

## 開賽前 10 分鐘
- [ ] 每台電腦都連得上比賽系統。
- [ ] 解題環境開好、Claude Code 能回應。
- [ ] 每題一個資料夾：`~/ctf/<題型>-<題名>/`，筆記寫在裡面的 `notes.md`。

## 比賽中
- [ ] 先看完全部題目，挑分數高、解題人多的先做。
- [ ] 每題筆記記下試過的方法，交接時對方不必重來。
- [ ] 拿到 flag 先記在筆記，再提交，確認格式（大小寫、前綴）。
- [ ] 定時存檔、VM 不要關。
