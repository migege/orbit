---
description: "智能 git commit，使用 Conventional Commits 格式"
allowed-tools:
  - "Bash(git add:*)"
  - "Bash(git status:*)"
  - "Bash(git commit:*)"
  - "Bash(git diff:*)"
---

分析 diff 内容，理解变更性质，然后：
1. 生成 3 个 commit message 候选项（Conventional Commits 格式）
2. 选择最合适的一个并说明理由
3. 如有必要先 git add，然后执行 git commit
4. 不要添加 Co-Authored-By 署名
