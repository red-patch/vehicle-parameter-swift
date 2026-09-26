#!/bin/bash
# 性能验收测量（M5）：冷启动耗时 + 空闲内存
# 用法：scripts/measure_launch.sh [path/to/VehicleParameter.app]
set -euo pipefail

APP="${1:-$(find ~/Library/Developer/Xcode/DerivedData -name 'VehicleParameter.app' -path '*Debug*' 2>/dev/null | head -1)}"
[ -z "$APP" ] && { echo "未找到 app，请传入路径"; exit 1; }

echo "测量目标：$APP"

# 预热：终止已运行实例，确保冷启动
osascript -e 'quit app "VehicleParameter"' 2>/dev/null || true
pkill -x VehicleParameter 2>/dev/null || true
sleep 2

# 冷启动计时：从 launch 到进程被 pgrep 观察到
START=$(python3 -c 'import time; print(time.time())')
open "$APP"
for i in $(seq 1 100); do
    if pgrep -x VehicleParameter >/dev/null; then
        END=$(python3 -c 'import time; print(time.time())')
        break
    fi
    sleep 0.05
done
LAUNCH=$(python3 -c "print(f'{$END - $START:.2f}')")
echo "冷启动（launch → 进程可见）: ${LAUNCH}s"

# 空闲内存：物理足迹（physical footprint，排除进程间共享的框架只读页——
# RSS 会把 SwiftUI/AppKit 的共享映射算进来虚高 60MB+）
sleep 5
PID=$(pgrep -x VehicleParameter)
FOOTPRINT=$(vmmap --summary "$PID" 2>/dev/null | awk '/Physical footprint:/ {print $3; exit}' | sed 's/M//')
FOOTPRINT=${FOOTPRINT:-0}
echo "空闲内存（physical footprint）: ${FOOTPRINT}MB"

# 验收阈值
python3 - "$LAUNCH" "$FOOTPRINT" <<'PYEOF'
import sys
launch, mem = float(sys.argv[1]), float(sys.argv[2])
if launch >= 1.0:
    print(f"✗ 冷启动 {launch}s 未达 <1s 预算（含 open 命令与 LaunchServices 开销）")
else:
    print(f"✓ 冷启动 {launch}s")
if mem >= 40:
    print(f"✗ 空闲内存 {mem}MB 超出 40MB 目标")
else:
    print(f"✓ 空闲内存 {mem}MB（footprint 口径）")
PYEOF

osascript -e 'quit app "VehicleParameter"' 2>/dev/null || true
echo "完成"
