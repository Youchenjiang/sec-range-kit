# 讓 Claude Code 直接使用 IDA Pro 與 Burp（MCP）

目標：解 reverse／pwn 時 Claude Code 能讀 IDA 的反編譯結果，解 web 時能讀 Burp 的請求紀錄、經 Burp 送請求。
**今晚接通並測過才算數；比賽中接不起來就不要硬修，改回「你操作 GUI、把結果貼給 Claude Code」。**

## 一、IDA Pro MCP（mrexodia/ida-pro-mcp）

需求（官方 README）：IDA Pro **8.3 以上**（建議 9），**IDA Free 不支援**；IDA 使用的 Python 需 **3.11 以上**（用 IDA 附的 `idapyswitch` 切換）。

1. 安裝 IDA 端插件（用 IDA 所用的那個 Python 的 pip）：

   ```powershell
   pip install https://github.com/mrexodia/ida-pro-mcp/archive/refs/heads/main.zip
   ```

   ```powershell
   ida-pro-mcp --install
   ```

   完成後**完全關閉再重開 IDA**。

2. 讓 Claude Code 認得它（官方給 Claude Code 的方式）：

   ```powershell
   claude plugin marketplace add mrexodia/claude-marketplace
   ```

   ```powershell
   claude plugin install ida-pro-mcp@mrexodia
   ```

3. 驗證：在 IDA 開一個執行檔、等分析完成並啟動插件（啟動方式以官方 README 為準，README 未寫明選單位置），再到 `Sec` 啟動 `claude`，請它「列出這個 binary 的函式並反編譯 main」。

備註：作者在 README 建議改用 Hex-Rays 官方的 IDA MCP（https://github.com/HexRaysSA/ida-mcp），且 GUI 插件日後會淘汰。上面的方式接不起來時再試官方版，或改用 headless（`idalib-mcp`，需 IDA 9 的 idalib）。

## 二、Burp MCP（PortSwigger 官方 mcp-server）

1. 取得擴充套件，二選一：
   - Burp 的 **Extensions → BApp Store** 搜尋「MCP Server」，有就直接安裝（README 未說明是否已上架）。
   - 自己編譯（需要 Java；`ctf_windows_gui.ps1` 已裝 Temurin 21）：

     ```powershell
     git clone https://github.com/PortSwigger/mcp-server $env:USERPROFILE\ctf-tools\burp-mcp
     ```

     ```powershell
     cd $env:USERPROFILE\ctf-tools\burp-mcp; .\gradlew.bat embedProxyJar
     ```

     在 Burp 的 **Extensions → Add**，Extension type 選 **Java**，選 `build\libs\burp-mcp-all.jar`。
2. Burp 出現 **MCP** 分頁：勾 **Enabled**。保留「送請求前詢問」的預設；**不要**開「Enable tools that can edit your config」。
3. 預設監聽 `http://127.0.0.1:9876`（`/mcp`）。`Sec\.mcp.json` 已寫好這個位址，名稱 `burp`。
4. 驗證：在 `Sec` 啟動 `claude`，第一次會詢問是否允許專案的 MCP server（選允許），再執行：

   ```powershell
   claude mcp list
   ```

   `burp` 顯示已連線後，請它「列出 Burp proxy history 最近 5 筆」。

README 未說明 Burp **Community** 版能否使用；用 Community 的話今晚務必實測。

## 三、今晚驗收

- [ ] `claude mcp list` 看得到 `burp`（已連線）與 IDA 的 MCP。
- [ ] Claude Code 能反編譯 IDA 裡開著的 binary 的 `main`。
- [ ] Claude Code 能讀 Burp proxy history；要它送一個請求時，Burp 會跳出確認。
- [ ] 任一項失敗：記下來，比賽時直接用 GUI，不要在比賽中修。
