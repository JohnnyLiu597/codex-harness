# Tool Failures

Record tool failures that affect the task or repeat:

```powershell
.\scripts\new-tool-failure.ps1 -Tool "playwright" -FailureType "timeout" -Summary "<what happened>" -Recovery "<what worked>"
```

Triage repeated failures into tool eval cases, docs, skills, rules, or scripts.
Do not store secrets, cookies, auth files, browser profiles, or full prompts.
