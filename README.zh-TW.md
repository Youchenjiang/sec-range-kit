# sec-range-kit

[Read in English](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)](https://www.python.org/downloads/)

> 給靶場演練與 DFIR 競賽共用的實戰工具包，是 [sec-compendium](https://github.com/Youchenjiang/sec-compendium) 的姊妹專案：
>
> - **sec-compendium**：📚 教材（課程、讀書會、playbooks、試卷）
> - **sec-range-kit**：🛠️ 比賽當天 clone 下來就能用、經過實戰驗證的工具

## 目前狀態

初始骨架。工具正從 sec-compendium 搬過來，第一批是 HITCON 2026 靶場的工具鏈。

## 規劃中的目錄

```text
sec-range-kit/
├── rangekit/        # Python 套件（pip install -e ".[dfir]"）
│   ├── common/      # 共用的路徑安全檢查
│   ├── dfir/        # 證據解析與查詢（E01、ESE、AD1、auditd）
│   ├── vm/          # 分析 VM 操作（vmrun guest ops、建置／清理腳本）
│   ├── collab/      # 團隊多 session 協作通訊
│   └── mcp/         # MCP bridge 與伺服器註冊表
├── skills/      # Agent skills（附上游來源與授權清單）
├── playbooks/   # 可重用的作戰範本（分工 SOP、逐日決策卡）
├── docs/        # ADR 與每場比賽的回顧
├── tools/       # 倉庫治理（commit lint、PR 工具、release 檢查）
└── tests/
```

## 工具包怎麼演進

每場比賽都讓工具包變強，而不是每場複製一份。

1. **賽前**：clone 本倉庫，從 `main` 開 `event/<年份>-<比賽名>` 分支（例如 `event/2026-hitcon`）。比賽分支推送時不需要 PR 說明，commit lint 和測試照跑。
2. **賽中**：在比賽分支上自由修改。案例、證據、筆記一律放在**倉庫外**，用環境變數讓工具指過去（工具搬進來後會附 `.env.example`）。
3. **賽後**：只把可重用的改進開 PR 合回 `main`（修 bug、新工具、更好的範本）；只對該場有效的臨時改法留在分支。
4. **發版**：合併後在 `main` 打 tag，例如 `v2026-hitcon`，並在 `docs/retros/` 寫一份回顧。

比賽中值得教的內容，整理成教材放到 sec-compendium。

## 基本規則

- 不寫死主機名、帳號或絕對路徑；與機器相關的設定一律來自環境變數或 git-ignored 設定檔。
- 不把比賽證據、參賽者資料或憑證放進倉庫。
- 匯入的第三方 skills 在來源清單中保留上游授權與 commit。

## 開發

```bash
python scripts/install-hooks.py            # 安裝 commit-msg 與 pre-push hook
python -m unittest discover -s tests       # 執行測試
```

Commit 遵循 Conventional Commits；完整規則與允許的 scope 見 [AGENTS.md](AGENTS.md)。

## 授權

[MIT](LICENSE)。匯入的 skills 保留各自的上游授權。
