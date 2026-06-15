<img width="1920" height="1080" alt="截屏2026-06-15 17 22 03" src="https://github.com/user-attachments/assets/0fa59f1c-7c2b-440e-b41d-fcb03529dc01" />
# Menu Calendar

Author: deemsd

Menu Calendar is a small macOS menu bar calendar made for Obsidian daily notes. It shows the tasks from your Daily Notes, lets you add, edit, delete, and check off tasks directly from the menu bar, then writes everything back to your Markdown files.

Menu Calendar 是一个给 Obsidian 每日笔记用的 macOS 状态栏小日历。点开状态栏就能看到每日任务，也可以直接新增、编辑、删除、勾选完成，所有改动都会同步回你的 Markdown 文件。

## Features / 功能

- Read tasks from Obsidian Daily Notes.
- Scan extra task sources, including nested year/month folders.
- Support dated tasks like `📅 2026-06-12`.
- Support recurring tasks like `🔁 every 170 days`.
- Add a task inline from the selected day.
- Right-click a task to edit or delete it.
- Check off a task and append `✅ yyyy-MM-dd`.
- Copy all tasks of the selected day as plain text.
- Optional launch at login.
- Custom accent color in settings.

---

- 读取 Obsidian 每日笔记任务。
- 支持额外任务来源，也支持年份、月份等多级子文件夹。
- 支持 `📅 2026-06-12` 这类指定日期任务。
- 支持 `🔁 every 170 days` 这类循环任务。
- 可以在选中日期下直接新增任务。
- 右键任务可以编辑或删除。
- 勾选完成后自动追加 `✅ yyyy-MM-dd`。
- 可以一键复制当天任务文本。
- 支持开机启动。
- 可以在设置里自定义强调色。

## Install / 安装

Download `MenuCalendar.dmg`, open it, then drag `Menu Calendar.app` to Applications.

下载 `MenuCalendar.dmg`，打开后把 `Menu Calendar.app` 拖到“应用程序”即可。

Because this is an unsigned personal build, macOS may show a security warning the first time you open it. If that happens, right-click the app and choose Open.

因为这是个人构建版本，没有 Apple 开发者签名，第一次打开时 macOS 可能会提示安全风险。如果遇到这个提示，请右键 App，选择“打开”。

## Build / 本地构建

```bash
cd /Users/zhenglipei/Documents/PPT制作/ObsidianMenuCalendar
./scripts/build_app.sh
open "build/Menu Calendar.app"
```

Run the core read/write self-test:

```bash
cd /Users/zhenglipei/Documents/PPT制作/ObsidianMenuCalendar
./scripts/build_app.sh
build/MenuCalendar --self-test
```

## Notes / 说明

Menu Calendar works directly with local Markdown files. It does not send your notes to any server.

Menu Calendar 直接读写本地 Markdown 文件，不会把你的笔记上传到任何服务器。
