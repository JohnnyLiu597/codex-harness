# Eval Case: Hook Privacy

Verifies that lifecycle hooks preserve only metadata and hashes. Adversarial
fixtures cover prompt text, summaries, shell commands, patch bodies, tool
responses, and credential-like values. The same workflow test also checks
official deny output, bounded Stop continuation, successful-verification
closure, and valid empty JSON for Stop-family events.
