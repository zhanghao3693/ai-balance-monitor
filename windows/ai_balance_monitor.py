#!/usr/bin/env python3
"""
AI Balance Monitor — Cross-Platform System Tray Tool
Monitors DeepSeek, Kimi, Zhipu, MiniMax, LongCat API key balances.

macOS: Uses rumps (or falls back to pystray)
Windows/Linux: Uses pystray

Usage:
    python ai_balance_monitor.py
"""

import json
import os
import sys
import time
import threading
from datetime import datetime, date
from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

# ─── Configuration ───────────────────────────────────────────────────────────

APP_NAME = "AI Balance Monitor"
CONFIG_DIR = Path.home() / ".ai_balance_monitor"
CONFIG_FILE = CONFIG_DIR / "config.json"
HISTORY_FILE = CONFIG_DIR / "history.json"
REFRESH_INTERVAL = 300  # 5 minutes

PLATFORMS = {
    "deepseek": {
        "name": "DeepSeek",
        "balance_url": "https://api.deepseek.com/user/balance",
        "web_url": "https://platform.deepseek.com/usage",
        "color": "#4F6BED",
        "badge": "DS",
    },
    "kimi": {
        "name": "Kimi",
        "balance_url": "https://api.moonshot.cn/v1/users/me/balance",
        "web_url": "https://platform.moonshot.cn/console",
        "color": "#F07B3F",
        "badge": "KM",
    },
    "zhipu": {
        "name": "Zhipu AI",
        "balance_url": None,  # No public API
        "web_url": "https://open.bigmodel.cn/overview",
        "color": "#9B59B6",
        "badge": "ZP",
    },
    "minimax": {
        "name": "MiniMax",
        "balance_url": None,  # No public API for pay-as-you-go
        "web_url": "https://platform.minimaxi.com/user-center/payment/balance",
        "color": "#F5A623",
        "badge": "MM",
    },
    "longcat": {
        "name": "LongCat",
        "balance_url": None,  # No public API (free beta)
        "web_url": "https://longcat.chat/platform/",
        "color": "#00BCD4",
        "badge": "LC",
    },
}


# ─── Data Models ──────────────────────────────────────────────────────────────

class UnifiedBalance:
    def __init__(self, is_available, cny_total, cny_granted, cny_topped_up,
                 usd_total=0, raw=""):
        self.is_available = is_available
        self.cny_total = cny_total
        self.cny_granted = cny_granted
        self.cny_topped_up = cny_topped_up
        self.usd_total = usd_total
        self.raw = raw


# ─── Config Management ────────────────────────────────────────────────────────

def load_config():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                cfg = json.load(f)
            return cfg
        except (json.JSONDecodeError, KeyError):
            pass

    # Default empty config
    return {"keys": [], "active": ""}


def save_config(cfg):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def get_active_key(cfg):
    for k in cfg.get("keys", []):
        if k.get("name") == cfg.get("active"):
            return k
    return cfg.get("keys", [{}])[0] if cfg.get("keys") else None


def get_platform(key_entry):
    plat = (key_entry or {}).get("platform", "deepseek")
    return PLATFORMS.get(plat, PLATFORMS["deepseek"])


# ─── History Management ───────────────────────────────────────────────────────

def load_history():
    if HISTORY_FILE.exists():
        try:
            with open(HISTORY_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError:
            pass
    return []


def save_history(records):
    with open(HISTORY_FILE, 'w', encoding='utf-8') as f:
        json.dump(records, f, ensure_ascii=False, indent=2)


def update_history(cny_total):
    records = load_history()
    today = date.today().isoformat()

    found = False
    for r in records:
        if r.get("date") == today:
            r["end_balance"] = cny_total
            found = True
            break
    if not found:
        records.append({
            "date": today,
            "start_balance": cny_total,
            "end_balance": cny_total,
        })

    # Keep last 60 days
    records = records[-60:]
    save_history(records)


# ─── API Calls ────────────────────────────────────────────────────────────────

def fetch_deepseek_balance(api_key):
    """Fetch DeepSeek balance."""
    req = Request(
        "https://api.deepseek.com/user/balance",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode(errors='replace')
        try:
            err = json.loads(body)
            msg = err.get("error", {}).get("message", body)
        except json.JSONDecodeError:
            msg = body or f"HTTP {e.code}"
        return None, msg
    except URLError as e:
        return None, str(e.reason)

    infos = data.get("balance_infos", [])
    cny = next((i for i in infos if i.get("currency") == "CNY"), None)
    usd = next((i for i in infos if i.get("currency") == "USD"), None)

    return UnifiedBalance(
        is_available=data.get("is_available", False),
        cny_total=float(cny.get("total_balance", 0) or 0) if cny else 0,
        cny_granted=float(cny.get("granted_balance", 0) or 0) if cny else 0,
        cny_topped_up=float(cny.get("topped_up_balance", 0) or 0) if cny else 0,
        usd_total=float(usd.get("total_balance", 0) or 0) if usd else 0,
        raw=json.dumps(data, ensure_ascii=False),
    ), None


def fetch_kimi_balance(api_key):
    """Fetch Kimi (Moonshot) balance."""
    req = Request(
        "https://api.moonshot.cn/v1/users/me/balance",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode(errors='replace')
        return None, body or f"HTTP {e.code}"
    except URLError as e:
        return None, str(e.reason)

    if data.get("code") != 0:
        return None, f"API Error (code={data.get('code')})"

    d = data.get("data", {})
    available = float(d.get("available_balance", 0) or 0)
    voucher = float(d.get("voucher_balance", 0) or 0)
    cash = float(d.get("cash_balance", 0) or 0)

    return UnifiedBalance(
        is_available=available > 0,
        cny_total=available,
        cny_granted=voucher,
        cny_topped_up=cash,
        raw=json.dumps(data, ensure_ascii=False),
    ), None


def fetch_balance(key_entry):
    """Fetch balance for the active key. Returns (UnifiedBalance | None, error_msg | None, unsupported_platform | None)."""
    if not key_entry:
        return None, "No API key configured", None

    plat_info = get_platform(key_entry)

    if plat_info["balance_url"] is None:
        return None, None, plat_info["name"]

    api_key = key_entry.get("key", "")
    platform = key_entry.get("platform", "deepseek")

    if platform == "deepseek":
        return fetch_deepseek_balance(api_key) + (None,)
    elif platform == "kimi":
        return fetch_kimi_balance(api_key) + (None,)
    else:
        return None, f"Unknown platform: {platform}", None


# ─── Icon Rendering ──────────────────────────────────────────────────────────

def create_tray_icon(balance_text, status="normal", platform_color="#4F6BED"):
    """Create a tray icon image with balance text."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return None

    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background circle
    margin = 4
    if status == "error":
        bg = "#E74C3C"
    elif status == "unsupported":
        bg = "#95A5A6"
    elif status == "warning":
        bg = "#F39C12"
    else:
        bg = platform_color

    draw.ellipse([margin, margin, size - margin, size - margin], fill=bg)

    # Balance text
    if balance_text:
        try:
            font_size = 18 if len(balance_text) <= 6 else 14
            font = ImageFont.truetype("arial.ttf", font_size)
        except Exception:
            try:
                font = ImageFont.load_default()
            except Exception:
                font = None

        if font:
            bbox = draw.textbbox((0, 0), balance_text, font=font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            x = (size - tw) // 2
            y = (size - th) // 2
            # Draw shadow
            draw.text((x + 1, y + 1), balance_text, fill="#00000044", font=font)
            draw.text((x, y), balance_text, fill="#FFFFFF", font=font)

    return img


# ─── System Tray App ─────────────────────────────────────────────────────────

class BalanceTrayApp:
    """Cross-platform system tray monitor for AI API balances."""

    def __init__(self):
        self.config = load_config()
        self.balance = None
        self.error_msg = None
        self.unsupported_platform = None
        self.last_refresh = ""
        self.running = True
        self.icon = None
        self.tray_thread = None

    # ─── CLI Menu (for headless/terminal mode) ────────────────────────────────

    def _print_menu(self):
        """Print text-based menu (used when GUI tray is unavailable)."""
        key = get_active_key(self.config)
        plat = get_platform(key)

        print(f"\n{'='*50}")
        print(f"  {APP_NAME}")
        print(f"{'='*50}")
        print(f"  Key: {self.config.get('active', 'N/A')}  [{plat['name']}]")
        print(f"  Last refresh: {self.last_refresh}")

        if self.unsupported_platform:
            print(f"  ⚠️  {self.unsupported_platform} has no public balance API")
            print(f"  → Web console: {plat['web_url']}")
        elif self.error_msg:
            print(f"  ❌ Error: {self.error_msg}")
        elif self.balance:
            print(f"  Status: {'✅ OK' if self.balance.is_available else '⚠️ LOW'}")
            if self.balance.cny_total > 0:
                print(f"  CNY Total:   ¥{self.balance.cny_total:.2f}")
                if self.balance.cny_granted > 0:
                    print(f"    Grant:     ¥{self.balance.cny_granted:.2f}")
                if self.balance.cny_topped_up > 0:
                    print(f"    Top-up:    ¥{self.balance.cny_topped_up:.2f}")
            if self.balance.usd_total > 0:
                print(f"  USD Total:   ${self.balance.usd_total:.2f}")
        else:
            print("  Loading...")

        print(f"\n  Actions: r=refresh, s=switch key, q=quit")
        print(f"{'='*50}")

    def _cli_loop(self):
        """Simple CLI loop for platforms without system tray support."""
        self.refresh()

        import threading
        stop_event = threading.Event()

        def auto_refresh():
            while not stop_event.is_set():
                stop_event.wait(REFRESH_INTERVAL)
                if not stop_event.is_set():
                    self.refresh()

        refresh_thread = threading.Thread(target=auto_refresh, daemon=True)
        refresh_thread.start()

        try:
            while self.running:
                self._print_menu()
                try:
                    cmd = input("\n> ").strip().lower()
                except (EOFError, KeyboardInterrupt):
                    break

                if cmd in ('q', 'quit', 'exit'):
                    break
                elif cmd in ('r', 'refresh'):
                    self.refresh()
                elif cmd in ('s', 'switch'):
                    self._cli_switch_key()
        finally:
            stop_event.set()
            print("\nGoodbye.")

    def _cli_switch_key(self):
        keys = self.config.get("keys", [])
        if not keys:
            print("No keys configured. Please add keys to config.json")
            return

        print("\nAvailable keys:")
        for i, k in enumerate(keys):
            plat = PLATFORMS.get(k.get("platform", "deepseek"), {})
            active_mark = " ← active" if k["name"] == self.config.get("active") else ""
            masked = k["key"][:4] + "****" + k["key"][-4:] if len(k["key"]) > 8 else "****"
            print(f"  {i+1}. [{plat.get('badge', '??')}] {k['name']}: {masked}{active_mark}")

        try:
            choice = int(input("\nSelect key number: ")) - 1
            if 0 <= choice < len(keys):
                self.config["active"] = keys[choice]["name"]
                save_config(self.config)
                self.refresh()
        except (ValueError, IndexError):
            print("Invalid selection")

    # ─── GUI Tray (pystray) ──────────────────────────────────────────────────

    def _setup_tray(self):
        """Initialize pystray system tray icon."""
        try:
            import pystray
        except ImportError:
            print("pystray not installed. Run: pip install pystray pillow")
            print("Falling back to CLI mode...")
            self._cli_loop()
            return

        # Initial icon
        icon_img = create_tray_icon("⌛", status="loading")
        if icon_img is None:
            print("PIL not available. Run: pip install pillow")
            self._cli_loop()
            return

        self.icon = pystray.Icon(
            APP_NAME,
            icon_img,
            title=APP_NAME,
        )

        # Build initial menu
        self.icon.menu = self._build_menu()

        # Run tray in a separate thread
        self.tray_thread = threading.Thread(target=self._run_tray, daemon=True)
        self.tray_thread.start()

        # Do initial refresh
        self.refresh()

        # Auto-refresh loop
        while self.running:
            time.sleep(REFRESH_INTERVAL)
            self.refresh()

    def _run_tray(self):
        """Run pystray event loop."""
        try:
            self.icon.run()
        except Exception as e:
            print(f"Tray error: {e}")

    def _build_menu(self):
        """Build pystray menu dynamically."""
        try:
            import pystray
        except ImportError:
            return None

        key = get_active_key(self.config)
        plat = get_platform(key)
        menu_items = []

        # Header
        active_name = self.config.get("active", "N/A")
        menu_items.append(
            pystray.MenuItem(f"🔑 Key: {active_name} [{plat['badge']}]", None, enabled=False)
        )

        # Platform unsupported
        if self.unsupported_platform:
            menu_items.append(pystray.Menu.SEPARATOR)
            menu_items.append(
                pystray.MenuItem(
                    f"⚠️ {self.unsupported_platform} — No balance API",
                    None,
                    enabled=False,
                )
            )
            menu_items.append(
                pystray.MenuItem(
                    f"Open {self.unsupported_platform} Console →",
                    lambda: self._open_url(plat["web_url"]),
                )
            )
        elif self.error_msg:
            menu_items.append(pystray.Menu.SEPARATOR)
            menu_items.append(
                pystray.MenuItem(f"❌ {self.error_msg[:40]}", None, enabled=False)
            )
        elif self.balance:
            menu_items.append(pystray.Menu.SEPARATOR)
            status = "✅ OK" if self.balance.is_available else "⚠️ LOW"
            menu_items.append(
                pystray.MenuItem(f"Status: {status}", None, enabled=False)
            )
            if self.balance.cny_total > 0:
                menu_items.append(
                    pystray.MenuItem(
                        f"CNY: ¥{self.balance.cny_total:.2f}", None, enabled=False
                    )
                )
                if self.balance.cny_granted > 0:
                    menu_items.append(
                        pystray.MenuItem(
                            f"  Grant: ¥{self.balance.cny_granted:.2f}",
                            None,
                            enabled=False,
                        )
                    )
                if self.balance.cny_topped_up > 0:
                    menu_items.append(
                        pystray.MenuItem(
                            f"  Top-up: ¥{self.balance.cny_topped_up:.2f}",
                            None,
                            enabled=False,
                        )
                    )
            if self.balance.usd_total > 0:
                menu_items.append(
                    pystray.MenuItem(
                        f"USD: ${self.balance.usd_total:.2f}", None, enabled=False
                    )
                )

        # Last refresh
        menu_items.append(pystray.Menu.SEPARATOR)
        menu_items.append(
            pystray.MenuItem(f"Last: {self.last_refresh}" if self.last_refresh else "Refreshing...",
                             None, enabled=False)
        )

        # Key switcher submenu
        keys = self.config.get("keys", [])
        if len(keys) > 1:
            key_items = []
            for k in keys:
                p = PLATFORMS.get(k.get("platform", "deepseek"), {})
                label = f"[{p.get('badge', '??')}] {k['name']}"
                if k["name"] == self.config.get("active"):
                    label += " ✓"

                def make_switch(name):
                    return lambda: self._switch_key(name)

                key_items.append(
                    pystray.MenuItem(label, make_switch(k["name"]))
                )
            menu_items.append(pystray.Menu.SEPARATOR)
            menu_items.append(
                pystray.MenuItem("🔀 Switch Key", pystray.Menu(*key_items))
            )

        # Actions
        menu_items.append(pystray.Menu.SEPARATOR)
        menu_items.append(
            pystray.MenuItem("🔄 Refresh", self.refresh)
        )
        menu_items.append(
            pystray.MenuItem(f"🌐 Open {plat['name']} Console",
                             lambda: self._open_url(plat["web_url"]))
        )
        menu_items.append(
            pystray.MenuItem("⚙️ Manage Keys", self._open_config)
        )
        menu_items.append(pystray.Menu.SEPARATOR)
        menu_items.append(
            pystray.MenuItem("Quit", self.quit)
        )

        return pystray.Menu(*menu_items)

    def _switch_key(self, name):
        self.config["active"] = name
        save_config(self.config)
        self.refresh()

    def _open_url(self, url):
        import webbrowser
        webbrowser.open(url)

    def _open_config(self):
        """Open config file with default editor."""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        if not CONFIG_FILE.exists():
            # Create example config
            save_config({
                "keys": [
                    {"name": "my-deepseek", "key": "sk-your-key", "platform": "deepseek"},
                    {"name": "my-kimi", "key": "sk-your-key", "platform": "kimi"},
                ],
                "active": "my-deepseek",
            })

        if sys.platform == "win32":
            os.startfile(str(CONFIG_FILE))
        elif sys.platform == "darwin":
            import subprocess
            subprocess.run(["open", str(CONFIG_FILE)])
        else:
            import subprocess
            subprocess.run(["xdg-open", str(CONFIG_FILE)])

    # ─── Core Logic ────────────────────────────────────────────────────────

    def refresh(self, *_):
        """Fetch balance and update menu/tooltip."""
        key = get_active_key(self.config)
        self.unsupported_platform = None
        self.error_msg = None

        if key is None:
            self.error_msg = "No API key configured"
            self.balance = None
            self._update_display()
            return

        plat = get_platform(key)
        result, err, unsupported = fetch_balance(key)

        self.balance = result
        self.error_msg = err
        self.unsupported_platform = unsupported
        self.last_refresh = datetime.now().strftime("%H:%M:%S")

        # Update history on successful fetch
        if self.balance and self.balance.cny_total > 0:
            update_history(self.balance.cny_total)

        self._update_display()

    def _update_display(self):
        """Update tray icon and menu."""
        if not self.icon:
            return

        # Update icon
        plat = get_platform(get_active_key(self.config))
        color = plat.get("color", "#4F6BED")

        if self.unsupported_platform:
            icon_img = create_tray_icon("?", status="unsupported", platform_color=color)
            self.icon.title = f"{APP_NAME} — {self.unsupported_platform} (no API)"
        elif self.error_msg or self.balance is None:
            icon_img = create_tray_icon("!", status="error", platform_color=color)
            self.icon.title = f"{APP_NAME} — Error: {self.error_msg or 'No data'}"
        elif self.balance.cny_total > 0:
            text = f"¥{self.balance.cny_total:.0f}"
            icon_img = create_tray_icon(text, status="normal", platform_color=color)
            self.icon.title = f"{APP_NAME} — ¥{self.balance.cny_total:.2f} CNY"
        elif self.balance.usd_total > 0:
            text = f"${self.balance.usd_total:.0f}"
            icon_img = create_tray_icon(text, status="normal", platform_color=color)
            self.icon.title = f"{APP_NAME} — ${self.balance.usd_total:.2f} USD"
        else:
            icon_img = create_tray_icon("¥0", status="warning", platform_color=color)
            self.icon.title = APP_NAME

        if icon_img:
            self.icon.icon = icon_img

        # Rebuild menu
        self.icon.menu = self._build_menu()
        self.icon.update_menu()

    def quit(self, *_):
        """Quit the application."""
        self.running = False
        if self.icon:
            self.icon.stop()
        sys.exit(0)

    def run(self):
        """Entry point. Try GUI tray first, fall back to CLI."""
        # Check if we can run GUI
        try:
            import pystray
            from PIL import Image
            self._setup_tray()
        except ImportError:
            print("Required packages not found. Install: pip install pystray pillow")
            self._cli_loop()
        except Exception as e:
            print(f"GUI tray failed: {e}")
            print("Falling back to CLI mode...")
            self._cli_loop()


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = BalanceTrayApp()
    app.run()
