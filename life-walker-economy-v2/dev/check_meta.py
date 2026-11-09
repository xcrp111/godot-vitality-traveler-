#!/usr/bin/env python3
"""构建前检查：资源 .meta 是否安全。

背景（社区踩过的坑）：资源的 uuid 如果含 `+`，CDN 路由会把 URL 路径里的 `+` 解码成空格，
请求就打到一个不存在的对象上 —— 客户端 404，引擎启动时记一条错误，测试壳会报「启动失败」。
字面 `+` = 404，改成 `%2B` 才 200。

本脚本检查 4 件事：
  1. uuid 含 `+` / `/` / 空白等非 URL 安全字符
  2. uuid 为空或 meta 不是合法 JSON
  3. 孤儿 meta（对应的资源文件已经不存在）—— 构建会把它当成一个资源，必然 404
  4. 同一个 uuid 被多个资源复用
  5. 资源文件缺少 .meta（构建器会跳过它，线上就取不到这个资源）

用法（项目根目录下）：
    python dev/check_meta.py

退出码 0 = 干净，1 = 有问题（构建前必须先修）。
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ("scripts", "assets", ".project")
SAFE = re.compile(r"^[A-Za-z0-9_.-]+$")


def iter_meta():
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for name in filenames:
                if name.endswith(".meta"):
                    yield os.path.join(dirpath, name)


def main() -> int:
    problems = []
    seen = {}
    count = 0

    for meta in iter_meta():
        count += 1
        rel = os.path.relpath(meta, ROOT).replace("\\", "/")
        try:
            with open(meta, encoding="utf-8") as f:
                data = json.load(f)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{rel}: meta 不是合法 JSON（{exc}）")
            continue

        uuid = data.get("uuid")
        if not isinstance(uuid, str) or not uuid:
            problems.append(f"{rel}: 缺少 uuid")
        else:
            if "+" in uuid:
                problems.append(f"{rel}: uuid 含 '+'（{uuid}）—— CDN 会把它解码成空格导致 404，删掉这个 meta 让构建器重新分配")
            elif "/" in uuid:
                problems.append(f"{rel}: uuid 含 '/'（{uuid}）—— 会被当成路径分隔符导致 404，删掉这个 meta 重新分配")
            elif not SAFE.match(uuid):
                problems.append(f"{rel}: uuid 含非 URL 安全字符（{uuid}）")
            elif uuid in seen:
                problems.append(f"{rel}: uuid 与 {seen[uuid]} 重复（{uuid}）")
            else:
                seen[uuid] = rel

        target = meta[: -len(".meta")]
        if not os.path.exists(target):
            problems.append(f"{rel}: 孤儿 meta（资源文件不存在）—— 构建会生成一个必然 404 的资源条目，直接删掉这个 meta")

    # 反向检查：资源文件必须都有 .meta，否则构建器不会把它当资源
    for d in ("scripts", "assets"):
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for name in filenames:
                if name.endswith(".meta"):
                    continue
                full = os.path.join(dirpath, name)
                if not os.path.exists(full + ".meta"):
                    rel = os.path.relpath(full, ROOT).replace("\\", "/")
                    problems.append(f"{rel}: 缺少 .meta（构建器不会把它打成资源，线上取不到）")

    print(f"扫描 {count} 个 .meta")
    if problems:
        print(f"发现 {len(problems)} 个问题：")
        for p in problems:
            print("  ❌ " + p)
        print("\n修法：删掉有问题的 .meta（或对应孤儿 meta），重新构建，构建器会分配干净 uuid。")
        return 1

    print("✅ 全部通过：uuid 均为 URL 安全字符，无孤儿/重复")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
