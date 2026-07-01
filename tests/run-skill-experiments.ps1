#Requires -Version 7.0
<#
.SYNOPSIS
Run vally skill effectiveness experiments for specified skills.

.DESCRIPTION
Executes skill_effectiveness_experiment.yaml files for all or specified skills.
Each experiment runs two variants (baseline without skill, skill with skill context) and
stores results organized by timestamp.

Use -SkillPattern to filter by language (e.g., '*-py' for Python, '*-rs' for Rust)
or by service (e.g., 'azure-cosmos*' for Cosmos DB).

Results can be compared using compare-experiment.mjs to analyze skill impact on performance.

.PARAMETER ScenariosRoot
Root directory containing skill scenario subdirectories.
Defaults to: <script-dir>/scenarios

.PARAMETER ResultsRoot
Root directory where experiment results will be stored.
Defaults to: <script-dir>/vally-experiment-results

.PARAMETER SkillPattern
Filter which skills to run. Supports wildcards.
Defaults to '*-py' (all Python skills).
Examples: -SkillPattern '*-rust', -SkillPattern 'azure-ai-*'

.PARAMETER Workers
Number of parallel experiment runs. Defaults to 1 (sequential).

.PARAMETER DryRun
If set, shows what experiments would be run without actually running them.

.PARAMETER Compare
If set, runs compare-experiment.mjs after completion to generate A/B reports.

.EXAMPLE
./run-skill-experiments.ps1
# Run all Python skill experiments sequentially

.EXAMPLE
./run-skill-experiments.ps1 -SkillPattern '*-rust' -Workers 4
# Run all Rust skill experiments with 4 parallel workers

.EXAMPLE
./run-skill-experiments.ps1 -SkillPattern 'azure-cosmos*' -Verbose
# Run only Cosmos DB skill experiments with verbose output

.EXAMPLE
./run-skill-experiments.ps1 -Workers 5 -Compare
# Run all (Python) experiments with 5 parallel workers, then generate comparison reports

.EXAMPLE
./run-skill-experiments.ps1 -DryRun
# Preview which experiments would be run
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ScenariosRoot = (Join-Path $PSScriptRoot "scenarios"),
    
    [Parameter(Mandatory = $false)]
    [string]$ResultsRoot = (Join-Path $PSScriptRoot "vally-experiment-results"),
    
    [Parameter(Mandatory = $false)]
    [string]$SkillPattern = "*-py",
    
    [Parameter(Mandatory = $false)]
    [int]$Workers = 1,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [switch]$Compare
)

$ErrorActionPreference = "Stop"

# Validate vally is available
$vallyCmd = Get-Command vally -ErrorAction SilentlyContinue
if (-not $vallyCmd) {
    Write-Error "vally command not found. Please install Vally to run experiments."
    exit 1
}

Write-Information "Vally: $($vallyCmd.Source)"

# Find all matching skill scenarios with experiments
$skillDirs = Get-ChildItem -Path $ScenariosRoot -Directory -Filter $SkillPattern | 
Where-Object { Test-Path (Join-Path $_.FullName "vally" "skill_effectiveness_experiment.yaml") } |
Sort-Object Name

Write-Information "Found $($skillDirs.Count) skills with experiments matching pattern: $SkillPattern"

if ($skillDirs.Count -eq 0) {
    Write-Warning "No skills found matching pattern: $SkillPattern"
    exit 0
}

if ($DryRun) {
    Write-Information ""
    Write-Information "DRY RUN - Would execute the following experiments:"
    foreach ($skillDir in $skillDirs) {
        $experimentFile = Join-Path $skillDir.FullName "vally" "skill_effectiveness_experiment.yaml"
        Write-Information "  - $($skillDir.Name): $experimentFile"
    }
    exit 0
}

# Create results directory with timestamp
$timestamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ss-fffZ"
$experimentResultsDir = Join-Path $ResultsRoot $timestamp
New-Item -ItemType Directory -Path $experimentResultsDir -Force | Out-Null

Write-Information ""
Write-Information "Results Directory: $experimentResultsDir"
Write-Information "Parallel Workers: $Workers"
Write-Information ""

# Track results and timing
$results = @()
$completed = 0
$failed = 0
$totalSkills = $skillDirs.Count
$overallStartTime = Get-Date
$skillTimings = @()  # Track timings for ETA calculation

# Execute experiments
$scriptBlock = {
    param($SkillDir, $ExperimentResultsDir, $ResultsRoot, $SkillIndex, $TotalSkills)
    
    $skillName = $SkillDir.Name
    $vallyDir = Join-Path $SkillDir.FullName "vally"
    $experimentFile = Join-Path $vallyDir "skill_effectiveness_experiment.yaml"
    $skillResultsDir = Join-Path $ExperimentResultsDir $skillName
    
    try {
        Write-Host "[$SkillIndex/$TotalSkills] ▶ Starting: $skillName"
        
        $startTime = Get-Date
        
        # Run the experiment
        # Note: vally experiment run expects to be run from the scenario directory
        Push-Location $vallyDir
        try {
            $output = & vally experiment run skill_effectiveness_experiment.yaml 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        
        $duration = (Get-Date) - $startTime
        
        # Check for success by looking at output and exit code
        # Vally returns 0 on success, but also check for "passed" keyword in output
        $outputString = $output -join "`n"
        
        # Strip ANSI color codes from output to allow proper regex matching
        # vally uses ANSI codes for colored output which blocks metric extraction
        $outputString = $outputString -replace "`e\[[0-9;]*m", ''
        
        $succeeded = ($exitCode -eq 0) -and ($outputString -match "passed")
        
        # Extract baseline and skill scores from output
        # Vally output format: "score: XX.X% (threshold: YY.Y%)"
        # Each test case produces one score; baseline and skill variants run separately
        $baselineScore = $null
        $skillScore = $null
        $delta = $null
        
        # Extract metrics from vally output
        # Metrics section shows: Tokens, Turns, Tool calls, Errors, etc.
        # Split metrics into baseline (first half) and skill (second half) variants
        $allTokens = @()
        $allTurns = @()
        $allErrors = @()
        
        # Extract token counts (e.g., "Tokens        29,409")
        $tokenMatches = [regex]::Matches($outputString, 'Tokens\s+([\d,]+)')
        foreach ($match in $tokenMatches) {
            $tokenValue = $match.Groups[1].Value -replace ',', ''
            $allTokens += [int]$tokenValue
        }
        
        # Extract turns (e.g., "Turns         2")
        $turnMatches = [regex]::Matches($outputString, 'Turns\s+(\d+)')
        foreach ($match in $turnMatches) {
            $allTurns += [int]$match.Groups[1].Value
        }
        
        # Extract error counts (e.g., "Errors        0")
        $errorMatches = [regex]::Matches($outputString, 'Errors\s+(\d+)')
        foreach ($match in $errorMatches) {
            $allErrors += [int]$match.Groups[1].Value
        }
        
        # Extract all score values from vally output
        $scoreMatches = [regex]::Matches($outputString, 'score:\s*([\d.]+)%')
        
        if ($scoreMatches.Count -ge 2) {
            # Assuming first scores are baseline variant, last scores are skill variant
            # Average them if multiple test cases per variant
            $baselineScores = @()
            $skillScores = @()
            
            # Split scores roughly in half
            $midpoint = [math]::Floor($scoreMatches.Count / 2)
            for ($i = 0; $i -lt $midpoint; $i++) {
                $baselineScores += [double]$scoreMatches[$i].Groups[1].Value
            }
            for ($i = $midpoint; $i -lt $scoreMatches.Count; $i++) {
                $skillScores += [double]$scoreMatches[$i].Groups[1].Value
            }
            
            if ($baselineScores.Count -gt 0) {
                $baselineScore = ($baselineScores | Measure-Object -Average).Average
            }
            if ($skillScores.Count -gt 0) {
                $skillScore = ($skillScores | Measure-Object -Average).Average
            }
            if ($baselineScore -and $skillScore) {
                $delta = $skillScore - $baselineScore
            }
        }
        elseif ($scoreMatches.Count -eq 1) {
            $skillScore = [double]$scoreMatches[0].Groups[1].Value
        }
        
        # Separate baseline and skill metrics (split roughly in half like scores)
        $baselineTokens = $null
        $skillTokens = $null
        $baselineTurns = $null
        $skillTurns = $null
        $baselineErrors = 0
        $skillErrors = 0
        
        if ($allTokens.Count -ge 2) {
            $midpoint = [math]::Floor($allTokens.Count / 2)
            $baselineTokens = [int](($allTokens[0..($midpoint - 1)] | Measure-Object -Average).Average)
            $skillTokens = [int](($allTokens[$midpoint..($allTokens.Count - 1)] | Measure-Object -Average).Average)
        }
        elseif ($allTokens.Count -eq 1) {
            $skillTokens = $allTokens[0]
        }
        
        if ($allTurns.Count -ge 2) {
            $midpoint = [math]::Floor($allTurns.Count / 2)
            $baselineTurns = [int](($allTurns[0..($midpoint - 1)] | Measure-Object -Average).Average)
            $skillTurns = [int](($allTurns[$midpoint..($allTurns.Count - 1)] | Measure-Object -Average).Average)
        }
        elseif ($allTurns.Count -eq 1) {
            $skillTurns = $allTurns[0]
        }
        
        if ($allErrors.Count -ge 2) {
            $midpoint = [math]::Floor($allErrors.Count / 2)
            $baselineErrors = ($allErrors[0..($midpoint - 1)] | Measure-Object -Sum).Sum
            $skillErrors = ($allErrors[$midpoint..($allErrors.Count - 1)] | Measure-Object -Sum).Sum
        }
        elseif ($allErrors.Count -eq 1) {
            $skillErrors = $allErrors[0]
        }
        
        $totalErrors = $skillErrors + $baselineErrors
        
        if ($succeeded) {
            # Format impact indicator with efficiency metrics
            $impactStr = ""
            if ($delta -ne $null) {
                $impactDirection = if ($delta -ge 0) { "↑" } else { "↓" }
                $impactStr = " [baseline: $($baselineScore.ToString('F1'))% → skill: $($skillScore.ToString('F1'))% $impactDirection $($delta.ToString('+0.0;-0.0'))%]"
            }
            elseif ($skillScore) {
                $impactStr = " [skill: $($skillScore.ToString('F1'))%]"
            }
            
            Write-Host "[$SkillIndex/$TotalSkills] ✓ PASSED: $skillName ($($duration.TotalSeconds.ToString('F1'))s)$impactStr" -ForegroundColor Green
            return @{
                Skill          = $skillName
                Status         = "PASSED"
                Duration       = $duration.TotalSeconds
                BaselineScore  = $baselineScore
                SkillScore     = $skillScore
                Delta          = $delta
                BaselineTokens = $baselineTokens
                SkillTokens    = $skillTokens
                BaselineTurns  = $baselineTurns
                SkillTurns     = $skillTurns
                BaselineErrors = $baselineErrors
                SkillErrors    = $skillErrors
                Output         = $output
            }
        }
        else {
            Write-Host "[$SkillIndex/$TotalSkills] ✗ FAILED: $skillName (exit code: $exitCode)" -ForegroundColor Red
            return @{
                Skill          = $skillName
                Status         = "FAILED"
                Duration       = $duration.TotalSeconds
                BaselineScore  = $baselineScore
                SkillScore     = $skillScore
                Delta          = $delta
                BaselineTokens = $baselineTokens
                SkillTokens    = $skillTokens
                BaselineTurns  = $baselineTurns
                SkillTurns     = $skillTurns
                BaselineErrors = $baselineErrors
                SkillErrors    = $skillErrors
                Output         = $output
            }
        }
    }
    catch {
        Write-Host "[$SkillIndex/$TotalSkills] ✗ Error running $skillName : $_"
        return @{
            Skill    = $skillName
            Status   = "ERROR"
            Duration = 0
            Score    = $null
            Output   = $_.Exception.Message
        }
    }
}

# Run experiments with parallelization
$jobs = @()
$skillIndex = 0

foreach ($skillDir in $skillDirs) {
    $skillIndex++
    
    if ($Workers -eq 1) {
        # Sequential execution
        $result = & $scriptBlock $skillDir $experimentResultsDir $ResultsRoot $skillIndex $totalSkills
        $results += $result
        $skillTimings += $result.Duration
        
        if ($result.Status -ne "PASSED") {
            $failed++
        }
        else {
            $completed++
        }
        
        # Show ETA for sequential execution
        if ($skillIndex -lt $totalSkills -and $skillTimings.Count -gt 0) {
            $avgTime = ($skillTimings | Measure-Object -Average).Average
            $remainingSkills = $totalSkills - $skillIndex
            $estimatedSeconds = [int]($avgTime * $remainingSkills)
            $estimatedTime = "{0:D2}:{1:D2}" -f [int]($estimatedSeconds / 60), [int]($estimatedSeconds % 60)
            Write-Host "  → Estimated time remaining: $estimatedTime" -ForegroundColor Cyan
        }
    }
    else {
        # Parallel execution
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $skillDir, $experimentResultsDir, $ResultsRoot, $skillIndex, $totalSkills
        $jobs += @{
            Job        = $job
            Skill      = $skillDir.Name
            SkillIndex = $skillIndex
        }
    }
}

# Wait for parallel jobs
if ($jobs.Count -gt 0) {
    Write-Host "`nWaiting for $($jobs.Count) parallel jobs to complete..." -ForegroundColor Cyan
    
    foreach ($jobInfo in $jobs) {
        $job = $jobInfo.Job
        $result = Receive-Job -Job $job -Wait
        $results += $result
        $skillTimings += $result.Duration
        
        if ($result.Status -ne "PASSED") {
            $failed++
        }
        else {
            $completed++
        }
        
        Remove-Job -Job $job
    }
}

# Calculate overall timing
$overallDuration = (Get-Date) - $overallStartTime
$totalDurationStr = "{0}h {1}m {2}s" -f `
    [int]($overallDuration.TotalSeconds / 3600), `
    [int](($overallDuration.TotalSeconds % 3600) / 60), `
    [int]($overallDuration.TotalSeconds % 60)

Write-Host "`n" + ("=" * 80)
Write-Host "Skill Effectiveness Experiments Summary" -ForegroundColor Green
Write-Host ("=" * 80)

# Build results table with verdict and efficiency analysis
$resultsTable = @()
foreach ($result in $results) {
    # Determine verdict based on pass/fail logic
    $verdict = ""
    
    if ($result.Status -eq "PASSED") {
        # Skill passed - check efficiency
        if ($result.SkillTokens -and $result.BaselineTokens) {
            $tokenDelta = [int](($result.SkillTokens - $result.BaselineTokens) / $result.BaselineTokens * 100)
            if ($tokenDelta -lt -5) {
                $verdict = "✓ Effective"
            }
            elseif ($tokenDelta -gt 5) {
                $verdict = "✗ Inefficient"
            }
            else {
                $verdict = "~ Neutral"
            }
        }
        else {
            $verdict = "✓ Passed"
        }
    }
    else {
        $verdict = "✗ Failed"
    }
    
    # Calculate efficiency deltas
    $tokensDelta = ""
    $turnsDelta = ""
    
    if ($result.SkillTokens -and $result.BaselineTokens) {
        $pctChange = [int](($result.SkillTokens - $result.BaselineTokens) / $result.BaselineTokens * 100)
        $dir = if ($pctChange -ge 0) { "↑" } else { "↓" }
        $tokensDelta = "$dir $($pctChange.ToString('+0;-0'))%"
    }
    
    if ($result.SkillTurns -and $result.BaselineTurns) {
        $turnChange = $result.SkillTurns - $result.BaselineTurns
        $dir = if ($turnChange -ge 0) { "↑" } else { "↓" }
        $turnsDelta = "$dir $($turnChange.ToString('+0;-0'))"
    }
    
    $resultsTable += [PSCustomObject]@{
        Skill          = $result.Skill
        Status         = if ($result.Status -eq "PASSED") { "✓" } else { "✗" }
        Verdict        = $verdict
        'Tokens Δ'     = if ($tokensDelta) { $tokensDelta } else { "N/A" }
        'Turns Δ'      = if ($turnsDelta) { $turnsDelta } else { "N/A" }
        Errors         = $result.SkillErrors
        'Duration (s)' = $result.Duration.ToString('F1')
    }
}

# Display results table
$resultsTable | Format-Table -AutoSize

Write-Host ("=" * 80)
Write-Host "Results Summary" -ForegroundColor Cyan
Write-Host ("  Total Skills:   $totalSkills")
Write-Host ("  Passed:         $completed") -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host ("  Failed:         $failed") -ForegroundColor Red
}
else {
    Write-Host ("  Failed:         $failed") -ForegroundColor Green
}
Write-Host ("  Total Duration: $totalDurationStr") -ForegroundColor Cyan
Write-Host ("  Results Dir:    $experimentResultsDir") -ForegroundColor Cyan
Write-Host ("=" * 80)
Write-Information ""

if ($Compare) {
    Write-Information ""
    Write-Information "Generating comparison reports..."
    
    # Run compare-experiment.mjs for the experiment directory
    $compareScript = Join-Path $PSScriptRoot "compare-experiment.mjs"
    if (Test-Path $compareScript) {
        & node $compareScript $experimentResultsDir
    }
    else {
        Write-Warning "compare-experiment.mjs not found at: $compareScript"
    }
}

if ($failed -gt 0) {
    exit 1
}
