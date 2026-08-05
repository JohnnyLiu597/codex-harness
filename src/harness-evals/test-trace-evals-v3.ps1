param()

$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Remove-TestDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    [System.IO.Directory]::Delete([System.IO.Path]::GetFullPath($Path), $true)
}

function Write-PromptCase {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Expected,
        [string]$MustInclude = "",
        [string]$MustNotInclude = "",
        [string]$MustIncludeEvents = "",
        [string]$MustNotIncludeEvents = "",
        [string]$MustIncludeTools = "",
        [string]$MustNotIncludeTools = "",
        [int]$MinScore = 70,
        [int]$TimeoutSeconds = 5,
        [int]$Attempts = 1
    )

    [pscustomobject][ordered]@{
        id = $Id
        enabled = "true"
        lane = "v3-regression"
        kind = "v3-regression"
        prompt = $Prompt
        expected = $Expected
        must_include = $MustInclude
        must_not_include = $MustNotInclude
        must_include_events = $MustIncludeEvents
        must_not_include_events = $MustNotIncludeEvents
        must_include_tools = $MustIncludeTools
        must_not_include_tools = $MustNotIncludeTools
        min_score = [string]$MinScore
        timeout_seconds = [string]$TimeoutSeconds
        attempts = [string]$Attempts
    } | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function Invoke-TraceRunner {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Surface,
        [Parameter(Mandatory = $true)][string]$PromptFile,
        [Parameter(Mandatory = $true)][string]$RunsRoot,
        [Parameter(Mandatory = $true)][string]$CodexCommand,
        [int]$TimeoutSeconds = 5,
        [int]$Attempts = 1,
        [switch]$NoGrade
    )

    $arguments = @{
        PromptFile = $PromptFile
        RunsRoot = $RunsRoot
        CodexCommand = $CodexCommand
        TimeoutSeconds = $TimeoutSeconds
        Attempts = $Attempts
        AllowFailures = $true
    }
    if ($Surface.ContainsKey("CodexHome")) { $arguments.CodexHome = $Surface.CodexHome }
    if ($NoGrade) { $arguments.NoGrade = $true }

    $raw = & $Surface.Runner @arguments
    return $raw | ConvertFrom-Json
}

$testRoot = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ("codex-trace-evals-v3-test-" + [guid]::NewGuid().ToString("N"))
$fakeCodexPath = Join-Path $testRoot "fake-codex.exe"
$fakeCodexHome = Join-Path $testRoot "codex-home"
$globalGradeDir = Join-Path $fakeCodexHome "harness-evals"
$childPidPath = Join-Path $testRoot "child.pid"
$retainedTempRoots = New-Object System.Collections.Generic.List[string]
$checks = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Force -Path $testRoot, $globalGradeDir | Out-Null

try {
    $fakeCodexSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;

public static class FakeCodex
{
    public static int Main(string[] args)
    {
        if (args.Any(value => value == "--version"))
        {
            Console.WriteLine("fake-codex 3.0");
            return 0;
        }

        if (args.Any(value => value == "child-sleep"))
        {
            Thread.Sleep(60000);
            return 0;
        }

        string prompt = Console.In.ReadToEnd();
        string attempt = Environment.GetEnvironmentVariable("CODEX_TRACE_EVAL_ATTEMPT") ?? "1";

        if (prompt.Contains("MODE_TIMEOUT"))
        {
            string executable = Process.GetCurrentProcess().MainModule.FileName;
            Process child = Process.Start(new ProcessStartInfo(executable, "child-sleep")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            });
            string pidPath = Environment.GetEnvironmentVariable("FAKE_CODEX_CHILD_PID");
            if (!String.IsNullOrWhiteSpace(pidPath))
            {
                File.WriteAllText(pidPath, child.Id.ToString());
            }
            Thread.Sleep(60000);
            return 0;
        }

        Console.WriteLine("{\"type\":\"thread.started\",\"thread_id\":\"fake-thread\"}");
        Console.WriteLine("{\"type\":\"turn.started\"}");

        if (prompt.Contains("MODE_RETRY") && attempt == "1")
        {
            Console.WriteLine("{\"type\":\"turn.failed\",\"error\":{\"message\":\"synthetic retry failure\"}}");
            return 17;
        }

        Console.WriteLine("{\"type\":\"item.started\",\"item\":{\"id\":\"item-1\",\"type\":\"command_execution\",\"command\":\"synthetic\",\"status\":\"in_progress\"}}");
        Console.WriteLine("{\"type\":\"item.completed\",\"item\":{\"id\":\"item-1\",\"type\":\"command_execution\",\"command\":\"synthetic\",\"status\":\"completed\",\"exit_code\":0}}");

        if (prompt.Contains("MODE_SELF_CONTAMINATION"))
        {
            Console.WriteLine("{\"type\":\"item.completed\",\"item\":{\"id\":\"item-2\",\"type\":\"reasoning\",\"text\":\"self-contamination-marker\"}}");
            Console.WriteLine("{\"type\":\"item.completed\",\"item\":{\"id\":\"item-3\",\"type\":\"agent_message\",\"text\":\"clean final answer\"}}");
        }
        else
        {
            Console.WriteLine("{\"type\":\"item.completed\",\"item\":{\"id\":\"item-2\",\"type\":\"agent_message\",\"text\":\"final-safe-answer\"}}");
        }

        Console.WriteLine("{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}");
        return 0;
    }
}
'@
    Add-Type -TypeDefinition $fakeCodexSource -Language CSharp -OutputAssembly $fakeCodexPath -OutputType ConsoleApplication

    $globalRunner = Join-Path $PSScriptRoot "run-trace-evals.ps1"
    $globalGrader = Join-Path $PSScriptRoot "grade-trace-evals.ps1"
    $projectRunner = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\templates\project-harness\scripts\run-codex-trace-evals.ps1")).Path
    $projectGrader = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\templates\project-harness\scripts\grade-codex-trace-evals.ps1")).Path
    Copy-Item -LiteralPath $globalGrader -Destination (Join-Path $globalGradeDir "grade-trace-evals.ps1") -Force

    $surfaces = @(
        @{ Name = "global"; Runner = $globalRunner; Grader = $globalGrader; CodexHome = $fakeCodexHome },
        @{ Name = "project"; Runner = $projectRunner; Grader = $projectGrader }
    )

    $env:FAKE_CODEX_CHILD_PID = $childPidPath

    foreach ($surface in $surfaces) {
        $surfaceRoot = Join-Path $testRoot $surface.Name
        $promptRoot = Join-Path $surfaceRoot "prompts"
        $runsRoot = Join-Path $surfaceRoot "runs"
        New-Item -ItemType Directory -Force -Path $promptRoot, $runsRoot | Out-Null

        $successPrompt = Join-Path $promptRoot "success.csv"
        $privatePromptMarker = "private-prompt-$($surface.Name)-9d81"
        $privateExpectedMarker = "private-expected-$($surface.Name)-6a42"
        Write-PromptCase -Path $successPrompt -Id "success-$($surface.Name)" `
            -Prompt "MODE_SUCCESS $privatePromptMarker" -Expected $privateExpectedMarker `
            -MustInclude "final-safe-answer" `
            -MustIncludeEvents "thread.started|item.started|item.completed|turn.completed" `
            -MustIncludeTools "command_execution"

        $success = Invoke-TraceRunner -Surface $surface -PromptFile $successPrompt -RunsRoot $runsRoot -CodexCommand $fakeCodexPath
        Assert-True ($success.status -eq "success") "$($surface.Name) success run did not report success"
        Assert-True ($success.run_status -eq "passed") "$($surface.Name) success run did not report run_status=passed"
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$success.run_id)) "$($surface.Name) success run omitted run_id"
        Assert-True ($success.duration_ms -ge 0) "$($surface.Name) success run omitted duration"

        $successManifestText = Get-Content -LiteralPath $success.manifests.result -Raw
        $successManifest = $successManifestText | ConvertFrom-Json
        Assert-True ([string]$successManifest.schema -match 'v3$') "$($surface.Name) result manifest is not v3"
        Assert-True ($successManifestText -notmatch [regex]::Escape($privatePromptMarker)) "$($surface.Name) result manifest persisted raw prompt text"
        Assert-True ($successManifestText -notmatch [regex]::Escape($privateExpectedMarker)) "$($surface.Name) result manifest persisted raw expected text"
        $successCase = @($successManifest.results)[0]
        Assert-True ($successCase.status -eq "completed") "$($surface.Name) success case did not complete"
        Assert-True ($successCase.failure_class -eq "none") "$($surface.Name) success case has a failure class"
        Assert-True ($successCase.attempt_count -eq 1 -and @($successCase.attempts).Count -eq 1) "$($surface.Name) success attempt metadata is wrong"
        Assert-True ($successCase.timeout_seconds -eq 5 -and $successCase.max_attempts -eq 1) "$($surface.Name) per-case controls were not recorded"
        Assert-True ((Get-Content -LiteralPath $successCase.final -Raw).Trim() -eq "final-safe-answer") "$($surface.Name) final artifact is not the parsed assistant message"

        $successGradesText = Get-Content -LiteralPath $success.manifests.grade -Raw
        $successGrades = $successGradesText | ConvertFrom-Json
        Assert-True ($successGrades.status -eq "passed") "$($surface.Name) event/tool invariant grade did not pass"
        Assert-True ($successGrades.grader.keyword_grading.label -eq "smoke") "$($surface.Name) keyword grading is not labeled smoke"
        Assert-True ($successGrades.grader.keyword_grading.version -eq "keyword-smoke-v3") "$($surface.Name) keyword grading version is missing"
        Assert-True ($successGrades.grader.keyword_grading.scope -eq "final-assistant-message") "$($surface.Name) keyword grading scope is not final assistant only"
        Assert-True ($successGradesText -notmatch [regex]::Escape($privatePromptMarker)) "$($surface.Name) grade manifest persisted raw prompt text"
        Assert-True ($successGradesText -notmatch [regex]::Escape($privateExpectedMarker)) "$($surface.Name) grade manifest persisted raw expected text"
        $checks.Add("$($surface.Name): final assistant and explicit event/tool invariants") | Out-Null

        $contaminationPrompt = Join-Path $promptRoot "self-contamination.csv"
        Write-PromptCase -Path $contaminationPrompt -Id "self-contamination-$($surface.Name)" `
            -Prompt "MODE_SELF_CONTAMINATION" -Expected "Only the final assistant message is graded." `
            -MustInclude "self-contamination-marker" -MinScore 100
        $contamination = Invoke-TraceRunner -Surface $surface -PromptFile $contaminationPrompt -RunsRoot $runsRoot -CodexCommand $fakeCodexPath
        Assert-True ($contamination.status -eq "failed" -and $contamination.run_status -eq "failed") "$($surface.Name) grade failure did not propagate with AllowFailures"
        Assert-True ($contamination.run_id -ne $success.run_id) "$($surface.Name) run IDs collided"
        $contaminationGrades = Get-Content -LiteralPath $contamination.manifests.grade -Raw | ConvertFrom-Json
        $contaminationGrade = @($contaminationGrades.grades)[0]
        Assert-True ($contaminationGrade.status -eq "failed") "$($surface.Name) self-contamination case unexpectedly passed"
        Assert-True ("self-contamination-marker" -in @($contaminationGrade.missing)) "$($surface.Name) grader read non-final trace content"
        $checks.Add("$($surface.Name): self-contamination regression") | Out-Null

        $retryPrompt = Join-Path $promptRoot "retry.csv"
        Write-PromptCase -Path $retryPrompt -Id "retry-$($surface.Name)" -Prompt "MODE_RETRY" -Expected "Second attempt completes." -Attempts 2
        $retry = Invoke-TraceRunner -Surface $surface -PromptFile $retryPrompt -RunsRoot $runsRoot -CodexCommand $fakeCodexPath -Attempts 2 -NoGrade
        Assert-True ($retry.status -eq "success" -and $retry.run_status -eq "passed") "$($surface.Name) retry did not recover"
        $retryManifest = Get-Content -LiteralPath $retry.manifests.result -Raw | ConvertFrom-Json
        $retryCase = @($retryManifest.results)[0]
        Assert-True ($retryCase.attempt_count -eq 2) "$($surface.Name) retry attempt count is wrong"
        Assert-True (@($retryCase.attempts)[0].failure_class -eq "nonzero-exit") "$($surface.Name) first retry failure was not classified"
        Assert-True (@($retryCase.attempts)[1].failure_class -eq "none") "$($surface.Name) successful retry retained a failure class"
        Assert-True (@($retryCase.attempts | Where-Object { $_.duration_ms -lt 0 }).Count -eq 0) "$($surface.Name) attempt duration is invalid"
        $checks.Add("$($surface.Name): attempts, durations, and failure classes") | Out-Null

        if (Test-Path -LiteralPath $childPidPath) { Remove-Item -LiteralPath $childPidPath -Force }
        $timeoutPrompt = Join-Path $promptRoot "timeout.csv"
        Write-PromptCase -Path $timeoutPrompt -Id "timeout-$($surface.Name)" -Prompt "MODE_TIMEOUT" -Expected "Timeout is classified." -TimeoutSeconds 1
        $timeout = Invoke-TraceRunner -Surface $surface -PromptFile $timeoutPrompt -RunsRoot $runsRoot -CodexCommand $fakeCodexPath -TimeoutSeconds 1 -NoGrade
        Assert-True ($timeout.status -eq "failed" -and $timeout.run_status -eq "failed") "$($surface.Name) timeout did not propagate with NoGrade and AllowFailures"
        $timeoutManifest = Get-Content -LiteralPath $timeout.manifests.result -Raw | ConvertFrom-Json
        $timeoutCase = @($timeoutManifest.results)[0]
        $timeoutAttempt = @($timeoutCase.attempts)[0]
        Assert-True ($timeoutCase.failure_class -eq "timeout" -and $timeoutAttempt.timed_out) "$($surface.Name) timeout was not classified"
        Assert-True ($timeoutAttempt.child_tree_cleanup -eq "terminated") "$($surface.Name) timeout did not report child-tree cleanup"
        Assert-True ($timeoutAttempt.duration_ms -ge 500 -and $timeoutAttempt.duration_ms -lt 10000) "$($surface.Name) timeout duration is outside the bounded window"
        Assert-True (Test-Path -LiteralPath $childPidPath -PathType Leaf) "$($surface.Name) fake child PID was not captured"
        $childPid = [int](Get-Content -LiteralPath $childPidPath -Raw)
        for ($poll = 0; $poll -lt 30 -and (Get-Process -Id $childPid -ErrorAction SilentlyContinue); $poll++) {
            Start-Sleep -Milliseconds 100
        }
        Assert-True (-not [bool](Get-Process -Id $childPid -ErrorAction SilentlyContinue)) "$($surface.Name) timeout left a child process running"
        $checks.Add("$($surface.Name): timeout status and child-tree cleanup") | Out-Null
    }

    $deterministicRunner = Join-Path $PSScriptRoot "run-harness-evals.ps1"
    $deterministicText = Get-Content -LiteralPath $deterministicRunner -Raw
    Assert-True ($deterministicText -notmatch 'verify-global-harness\.ps1') "deterministic eval runner still owns the global verifier"
    $registeredTempRoots = ([regex]::Matches($deterministicText, '\$tmpRoot\s*=\s*New-EvalTempRoot\s+-Prefix\s+["'']codex-[A-Za-z0-9-]+-eval-')).Count
    Assert-True ($registeredTempRoots -ge 1) "deterministic eval runner does not register TEMP roots"
    Assert-True ($deterministicText -notmatch 'Join-Path\s+\$env:TEMP\s+["'']codex-[A-Za-z0-9-]+-eval-') "deterministic eval runner bypasses the TEMP root registry"

    $deterministicHome = Join-Path $testRoot "deterministic-home"
    $deterministicScripts = Join-Path $deterministicHome "scripts"
    New-Item -ItemType Directory -Force -Path $deterministicScripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\scripts\safe-remove.ps1") -Destination (Join-Path $deterministicScripts "safe-remove.ps1") -Force

    $beforeTempRoots = @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter "codex-safe-remove-eval-*" | Select-Object -ExpandProperty FullName)
    $deterministicOne = (& $deterministicRunner -CodexHome $deterministicHome -EvalName "safe-remove" -AllowFailures) | ConvertFrom-Json
    $deterministicTwo = (& $deterministicRunner -CodexHome $deterministicHome -EvalName "safe-remove" -AllowFailures) | ConvertFrom-Json
    Assert-True ($deterministicOne.status -eq "success" -and $deterministicOne.run_status -eq "passed") "deterministic focused eval did not pass"
    Assert-True ($deterministicOne.run_id -ne $deterministicTwo.run_id) "deterministic run IDs collided"
    Assert-True (@($deterministicOne.results)[0].temp_root_count -eq 1) "deterministic eval did not register its TEMP root"
    Assert-True (@($deterministicOne.results)[0].temp_roots_cleaned -eq 1) "deterministic eval did not clean its TEMP root"
    $afterTempRoots = @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter "codex-safe-remove-eval-*" | Select-Object -ExpandProperty FullName)
    $newTempRoots = @($afterTempRoots | Where-Object { $_ -notin $beforeTempRoots })
    Assert-True ($newTempRoots.Count -eq 0) "successful deterministic eval leaked a TEMP root"

    Set-Content -LiteralPath (Join-Path $deterministicScripts "safe-remove.ps1") -Value 'throw "forced retained-artifact failure"' -Encoding ASCII
    $deterministicFailed = (& $deterministicRunner -CodexHome $deterministicHome -EvalName "safe-remove" -AllowFailures -KeepFailedArtifacts) | ConvertFrom-Json
    Assert-True ($deterministicFailed.status -eq "failed" -and $deterministicFailed.run_status -eq "failed") "deterministic failure status did not propagate"
    Assert-True (@($deterministicFailed.retained_temp_roots).Count -eq 1) "failed deterministic eval did not retain its requested artifacts"
    foreach ($path in @($deterministicFailed.retained_temp_roots)) {
        Assert-True (Test-Path -LiteralPath $path -PathType Container) "retained deterministic TEMP root is missing"
        $retainedTempRoots.Add([string]$path) | Out-Null
    }
    $checks.Add("deterministic: verifier ownership, cleanup, retained failures, and unique IDs") | Out-Null

    [ordered]@{
        status = "success"
        summary = "Trace and deterministic eval v3 regressions passed."
        checks = $checks.ToArray()
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    Remove-Item Env:FAKE_CODEX_CHILD_PID -ErrorAction SilentlyContinue
    foreach ($path in $retainedTempRoots) {
        try { Remove-TestDirectory -Path $path } catch { }
    }
    try { Remove-TestDirectory -Path $testRoot } catch { }
}
