# AI Balance Monitor

> macOS & Windows 系统托盘 / 菜单栏 AI API 余额监控工具

实时监测 DeepSeek、Kimi、智谱 AI、MiniMax、LongCat 的 API Key 余额与用量，支持多 Key 快速切换。

<p align="center">
  <img src="icons/deepseek_icon.png" width="40" height="40" alt="DeepSeek"/>
  <img src="icons/kimi_icon.png" width="40" height="40" alt="Kimi"/>
  <img src="icons/zhipu_icon.png" width="40" height="40" alt="Zhipu"/>
  <img src="icons/minimax_icon.png" width="40" height="40" alt="MiniMax"/>
  <img src="icons/longcat_icon.png" width="40" height="40" alt="LongCat"/>
</p>

---

## 支持的平台

| 平台 | 余额 API | 状态 |
|------|---------|------|
| **DeepSeek** | `api.deepseek.com/user/balance` | ✅ 完整支持（CNY + USD） |
| **Kimi (Moonshot)** | `api.moonshot.cn/v1/users/me/balance` | ✅ 完整支持（可用余额/代金券/现金） |
| **智谱 AI (BigModel)** | 无公开接口 | ⚠️ 仅显示在线状态，需到网页控制台查看 |
| **MiniMax** | 无公开接口（按量付费账户） | ⚠️ 仅显示在线状态，需到网页控制台查看 |
| **LongCat** | 无公开接口（公测免费阶段） | ⚠️ 仅显示在线状态，需到网页控制台查看 |

> 智谱、MiniMax、LongCat 均不开放按量付费/免费账户的余额 REST API。

## 功能

- 🍔 **系统托盘/菜单栏** 实时显示余额
- 🔀 **多 Key 切换** — 支持多个 API Key 快速切换
- 📊 **今日/本月用量** — 基于余额变化推算花费
- 📅 **近 7 天消费图表** — 菜单栏内嵌迷你柱状图
- 🔄 **5 分钟自动刷新**
- ⚙️ **Key 管理面板** — 菜单内直接编辑
- 🌐 **一键跳转平台控制台**
- 🎨 **平台定制图标** — 不同平台用不同颜色标识

## 安装

### macOS

```bash
# 1. 解压
unzip ai-balance-monitor-macos.zip
cd ai-balance-monitor-macos

# 2. 运行安装脚本
chmod +x install.sh
./install.sh

# 3. 或者直接运行
open AI-Balance-Monitor.app
```

首次运行后点击菜单栏图标 → **⚙️ Manage API Keys** 添加你的 Key。

**最低要求**：macOS 10.15+

### Windows

```bash
# 1. 解压
# 右键 ai-balance-monitor-windows.zip → 解压到当前文件夹
cd ai-balance-monitor-windows

# 2. 安装依赖（需要 Python 3.8+）
双击 install.bat

# 3. 启动
python ai_balance_monitor.py
```

首次运行后右键系统托盘图标 → **⚙️ Manage Keys** 添加你的 Key。

**最低要求**：Python 3.8+

## 配置

配置文件位于：

- **macOS/Windows**: `~/.deepseek_monitor/config.json` (macOS Swift)  
  `~/.ai_balance_monitor/config.json` (Windows Python)

格式：

```json
{
  "keys": [
    {
      "name": "my-deepseek",
      "key": "sk-your-deepseek-api-key",
      "platform": "deepseek"
    },
    {
      "name": "my-kimi",
      "key": "sk-your-kimi-api-key",
      "platform": "kimi"
    },
    {
      "name": "my-zhipu",
      "key": "your-zhipu-api-key",
      "platform": "zhipu"
    },
    {
      "name": "my-minimax",
      "key": "sk-api-your-minimax-key",
      "platform": "minimax"
    }
  ],
  "active": "my-deepseek"
}
```

| 字段 | 说明 |
|------|------|
| `name` | Key 的显示名称 |
| `key` | API Key 原文 |
| `platform` | `deepseek` / `kimi` / `zhipu` / `minimax` / `longcat` |
| `active` | 当前活跃的 Key 名称 |

## 项目结构

```
ai-balance-monitor/
├── README.md
├── config.example.json          # 配置文件模板
├── icons/                       # 平台图标 (DeepSeek/Kimi/Zhipu/MiniMax)
├── macos/
│   ├── AI-Balance-Monitor.app   # macOS 原生 App (Swift + AppKit)
│   ├── deepseek_monitor.swift   # Swift 源码
│   ├── build.sh                 # 编译脚本
│   └── install.sh               # 安装脚本
└── windows/
    ├── ai_balance_monitor.py    # Windows/Linux Python 版 (pystray)
    ├── requirements.txt
    └── install.bat
```

## 从源码编译 (macOS)

```bash
cd macos
chmod +x build.sh
./build.sh
```

需要 Xcode Command Line Tools (`xcode-select --install`)。

## License

MIT

---

**Made with ❤️ for AI developers who care about their API costs.**
