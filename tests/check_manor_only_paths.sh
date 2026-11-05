#!/bin/sh
# 裁剪后的静态自检：确保没有蚂蚁森林/其它模块残留，且未硬编码未确认的家庭接口。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[check] 关键文件..."
for f in PortEntry.m antforest/AntManorManager.m antforest/AntManorIntimacy.m antforest/AntManorManager.h antforest/AntManorIntimacy.h; do
  test -f "$f" || { echo "缺少 $f"; exit 1; }
done

echo "[check] 不应残留森林管理器..."
if grep -R "AntForestManager" --include='*.m' --include='*.h' . >/dev/null 2>&1; then
  echo "仍存在 AntForestManager 引用"
  exit 1
fi

echo "[check] 不应存在森林相关接口..."
if grep -RE "com\.alipay\.antforest|antmember\.forest|com\.alipay\.antfarm\.listHomePage|babafarm|antocean" PortEntry.m antforest >/dev/null 2>&1; then
  echo "仍存在森林/其它模块接口"
  exit 1
fi

echo "[check] 不应引用已删除的 UI/音效/模拟器文件..."
for token in "StepSimulator" "DebugTool" "beginwav" "BgRun" "XMLReader"; do
  if grep -R "$token" --include='*.m' --include='*.h' PortEntry.m antforest >/dev/null 2>&1; then
    echo "仍引用 $token"
    exit 1
  fi
done

echo "[check] 未确认的家庭接口必须默认为空..."
grep -q 'rankOperationType = @""' antforest/AntManorIntimacy.m
grep -q 'familyTaskOperationType = @""' antforest/AntManorIntimacy.m

echo "[check] 敏感配置必须被忽略..."
grep -q "manor-config.json" .gitignore

echo "[check] 通过"
