# Worker 审查修复任务

请 ai_worker 按 docs/review-findings.md 修复删除照片的持久清理重试。与backend直接写文件同步契约：建议SQL原子写 jobs cleanup payload包含original+analysis paths。worker负责claim/实际Storage删除/finish重试，不改变业务盖章。UI清理中状态需返回字段，请提供契约到worker-contract.md。

另请与backend协作ALL用户编辑后仍完成照片归类，用户摘要/字段保持优先。必须解除worker整项user_edited跳过，但由SQL保护用户字段版本。阅读docs/backend-fixes-task.md，两者一起完成。

root负责食物区间编辑器与UI。完成后跑针对性worker测试并更新worker-status。
