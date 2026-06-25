# opencode 视频多模态版 — 一键启动
# 用法: 在 D:\ProgrameAI\Opencode\opencode 目录下运行 .\start.ps1

$env:OPENCODE_EXPERIMENTAL_NATIVE_LLM = "true"

Write-Host @"
=============================================
  opencode 视频多模态版
  Native Runtime: ON
  Bun: $(bun --version)
  Model: xiaomi-token-plan-cn/mimo-v2-omni
=============================================
  
  TUI 模式: 直接回车
  CLI 模式: .\start.ps1 run "你的指令"
  
"@ -ForegroundColor Cyan

if ($args[0] -eq "run") {
    $prompt = $args[1]
    if (-not $prompt) { Write-Host "请提供指令" -ForegroundColor Red; exit 1 }
    bun run --cwd packages/opencode src/index.ts run $prompt --model xiaomi-token-plan-cn/mimo-v2-omni
} else {
    bun run dev
}
