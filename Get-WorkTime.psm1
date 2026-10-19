<#
.SYNOPSIS
Displays system-on time summaries from the Windows System event log.

.DESCRIPTION
Get-WorkTime reads boot/wake and shutdown/sleep/hibernate events from the local System log
for the last N days (default 7), a single day (-Date) or a date range (-From/-To) and turns
them into sessions (Start -> End).

By default it shows a daily summary with the first start and last end per day, the WorkTime
(sum of all sessions, without the detected breaks: standby, sleep, shutdown and, with
-IncludeLock / -IncludeIdle, locks and idle) and the Overall time span (first start -> last end).
With -All it shows the individual sessions instead, with -Summary totals per week or month.
With -TargetHours, the daily summary and the totals also show the balance against a daily
target (overtime / undertime).

- A session that runs past midnight is split per day (ends at 24:00, continues at 00:00).
  If the system was already running when the range starts, the first day starts at 00:00.
- A session that is still running is shown with End "now".
- If the system was off for up to -OffMinutes (e.g. a quick reboot), the previous session
  continues.
- If the system crashed or lost power (a new boot while a session was still open), the
  end of that session is inferred from the last System log event before the new boot
  and marked with an asterisk (*).

Each session reports how it started and ended (StartType/EndType, column "Via" with -All):
  StartType: Boot, Sleep (wake from sleep), Standby (Modern Standby exit), Hibernate (resume),
             Idle (back after Idle, -IncludeIdle), Unlock (-IncludeLock),
             Continued (already running at midnight / at the start of the range)
  EndType:   Shutdown, Restart (only if longer than -OffMinutes, otherwise merged), Sleep,
             Standby (Modern Standby: lid, power button, Start menu), Hibernate,
             Idle (screen turned off after inactivity, -IncludeIdle), Lock (-IncludeLock),
             Crash (inferred, marked *), Continued (still running at midnight), Running (still running now)

-Verbose shows a summary (range, state at range start, events read, sessions and how they
ended). -Debug shows every start/end event and what was done with it, for troubleshooting.

The cmdlet returns typed objects (DateTime/TimeSpan) with a default table view, so the
output is suitable for both interactive use and further processing.

.PARAMETER Days
How many days back to include, including today. Default: 7.

.PARAMETER Date
Report a single day. Accepts a date in your culture's format (e.g. 05.10.2026 on de-CH) or
ISO format (2026-10-05), 'today', 'yesterday', a day offset (0 = today, -1 = yesterday) or a
day name (e.g. Monday / Montag = the most recent Monday, today included).

.PARAMETER From
First day of a date range. Accepts the same input as -Date.

.PARAMETER To
Last day of a date range (inclusive). Accepts the same input as -Date. Default: today.

.PARAMETER All
Show the individual sessions instead of the daily summary.

.PARAMETER OffMinutes
If the system was off (restart, sleep, standby, hibernate) for up to this many minutes, it is not
a break: the previous session continues. Default: 3. 0 = every off period is a break.
For idle and locks see -BreakMinutes. Alias: -MergeGapMinutes (name before version 2.0).

.PARAMETER BreakMinutes
With -IncludeIdle / -IncludeLock: idle and locks only count as a break if they last longer than
this many minutes; shorter ones count as work time. Default: 15. 0 = every idle/lock is a break.

.PARAMETER IncludeIdle
Also treat "Idle" (the screen turned off after inactivity, logged as Modern Standby with reason
idle timeout) as a break. Without it, idle is ignored completely, so e.g. a notebook left open
overnight counts as running until it goes to hibernate or is used again.

.PARAMETER IncludeLock
Also treat workstation lock/unlock as end/start of a session, so locked time does not count.
After a wake on the lock screen, the session starts at the unlock. Locks up to -BreakMinutes
count as work time. Reads Microsoft-Windows-Winlogon/Operational (no admin rights needed). That log
is small (1 MB by default) and may only cover a few weeks; a warning is shown if it does not
reach back to the start of the range.

.PARAMETER TargetHours
Daily target work time, as hours:minutes (8:24) or hours (8.4). Adds Target, Balance
(WorkTime - Target) and a running Total to the daily summary, and Target/Balance to -Summary.
Ignored with -All (sessions have no target), so it can be set as a default in $PSDefaultParameterValues.

.PARAMETER TargetDays
Which days have a target (with -TargetHours):
  WorkedWeekdays (default) - Mon-Fri with work. Days off (vacation, holidays) count nothing,
                             work on the weekend counts fully as overtime.
  Weekdays                 - every Mon-Fri, also without work (shown as a row with 00:00).
  WorkedDays               - every day with work, also on the weekend.

.PARAMETER Summary
Week or Month: one row per ISO week (e.g. 2026-W11, Monday to Sunday) or calendar month with
the number of days worked, total and average WorkTime (and Target/Balance with -TargetHours).
Cannot be combined with -All.

.PARAMETER Raw
Skip the table view and show the plain property values. The returned objects are the same.

.OUTPUTS
GetWorkTime.Daily (GetWorkTime.Daily.Target with -TargetHours), GetWorkTime.Session with -All,
GetWorkTime.Summary.Week / .Month (+ .Target) with -Summary.

.NOTES
Day names and dates are localized based on your system culture (e.g. "Mi" and 12.11.2025 on de-CH).
Start events: Kernel-General 12, EventLog 6005 (boot); Power-Troubleshooter 1, Kernel-Power 107 (wake);
              Kernel-Power 507 (exiting Modern Standby); Kernel-Boot 27 with boot type 2 (resume from hibernation)
End events:   Kernel-General 13, EventLog 6006, User32 1074 (shutdown); Kernel-Power 42 (sleep/hibernate);
              Kernel-Power 506 (entering Modern Standby); Kernel-Power 109 with action 5 (restart)
Short standby periods (e.g. 506 -> 507 right after boot) are merged via -OffMinutes.

.EXAMPLE
Get-WorkTime
Shows the daily summary for the last 7 days.

.EXAMPLE
Get-WorkTime -Days 14
Shows the daily summary for the last 14 days.

.EXAMPLE
Get-WorkTime -All
Shows the individual sessions (Start, End, WorkTime) for the last 7 days.

.EXAMPLE
Get-WorkTime -All -Days 10 -OffMinutes 2
Shows the sessions for the last 10 days; the system being off for up to 2 minutes is not a break.

.EXAMPLE
Get-WorkTime yesterday -All
Shows the sessions of yesterday.

.EXAMPLE
Get-WorkTime -Date 2026-10-05
Shows the daily summary for October 5th, 2026.

.EXAMPLE
Get-WorkTime -From 2026-09-01 -To 2026-09-30 | Export-Csv worktime-09.csv -NoTypeInformation
Exports the daily summary for September 2026.

.EXAMPLE
Get-WorkTime -From Monday
Shows the daily summary from the most recent Monday until today.

.EXAMPLE
Get-WorkTime -Days 30 -All | Where-Object EndType -eq 'Crash'
Lists the sessions of the last 30 days that ended with a crash or power loss.

.EXAMPLE
Get-WorkTime -All -IncludeLock
Shows the sessions of the last 7 days; locking the workstation ends a session, unlocking starts one.

.EXAMPLE
Get-WorkTime -From Monday -TargetHours 8:24
Shows this week with the balance per day against 8:24 hours and the running total.

.EXAMPLE
Get-WorkTime -From 2026-01-01 -Summary Month -TargetHours 8:24
Shows total, average and balance per month since January 1st.

.EXAMPLE
Get-WorkTime -Date Friday -All -Debug
Shows every start/end event of Friday and how it was interpreted (troubleshooting).
#>

function Get-WorkTime {
    [CmdletBinding(DefaultParameterSetName = 'Days')]
    [OutputType('GetWorkTime.Daily', 'GetWorkTime.Session')]
    param(
        [Parameter(ParameterSetName = 'Days')]
        [ValidateRange(1, 3650)]
        [int]$Days = 7,

        # Untyped on purpose: converted by ConvertTo-WorkTimeDate (see there why)
        [Parameter(ParameterSetName = 'Date', Mandatory, Position = 0)]
        $Date,

        [Parameter(ParameterSetName = 'Range', Mandatory)]
        $From,

        [Parameter(ParameterSetName = 'Range')]
        $To,

        [switch]$All,
        [ValidateRange(0, 1440)]
        [Alias('MergeGapMinutes')]
        [int]$OffMinutes = 3,
        [ValidateRange(0, 1440)]
        [int]$BreakMinutes = 15,
        [switch]$IncludeIdle,
        [switch]$IncludeLock,

        # Untyped on purpose: '8:24' (hours:minutes) or 8.4 (hours), see ConvertTo-TargetTime
        $TargetHours,
        [ValidateSet('WorkedWeekdays', 'Weekdays', 'WorkedDays')]
        [string]$TargetDays = 'WorkedWeekdays',
        [ValidateSet('Week', 'Month')]
        [string]$Summary,

        [switch]$Raw
    )

    # Windows PowerShell 5.1 would ask "Continue?" after every -Debug message
    if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'Continue' }

    if ($All -and $Summary) { throw '-Summary cannot be combined with -All.' }
    # Sessions have no target: -TargetHours is ignored with -All (no error, so it can be a default in $PSDefaultParameterValues)
    $target = if ($PSBoundParameters.ContainsKey('TargetHours')) { ConvertTo-TargetTime $TargetHours }
    if ($All -and $target) {
        Write-Verbose '-TargetHours is ignored with -All (sessions have no target).'
        $target = $null
    }

    $now   = Get-Date
    $today = $now.Date

    # Report range: $rangeStart (inclusive) .. $rangeEnd (exclusive, midnight after the last day)
    switch ($PSCmdlet.ParameterSetName) {
        'Date'  {
            $rangeStart = (ConvertTo-WorkTimeDate $Date -ParameterName Date).Date
            $lastDay    = $rangeStart
        }
        'Range' {
            $rangeStart = (ConvertTo-WorkTimeDate $From -ParameterName From).Date
            $lastDay    = if ($PSBoundParameters.ContainsKey('To')) { (ConvertTo-WorkTimeDate $To -ParameterName To).Date } else { $today }
        }
        default {
            $rangeStart = $today.AddDays(1 - $Days)
            $lastDay    = $today
        }
    }
    $rangeEnd = $lastDay.AddDays(1)

    if ($rangeStart -gt $today) { throw "The date $($rangeStart.ToString('d')) is in the future." }
    if ($lastDay -lt $rangeStart) { throw "-To ($($lastDay.ToString('d'))) is before -From ($($rangeStart.ToString('d')))." }

    $dayCount = ($rangeEnd - $rangeStart).Days
    Write-Verbose "Range: $($rangeStart.ToString('d')) - $($lastDay.ToString('d')) ($dayCount day$(if ($dayCount -ne 1) { 's' }))"

    $oldest = Get-OldestEventTime
    if ($oldest -and $oldest -gt $rangeStart) {
        Write-Warning "The System log only goes back to $($oldest.ToString('g')). Results before that are missing or incomplete."
    }

    # --- 1. Events -> sessions (across the whole range) ---
    $sessions  = [System.Collections.Generic.List[object]]::new()
    $openStart = $null    # start of the currently open session
    $openType  = $null    # its StartType
    $lastBoot  = $null    # last boot event (to recognize the 2nd boot event of the same boot)
    $lastEnd   = $null    # time of the last end event (for gap merging)
    $lastEndType = $null  # its type (a wake after 'Idle' starts as 'Idle')
    $mergeable = $false   # the last session ended cleanly and may be reopened
    $merges    = 0

    # Gaps up to this many minutes continue the previous session: inactivity (Idle, Lock) uses
    # -BreakMinutes, the system being off (restart, brief standby, ...) -OffMinutes.
    $gapLimit = {
        param($endType)
        if ($endType -in 'Idle', 'Lock') { $BreakMinutes } else { $OffMinutes }
    }

    # Idle (screen off after inactivity) is only used with -IncludeIdle
    $isUsed = { param($r) (Get-EventKind $r) -and ($IncludeIdle -or (Get-EventType $r) -ne 'Idle') }
    $locked    = $false   # -IncludeLock: workstation locked (a wake then waits for the unlock)

    if ($IncludeLock) {
        $lockOldest = Get-OldestEventTime -LogName $script:LockLog
        if (-not $lockOldest) {
            Write-Warning "-IncludeLock: no events in $script:LockLog (log empty, disabled or not readable)."
        }
        elseif ($lockOldest -gt $rangeStart) {
            Write-Warning "-IncludeLock: $script:LockLog only goes back to $($lockOldest.ToString('g')). Lock/unlock before that is missing."
        }
    }

    # State at range start: the latest start/end (and lock/unlock) event before it
    $powerBefore = @(Get-SystemEvent -Before $rangeStart -Relevant -MaxEvents 5 |
        Where-Object { (& $isUsed $_) -and (Get-EventKind $_) -ne 'Detail' })
    $lockBefore  = if ($IncludeLock) { Get-LatestEvent (Get-LockEvent -Before $rangeStart -MaxEvents 2) }
    $before      = Get-LatestEvent (@($powerBefore) + @($lockBefore | Where-Object { $_ }))
    $beforeKind  = if ($before) { Get-EventKind $before }
    if ($lockBefore -and (Get-EventKind $lockBefore) -eq 'Lock') {
        # Still locked, unless the system booted since
        $locked = -not ($powerBefore | Where-Object { (Get-EventKind $_) -eq 'Boot' -and $_.TimeCreated -gt $lockBefore.TimeCreated })
    }

    if ($before -and $beforeKind -notin 'End', 'Lock' -and -not $locked) {
        $openStart = $rangeStart
        $openType  = 'Continued'
        if ($beforeKind -eq 'Boot') { $lastBoot = $before }
        Write-Verbose "At range start: running (last start: $(Get-EventType $before), $($before.TimeCreated.ToString('g')))"
    }
    elseif ($before -and $beforeKind -in 'End', 'Lock') {
        # Stopped shortly before the range: an empty placeholder session lets a start
        # within -OffMinutes continue at $rangeStart (same result as a longer range)
        $sessions.Add((New-Session -Start $rangeStart -End $rangeStart -StartType 'Continued' -EndType 'Continued'))
        $lastEnd     = $before.TimeCreated
        $lastEndType = Get-EventType $before
        $mergeable   = $true
        Write-Verbose "At range start: off (last end: $(Get-EventType $before), $($before.TimeCreated.ToString('g')))"
    }
    elseif ($before) {
        Write-Verbose "At range start: on, but locked (since $($lockBefore.TimeCreated.ToString('g')))"
    }
    else {
        Write-Verbose 'At range start: off (no earlier start/end event in the System log)'
    }

    # Read until now, not just until $rangeEnd: whether a session open at $rangeEnd was
    # still running, crashed or merged is only known from the events after it.
    # A resume from hibernation is sorted 5 s earlier, so it is handled before the events
    # logged right after the resume (e.g. Modern Standby 506/507 in the same second).
    $events = @(@(Get-SystemEvent -After $rangeStart -Relevant) + @(if ($IncludeLock) { Get-LockEvent -After $rangeStart }) |
        Where-Object { $_ -and (& $isUsed $_) } |
        Sort-Object { $t = $_.TimeCreated.ToUniversalTime(); if ((Get-EventKind $_) -eq 'Resume') { $t.AddSeconds(-5) } else { $t } }, RecordId)
    if ($IncludeLock) {
        $lockCount = @($events | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Winlogon' }).Count
        Write-Verbose "Read $($events.Count - $lockCount) start/end events from the System log and $lockCount lock/unlock events"
    }
    else {
        Write-Verbose "Read $($events.Count) start/end events from the System log"
    }

    $time = $null
    foreach ($ev in $events) {
        $kind = Get-EventKind $ev

        if ($kind -eq 'Detail') {
            # Restart (Kernel-Power 109, logged shortly after 1074/6006): the session closed by this
            # shutdown ends with 'Restart'. A quick restart is merged anyway (-OffMinutes), not shown.
            $last = if ($sessions.Count) { $sessions[$sessions.Count - 1] }
            if (-not $openStart -and $last -and $last.EndType -eq 'Shutdown' -and
                (Get-Duration $last.End $ev.TimeCreated).TotalMinutes -le 10) {
                $last.EndType = 'Restart'
                Write-EventTrace $ev 'the shutdown before was a restart'
            }
            else {
                Write-EventTrace $ev 'ignored'
            }
            continue
        }

        $type     = Get-EventType $ev
        $prevTime = $time     # time of the previous relevant event
        $time     = $ev.TimeCreated

        if ($kind -eq 'Resume' -and $openStart) {
            # Resumed from hibernation while a session is open: the wake event logged on resume
            # had a stale timestamp (clock not yet corrected, e.g. 107 right after 42) and wrongly
            # reopened the session. The system was hibernated since the previous event.
            if ($prevTime -and $prevTime -gt $openStart) {
                $sessions.Add((New-Session -Start $openStart -End $prevTime -StartType $openType -EndType 'Hibernate'))
                Write-EventTrace $ev "running, but resumed from hibernation: session $(Format-Span $openStart $prevTime) ends at the previous event (stale wake timestamp); new session"
            }
            else {
                Write-EventTrace $ev 'running, but resumed from hibernation: hibernated since before the range; new session'
            }
            $openStart = $time
            $openType  = $type
            $mergeable = $false
            continue
        }

        if ($kind -in 'End', 'Lock') {
            # Several end events per shutdown (1074, 6006, 13): the first one closes the session
            if ($kind -eq 'Lock') { $locked = $true }
            if ($openStart) {
                if ($time -gt $openStart) {
                    $sessions.Add((New-Session -Start $openStart -End $time -StartType $openType -EndType $type))
                    Write-EventTrace $ev "session $(Format-Span $openStart $time) closed"
                }
                else {
                    # Zero length (e.g. standby logged right after a resume): kept as placeholder,
                    # so a start right after continues it (and keeps its StartType); not shown
                    $sessions.Add((New-Session -Start $openStart -End $openStart -StartType $openType -EndType $type))
                    Write-EventTrace $ev 'zero-length session (not shown; a start within the merge gap continues it)'
                }
                $openStart = $null
                $mergeable = $true
            }
            else {
                Write-EventTrace $ev $(if ($kind -eq 'Lock') { 'locked (not running)' } else { 'ignored (not running)' })
            }
            $lastEnd     = $time
            $lastEndType = $type
            continue
        }

        # -IncludeLock: after a wake on the lock screen, the session starts at the unlock.
        # A boot starts with a fresh logon, so it is never "locked".
        if ($kind -in 'Boot', 'Unlock') { $locked = $false }
        if ($locked -and -not $openStart) {
            # The system was off (asleep/hibernated) since $lastEnd. If longer than the merge gap,
            # the unlock must not continue the previous session, even if an end event logged right
            # after the resume (e.g. Modern Standby 506) makes the unlock look close to an end.
            if ($mergeable -and (Get-Duration $lastEnd $time).TotalMinutes -gt (& $gapLimit $lastEndType)) {
                $mergeable = $false
                Write-EventTrace $ev "locked: the session starts at the unlock (off for $([int](Get-Duration $lastEnd $time).TotalMinutes) min: no merge)"
            }
            else {
                Write-EventTrace $ev 'locked: the session starts at the unlock'
            }
            continue
        }

        # Boot, wake, resume or unlock. One boot logs Kernel-General 12 and shortly after EventLog 6005.
        $sameBoot = $kind -eq 'Boot' -and $ev.Id -eq 6005 -and $lastBoot -and $lastBoot.Id -eq 12 -and
                    (Get-Duration $lastBoot.TimeCreated $time).TotalMinutes -lt 10
        if ($kind -eq 'Boot') { $lastBoot = $ev }

        if ($openStart) {
            if ($kind -ne 'Boot' -or $sameBoot) {
                Write-EventTrace $ev 'ignored (already running)'
                continue
            }

            # New boot while a session is open: the system crashed or lost power.
            # Close the session at the last System log event before this boot
            # (only looked up if the session is within the range).
            $crash = if ($openStart -lt $rangeEnd) {
                (Get-LatestEvent (Get-SystemEvent -Before $time -MaxEvents 20)).TimeCreated
            }
            if ($crash -and $crash -gt $openStart) {
                $sessions.Add((New-Session -Start $openStart -End $crash -StartType $openType -EndType 'Crash'))
                Write-EventTrace $ev "boot while running = crash: session $(Format-Span $openStart $crash) ends at the last event before the boot; new session"
            }
            else {
                Write-EventTrace $ev 'boot while running = crash; new session'
            }
            $openStart = $time
            $openType  = $type
            $mergeable = $false
            continue
        }

        $gap   = if ($lastEnd) { Get-Duration $lastEnd $time }
        $limit = & $gapLimit $lastEndType
        if ($mergeable -and $gap.TotalMinutes -le $limit) {
            # Short gap (e.g. quick reboot, short idle): reopen the previous session
            $previous  = $sessions[$sessions.Count - 1]
            $openStart = $previous.Start
            $openType  = $previous.StartType
            $sessions.RemoveAt($sessions.Count - 1)
            $merges++
            Write-EventTrace $ev "gap $([int]$gap.TotalSeconds) s after $lastEndType <= $limit min: continues the session from $($openStart.ToString('g'))"
        }
        else {
            $openStart = $time
            # Back from screen-off after inactivity: the Modern Standby exit (507) starts as 'Idle'
            $openType  = if ($type -eq 'Standby' -and $lastEndType -eq 'Idle') { 'Idle' } else { $type }
            Write-EventTrace $ev 'new session'
        }
        $mergeable = $false
    }

    if ($openStart) {
        $sessions.Add((New-Session -Start $openStart -End $now -StartType $openType -EndType 'Running'))
        Write-Debug "Session $(Format-Span $openStart $now) is still running"
    }

    # --- 2. Split sessions at midnight, keep only days in range ---
    $pieces = foreach ($s in $sessions) {
        for ($day = $s.Start.Date; $day -lt $s.End; $day = $day.AddDays(1)) {
            if ($day -ge $rangeEnd) { break }
            $next       = $day.AddDays(1)
            $pieceStart = if ($s.Start -gt $day) { $s.Start } else { $day }
            $pieceEnd   = if ($s.End -lt $next)  { $s.End }   else { $next }
            if ($day -lt $rangeStart -or $pieceEnd -le $pieceStart) { continue }

            # A session split at midnight shows 'Continued' at the split
            [PSCustomObject]@{
                Date      = $day
                Start     = $pieceStart
                End       = $pieceEnd
                StartType = if ($pieceStart -eq $s.Start) { $s.StartType } else { 'Continued' }
                EndType   = if ($pieceEnd -eq $s.End)     { $s.EndType }   else { 'Continued' }
            }
        }
    }

    # --- 3. Build output rows ---
    $byDay = @($pieces | Group-Object { $_.Date })

    if ($pieces) {
        $ends = ($pieces | Group-Object EndType | Sort-Object Count -Descending |
            ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '
        Write-Verbose "$(@($pieces).Count) session(s) on $($byDay.Count) day(s); ended by: $ends"
        if ($merges) {
            $breaks = @(if ($IncludeIdle) { 'idle' }; if ($IncludeLock) { 'lock' }) -join '/'
            Write-Verbose ("$merges short gap(s) merged (off <= $OffMinutes min" +
                $(if ($breaks) { ", $breaks <= $BreakMinutes min" }) + ')')
        }
    }
    else {
        Write-Verbose 'No sessions in range'
    }

    if ($All) {
        foreach ($g in $byDay) {
            $n = 0
            foreach ($p in $g.Group) {
                $n++
                New-WorkTimeRow -TypeName 'GetWorkTime.Session' -Date $p.Date -Raw:$Raw -Properties ([ordered]@{
                    Session    = $n
                    StartTime  = $p.Start
                    EndTime    = $p.End
                    WorkTime   = Get-Duration $p.Start $p.End
                    StartType  = $p.StartType
                    EndType    = $p.EndType
                    IsInferred = $p.EndType -eq 'Crash'
                    IsRunning  = $p.EndType -eq 'Running'
                })
            }
        }
    }
    else {
        # Daily rows (as data first; target, balance and summaries are added below)
        $dayRows = [System.Collections.Generic.List[object]]::new()
        foreach ($g in $byDay) {
            $first    = $g.Group[0]
            $last     = $g.Group[$g.Count - 1]
            $workTime = [TimeSpan]::Zero
            foreach ($p in $g.Group) { $workTime += Get-Duration $p.Start $p.End }

            $dayRows.Add([ordered]@{
                Date       = $first.Date
                StartTime  = $first.Start
                EndTime    = $last.End
                WorkTime   = $workTime
                Overall    = Get-Duration $first.Start $last.End
                Sessions   = $g.Count
                StartType  = $first.StartType
                EndType    = $last.EndType
                IsInferred = $last.EndType -eq 'Crash'
                IsRunning  = $last.EndType -eq 'Running'
            })
        }

        if ($target) {
            # -TargetDays Weekdays: weekdays without work have a target too, so they get a row
            # (only days covered by the System log; before that nothing is known)
            if ($TargetDays -eq 'Weekdays') {
                $worked = @{}
                foreach ($d in $dayRows) { $worked[$d.Date] = $true }
                $firstKnown = if ($oldest -and $oldest.Date -gt $rangeStart) { $oldest.Date } else { $rangeStart }
                for ($day = $firstKnown; $day -lt $rangeEnd -and $day -le $today; $day = $day.AddDays(1)) {
                    if ((Test-Weekday $day) -and -not $worked.ContainsKey($day)) {
                        $dayRows.Add([ordered]@{
                            Date = $day; StartTime = $null; EndTime = $null
                            WorkTime = [TimeSpan]::Zero; Overall = [TimeSpan]::Zero; Sessions = 0
                            StartType = $null; EndType = $null; IsInferred = $false; IsRunning = $false
                        })
                    }
                }
                $dayRows = @($dayRows | Sort-Object { $_.Date })
            }

            # Target per day: WorkedWeekdays/Weekdays = Mon-Fri (weekend work is all overtime),
            # WorkedDays = every day with work. Days without work only exist here with Weekdays.
            $total = [TimeSpan]::Zero
            foreach ($d in $dayRows) {
                $d.Target  = if ($TargetDays -eq 'WorkedDays' -or (Test-Weekday $d.Date)) { $target } else { [TimeSpan]::Zero }
                $d.Balance = $d.WorkTime - $d.Target
                $total    += $d.Balance
                $d.Total   = $total
            }
        }

        if (-not $Summary) {
            $typeName = if ($target) { 'GetWorkTime.Daily.Target' } else { 'GetWorkTime.Daily' }
            foreach ($d in $dayRows) { New-WorkTimeRow -TypeName $typeName -Date $d.Date -Raw:$Raw -Properties $d }
            return
        }

        # --- -Summary: one row per ISO week / month ---
        $periodOf = if ($Summary -eq 'Week') { { Get-IsoWeek $_.Date } } else { { $_.Date.ToString('yyyy-MM', [cultureinfo]::InvariantCulture) } }
        foreach ($g in ($dayRows | Group-Object $periodOf)) {
            $firstDay = $g.Group[0].Date
            if ($Summary -eq 'Week') {
                $periodStart = $firstDay.AddDays(-(([int]$firstDay.DayOfWeek + 6) % 7))   # Monday
                $periodEnd   = $periodStart.AddDays(6)
            }
            else {
                $periodStart = [datetime]::new($firstDay.Year, $firstDay.Month, 1)
                $periodEnd   = $periodStart.AddMonths(1).AddDays(-1)
            }
            # Clipped to the requested range (and today)
            $periodTo = @($periodEnd, $lastDay, $today) | Sort-Object | Select-Object -First 1

            $workedDays = @($g.Group | Where-Object { $_.Sessions -gt 0 })
            $workTime   = [TimeSpan]::Zero
            foreach ($d in $workedDays) { $workTime += $d.WorkTime }

            $row = [ordered]@{
                $Summary = $g.Name
                From     = if ($periodStart -gt $rangeStart) { $periodStart } else { $rangeStart }
                To       = $periodTo
                Days     = $workedDays.Count
                WorkTime = $workTime
                Average  = if ($workedDays.Count) { [TimeSpan]::FromTicks($workTime.Ticks / $workedDays.Count) } else { [TimeSpan]::Zero }
            }
            if ($target) {
                $row.Target  = [TimeSpan]::Zero
                $row.Balance = [TimeSpan]::Zero
                foreach ($d in $g.Group) { $row.Target += $d.Target; $row.Balance += $d.Balance }
            }

            $obj = [PSCustomObject]$row
            if (-not $Raw) { $obj.PSObject.TypeNames.Insert(0, "GetWorkTime.Summary.$Summary$(if ($target) { '.Target' })") }
            $obj
        }
    }
}

<#
.SYNOPSIS
Appends completed days (or sessions) to a CSV file, to keep a history beyond the event log retention.

.DESCRIPTION
The event logs Get-WorkTime reads are overwritten when they are full. Export-WorkTime appends all
completed days (up to yesterday) that are not in the file yet, so it can be run as often as you like
(e.g. weekly) without creating duplicates. The first export starts at the beginning of the System log.

One row per day (default, WorkTime.csv) or per session (-All, WorkTime-Sessions.csv), in the current
folder unless -Path is given. Dates and times have a fixed format (2026-03-09, 07:52, 24:00 for a day
running until midnight); Hours are decimal hours. Separator and decimal point follow your regional
settings, so the file opens in Excel by double-click (-Invariant: comma and dot). An existing file
always keeps its format.

The Options column records how the rows were calculated (-OffMinutes, -IncludeIdle, -IncludeLock,
-BreakMinutes). A warning is shown if they differ from the last export.

.PARAMETER Path
The CSV file. Default: WorkTime.csv (or WorkTime-Sessions.csv with -All) in the current folder.

.PARAMETER All
Export the individual sessions instead of one row per day.

.PARAMETER OffMinutes
Passed to Get-WorkTime. Alias: -MergeGapMinutes.

.PARAMETER BreakMinutes
Passed to Get-WorkTime.

.PARAMETER IncludeIdle
Passed to Get-WorkTime.

.PARAMETER IncludeLock
Passed to Get-WorkTime. The lock/unlock log may only cover a few weeks, so export at least weekly.

.PARAMETER Invariant
For a new file: comma as separator and dot as decimal point, independent of the regional settings.

.PARAMETER PassThru
Also output the exported rows.

.EXAMPLE
Export-WorkTime
Appends all completed days not yet in .\WorkTime.csv.

.EXAMPLE
Export-WorkTime -All
Appends the sessions to .\WorkTime-Sessions.csv.

.EXAMPLE
Export-WorkTime D:\Backup\WorkTime.csv -IncludeLock
Appends the days, with locked time not counted, to D:\Backup\WorkTime.csv.

.EXAMPLE
Export-WorkTime -WhatIf
Shows what would be appended, without writing anything.
#>
function Export-WorkTime {
    # Write-Host: short status line, shown without -Verbose but not part of the output (suppress with 6>$null)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Path,
        [switch]$All,
        [ValidateRange(0, 1440)]
        [Alias('MergeGapMinutes')]
        [int]$OffMinutes = 3,
        [ValidateRange(0, 1440)]
        [int]$BreakMinutes = 15,
        [switch]$IncludeIdle,
        [switch]$IncludeLock,
        [switch]$Invariant,
        [switch]$PassThru
    )

    if (-not $Path) { $Path = if ($All) { 'WorkTime-Sessions.csv' } else { 'WorkTime.csv' } }
    $file = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

    $columns = if ($All) { 'Date', 'Day', 'Session', 'Start', 'End', 'WorkTime', 'Hours', 'StartType', 'EndType', 'Options' }
               else      { 'Date', 'Day', 'Start', 'End', 'WorkTime', 'Hours', 'Overall', 'Sessions', 'StartType', 'EndType', 'Options' }

    # How the rows are calculated (recorded in each row)
    $options = @("OffMinutes=$OffMinutes")
    if ($IncludeIdle) { $options += 'IncludeIdle' }
    if ($IncludeLock) { $options += 'IncludeLock' }
    if ($IncludeIdle -or $IncludeLock) { $options += "BreakMinutes=$BreakMinutes" }
    $options = $options -join ' '

    # CSV format: a new file uses the regional settings (or -Invariant), an existing one keeps its format
    $culture   = if ($Invariant) { [cultureinfo]::InvariantCulture } else { [cultureinfo]::CurrentCulture }
    $delimiter = $culture.TextInfo.ListSeparator
    $decimal   = $culture.NumberFormat.NumberDecimalSeparator
    $last      = $null

    if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0) {
        $header = Get-Content -LiteralPath $file -TotalCount 1
        if ($header -notmatch '^"Date"(.)') { throw "$file is not a file written by Export-WorkTime." }
        $delimiter = $Matches[1]
        $existing  = @($header.Split($delimiter) | ForEach-Object { $_.Trim('"') })
        if (($existing -join ',') -ne ($columns -join ',')) {
            if ($existing -contains 'Session') { throw "$file contains sessions. Use -All, or another -Path for days." }
            throw "$file contains days. Use it without -All, or another -Path for sessions."
        }
        $last = Import-Csv -LiteralPath $file -Delimiter $delimiter | Select-Object -Last 1
        if ($last -and $last.Hours -match '\d([.,])\d') { $decimal = $Matches[1] }
        if ($last -and $last.Options -ne $options) {
            Write-Warning "$file was exported with '$($last.Options)', now with '$options'. Its rows will be calculated differently."
        }
    }

    # Range: the day after the last exported one up to yesterday. First export: from the first complete
    # day of the System log (the day it starts is incomplete).
    $to   = (Get-Date).Date.AddDays(-1)
    $from = if ($last) { [datetime]::ParseExact($last.Date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture).AddDays(1) }
            else { $oldest = Get-OldestEventTime; if ($oldest) { $oldest.Date.AddDays(1) } }
    if (-not $from -or $from -gt $to) {
        Write-Host "$file is up to date."
        return
    }

    $params = @{
        From = $from; To = $to; All = $All
        OffMinutes = $OffMinutes; BreakMinutes = $BreakMinutes; IncludeIdle = $IncludeIdle; IncludeLock = $IncludeLock
    }
    $rows = @(Get-WorkTime @params | ForEach-Object { ConvertTo-ExportRow $_ -Session:$All -Decimal $decimal -Options $options })

    if (-not $rows) {
        Write-Host "No work time between $($from.ToString('d')) and $($to.ToString('d')); $file is up to date."
        return
    }

    $unit  = if ($All) { 'session(s)' } else { 'day(s)' }
    $range = "$($rows[0].Date) - $($rows[-1].Date)"
    if ($PSCmdlet.ShouldProcess($file, "Append $($rows.Count) $unit ($range)")) {
        $rows | Export-Csv -LiteralPath $file -Append -NoTypeInformation -Delimiter $delimiter -Encoding UTF8
        Write-Host "Exported $($rows.Count) $unit ($range) to $file"
        if ($PassThru) { foreach ($row in $rows) { $row } }
    }
}

<#
.SYNOPSIS
Statistics for the daily rows of Get-WorkTime: averages, longest days, start and end times, rest and more.

.DESCRIPTION
Pipe the daily rows of Get-WorkTime into Measure-WorkTime. The period, the switches (-IncludeLock,
-BreakMinutes, ...) and any filter (Where-Object) are up to you.

The result is one object with all statistics as typed properties (TimeSpan, DateTime, numbers).
The default list shows the most important ones, -Detailed all of them.

- Start statistics ignore days that started the day before (StartType Continued), end statistics
  ignore days without a real end (EndType Continued or Running).
- Short rest: the time between the end of one working day and the start of the next one is shorter
  than -MinRestHours.
- Target statistics (balance, days over/under target) only if the input comes from -TargetHours.
- Rows without work (from -TargetDays Weekdays) are skipped.
- A day that is still running (today) is not included by default, since it would distort the
  averages and the shortest day. Use -IncludeToday to include it.
- -ExcludeWeekends leaves out Saturdays and Sundays (e.g. a short check of mails on Sunday);
  the number of weekend days worked is still shown.

.PARAMETER InputObject
Daily rows of Get-WorkTime (not -All or -Summary).

.PARAMETER Detailed
Show all statistics instead of the most important ones. The returned object is the same.

.PARAMETER IncludeToday
Also include a day that is still running (normally today).

.PARAMETER ExcludeWeekends
Leave out Saturdays and Sundays. WeekendDays still counts them.

.PARAMETER LongDayHours
A day with more work time than this counts as a long day. Default: 10.

.PARAMETER LongWeekHours
An ISO week (Monday to Sunday) with at least this much work time counts as a long week. Default: 50.

.PARAMETER MinRestHours
Rest between two working days shorter than this counts as short rest. Default: 11.

.EXAMPLE
Get-WorkTime -Days 90 | Measure-WorkTime
Statistics of the last 90 days.

.EXAMPLE
Get-WorkTime -From 2026-01-01 -IncludeLock -TargetHours 8:24 | Measure-WorkTime -Detailed
All statistics since January 1st, locked time not counted, with the balance against 8:24 hours.

.EXAMPLE
Get-WorkTime -Days 90 | Where-Object DayOfWeekNumber -notin 0, 6 | Measure-WorkTime
Statistics of the weekdays only.

.EXAMPLE
(Get-WorkTime -Days 30 | Measure-WorkTime).AverageStart
The average start time of the last 30 days, as a TimeSpan.
#>
function Measure-WorkTime {
    [CmdletBinding()]
    [OutputType('GetWorkTime.Statistics')]
    param(
        [Parameter(ValueFromPipeline)]
        [psobject]$InputObject,
        [switch]$Detailed,
        [switch]$IncludeToday,
        [switch]$ExcludeWeekends,
        [ValidateRange(1, 24)]
        [double]$LongDayHours = 10,
        [ValidateRange(1, 168)]
        [double]$LongWeekHours = 50,
        [ValidateRange(1, 24)]
        [double]$MinRestHours = 11
    )

    begin {
        $rows    = [System.Collections.Generic.List[object]]::new()
        $running = 0   # skipped days that are still running
        $weekend = 0   # skipped weekend days (-ExcludeWeekends)
    }

    process {
        if ($null -eq $InputObject) { return }
        $names = $InputObject.PSObject.Properties.Name
        if ($names -contains 'Session' -or $names -notcontains 'Sessions' -or $names -notcontains 'StartTime') {
            throw 'Measure-WorkTime needs the daily rows of Get-WorkTime (without -All or -Summary).'
        }
        if ($InputObject.Sessions -le 0) { return }                    # rows without work (-TargetDays Weekdays)
        if ($InputObject.IsRunning -and -not $IncludeToday) { $running++; return }
        if ($ExcludeWeekends -and -not (Test-Weekday $InputObject.Date)) { $weekend++; return }
        $rows.Add($InputObject)
    }

    end {
        if (-not $rows.Count) {
            if ($running)     { Write-Warning 'No completed days to measure: the day is still running. Use -IncludeToday to include it.' }
            elseif ($weekend) { Write-Warning 'No weekdays to measure: only weekend days (-ExcludeWeekends).' }
            else              { Write-Warning 'No days with work time to measure.' }
            return
        }
        $days   = @($rows | Sort-Object Date)
        $starts = @($days | Where-Object StartType -ne 'Continued')                  # started that day
        $ends   = @($days | Where-Object { $_.EndType -notin 'Continued', 'Running' })   # real end that day

        # Work time
        $minutes = @($days | ForEach-Object { $_.WorkTime.TotalMinutes })
        $total   = [TimeSpan]::Zero
        foreach ($d in $days) { $total += $d.WorkTime }
        $average = [TimeSpan]::FromTicks($total.Ticks / $days.Count)
        # Ties: the earliest date wins (sorting is not stable in all PowerShell versions)
        $longest  = $days | Sort-Object @{ e = 'WorkTime'; Descending = $true }, Date | Select-Object -First 1
        $shortest = $days | Sort-Object WorkTime, Date | Select-Object -First 1
        $sorted  = @($minutes | Sort-Object)
        $middle  = [math]::Floor($sorted.Count / 2)
        $median  = if ($sorted.Count % 2) { $sorted[$middle] } else { ($sorted[$middle - 1] + $sorted[$middle]) / 2 }
        $spread  = [math]::Sqrt((@($minutes | ForEach-Object { [math]::Pow($_ - $average.TotalMinutes, 2) }) | Measure-Object -Sum).Sum / $days.Count)

        # Start and end
        $earliest = $starts | Sort-Object { $_.StartTime.TimeOfDay }, Date | Select-Object -First 1
        $latest   = $ends   | Sort-Object @{ e = { $_.EndTime.TimeOfDay }; Descending = $true }, Date | Select-Object -First 1
        $commonStart = $starts | Group-Object { $_.StartTime.Hour } | Sort-Object Count, { -[int]$_.Name } -Descending | Select-Object -First 1

        # Rest between two working days (not across a session running past midnight)
        $shortRests = 0
        for ($i = 1; $i -lt $days.Count; $i++) {
            $prev = $days[$i - 1]; $next = $days[$i]
            if ($prev.EndType -in 'Continued', 'Running' -or $next.StartType -eq 'Continued') { continue }
            if ((Get-Duration $prev.EndTime $next.StartTime).TotalHours -lt $MinRestHours) { $shortRests++ }
        }

        # Longest run of consecutive calendar days with work
        $streak = 1; $run = 1
        for ($i = 1; $i -lt $days.Count; $i++) {
            $run = if (($days[$i].Date - $days[$i - 1].Date).Days -eq 1) { $run + 1 } else { 1 }
            if ($run -gt $streak) { $streak = $run }
        }

        # Weeks
        $weeks = @($days | Group-Object { Get-IsoWeek $_.Date } | ForEach-Object {
            $sum = [TimeSpan]::Zero
            foreach ($d in $_.Group) { $sum += $d.WorkTime }
            [PSCustomObject]@{ Week = $_.Name; WorkTime = $sum }
        })
        $busiest = $weeks | Sort-Object @{ e = 'WorkTime'; Descending = $true }, Week | Select-Object -First 1

        # Trend: average work time of the 2nd half of the days minus the 1st half
        $trend = $null
        if ($days.Count -ge 2) {
            $half   = [math]::Floor($days.Count / 2)
            $first  = (@($minutes[0..($half - 1)]) | Measure-Object -Average).Average
            $second = (@($minutes[$half..($minutes.Count - 1)]) | Measure-Object -Average).Average
            $trend  = [TimeSpan]::FromMinutes($second - $first)
        }

        # Target (only if the input comes from -TargetHours)
        $hasTarget = $null -ne $days[0].PSObject.Properties['Balance']
        $balance   = $null
        if ($hasTarget) {
            $balance = [TimeSpan]::Zero
            foreach ($d in $days) { $balance += $d.Balance }
        }

        $result = [PSCustomObject]@{
            From                = $days[0].Date
            To                  = $days[-1].Date
            Days                = $days.Count
            TotalWorkTime       = $total
            AverageWorkTime     = $average
            MedianWorkTime      = [TimeSpan]::FromMinutes($median)
            WorkTimeSpread      = [TimeSpan]::FromMinutes($spread)
            LongestDay          = $longest.WorkTime
            LongestDayDate      = $longest.Date
            ShortestDay         = $shortest.WorkTime
            ShortestDayDate     = $shortest.Date
            AverageStart        = $(if ($starts) { Get-AverageTimeOfDay @($starts | ForEach-Object { $_.StartTime }) })
            EarliestStart       = $(if ($earliest) { $earliest.StartTime.TimeOfDay })
            EarliestStartDate   = $(if ($earliest) { $earliest.Date })
            CommonStartHour     = $(if ($commonStart) { [int]$commonStart.Name })
            AverageEnd          = $(if ($ends) { Get-AverageTimeOfDay @($ends | ForEach-Object { $_.EndTime }) })
            LatestEnd           = $(if ($latest) { $latest.EndTime.TimeOfDay })
            LatestEndDate       = $(if ($latest) { $latest.Date })
            LateEvenings        = @($ends | Where-Object { $_.EndTime.TimeOfDay -gt [TimeSpan]'20:00' }).Count
            AverageBreaks       = [TimeSpan]::FromTicks((@($days | ForEach-Object { ($_.Overall - $_.WorkTime).Ticks }) | Measure-Object -Average).Average)
            LongDays            = @($days | Where-Object { $_.WorkTime.TotalHours -gt $LongDayHours }).Count
            LongDayHours        = $LongDayHours
            LongWeeks           = @($weeks | Where-Object { $_.WorkTime.TotalHours -ge $LongWeekHours })
            LongWeekHours       = $LongWeekHours
            WeekendDays         = @($days | Where-Object { -not (Test-Weekday $_.Date) }).Count + $weekend
            ShortRests          = $shortRests
            MinRestHours        = $MinRestHours
            LongestStreak       = $streak
            TodayExcluded       = $running -gt 0
            WeekendsExcluded    = [bool]$ExcludeWeekends
            ByWeekday           = @($days | Group-Object { $_.Date.DayOfWeek } | Sort-Object { ([int]$_.Group[0].Date.DayOfWeek + 6) % 7 } | ForEach-Object {
                                      $sum = [TimeSpan]::Zero
                                      foreach ($d in $_.Group) { $sum += $d.WorkTime }
                                      [PSCustomObject]@{ DayOfWeek = $_.Group[0].Date.DayOfWeek; Days = $_.Count; AverageWorkTime = [TimeSpan]::FromTicks($sum.Ticks / $_.Count) }
                                  })
            Trend               = $trend
            BusiestWeek         = $busiest.Week
            BusiestWeekWorkTime = $busiest.WorkTime
            DayEnds             = @($ends | Group-Object EndType | Sort-Object Count -Descending | ForEach-Object {
                                      [PSCustomObject]@{ EndType = $_.Name; Count = $_.Count; Percent = [math]::Round(100 * $_.Count / $ends.Count) }
                                  })
            TotalBalance        = $balance
            DaysOverTarget      = $(if ($hasTarget) { @($days | Where-Object { $_.Balance -gt [TimeSpan]::Zero }).Count })
            DaysUnderTarget     = $(if ($hasTarget) { @($days | Where-Object { $_.Balance -lt [TimeSpan]::Zero }).Count })
        }
        $result.PSObject.TypeNames.Insert(0, $(if ($Detailed) { 'GetWorkTime.Statistics.Detailed' } else { 'GetWorkTime.Statistics' }))
        $result
    }
}

function Get-AverageTimeOfDay([datetime[]]$Times) {
    # Average time of day, e.g. of the start times
    [TimeSpan]::FromTicks((@($Times | ForEach-Object { $_.TimeOfDay.Ticks }) | Measure-Object -Average).Average)
}

function ConvertTo-ExportRow($Item, [switch]$Session, [string]$Decimal, [string]$Options) {
    # One CSV row of Export-WorkTime: fixed formats, only Hours uses the file's decimal point
    $inv   = [cultureinfo]::InvariantCulture
    $hours = [math]::Round($Item.WorkTime.TotalHours, 2).ToString($inv)
    if ($Decimal -ne '.') { $hours = $hours.Replace('.', $Decimal) }

    $row = [ordered]@{ Date = $Item.Date.ToString('yyyy-MM-dd', $inv); Day = "$($Item.DayOfWeek)" }
    if ($Session) { $row.Session = $Item.Session }
    $row.Start    = $Item.StartTime.ToString('HH:mm', $inv)
    $row.End      = if ($Item.EndTime -eq $Item.Date.AddDays(1)) { '24:00' } else { $Item.EndTime.ToString('HH:mm', $inv) }
    $row.WorkTime = Format-TimeSpan $Item.WorkTime
    $row.Hours    = $hours
    if (-not $Session) {
        $row.Overall  = Format-TimeSpan $Item.Overall
        $row.Sessions = $Item.Sessions
    }
    $row.StartType = $Item.StartType
    $row.EndType   = $Item.EndType
    $row.Options   = $Options
    [PSCustomObject]$row
}

function Format-TimeSpan([TimeSpan]$Time) {
    # hh:mm, hours can exceed 24
    '{0:00}:{1:00}' -f [math]::Floor($Time.TotalHours), $Time.Minutes
}

# Relevant System log events, keyed by "Provider/Id": kind (for the session logic) and
# type (reported as StartType/EndType). IDs alone are ambiguous (e.g. Kernel-General 1 = "system time changed").
$script:EventKinds = @{
    'Microsoft-Windows-Kernel-General/12'      = 'Boot',   'Boot'
    'EventLog/6005'                            = 'Boot',   'Boot'
    'Microsoft-Windows-Power-Troubleshooter/1' = 'Wake',   'Sleep'
    'Microsoft-Windows-Kernel-Power/107'       = 'Wake',   'Sleep'
    'Microsoft-Windows-Kernel-Power/507'       = 'Wake',   'Standby'    # exiting Modern Standby
    'Microsoft-Windows-Kernel-Boot/27'         = 'Resume', 'Hibernate'  # boot type 0x2 = resume from hibernation (see Get-EventKind)
    'Microsoft-Windows-Kernel-General/13'      = 'End',    'Shutdown'
    'EventLog/6006'                            = 'End',    'Shutdown'
    'User32/1074'                              = 'End',    'Shutdown'
    'Microsoft-Windows-Kernel-Power/42'        = 'End',    'Sleep'      # or Hibernate (see Get-EventType)
    'Microsoft-Windows-Kernel-Power/506'       = 'End',    'Standby'    # entering Modern Standby
    'Microsoft-Windows-Kernel-Power/109'       = 'Detail', 'Restart'    # shutdown transition; only restarts are used (see Get-EventKind)
}

# Workstation lock/unlock (-IncludeLock): Winlogon 811 delivered to the SENS subscriber,
# Event 4 = locked, 5 = unlocked. Readable without admin rights (unlike Security 4800/4801).
$script:LockLog = 'Microsoft-Windows-Winlogon/Operational'

function Get-LockKind($Record) {
    if ($Record.Id -ne 811 -or -not $Record.Properties -or $Record.Properties[1].Value -ne 'Sens') { return }
    switch ($Record.Properties[0].Value) { 4 { 'Lock' } 5 { 'Unlock' } }
}

function Get-EventKind($Record) {
    if ($Record.ProviderName -eq 'Microsoft-Windows-Winlogon') { return Get-LockKind $Record }
    $entry = $script:EventKinds["$($Record.ProviderName)/$($Record.Id)"]
    if (-not $entry) { return }
    # Kernel-Boot 27 is logged on every boot; only boot type 2 is a resume from hibernation
    if ($entry[0] -eq 'Resume' -and -not ($Record.Properties -and $Record.Properties[0].Value -eq 2)) { return }
    # Kernel-Power 109 is logged on every shutdown; ShutdownActionType 5 = restart (6 = power off)
    if ($entry[0] -eq 'Detail' -and -not ($Record.Properties -and $Record.Properties[0].Value -eq 5)) { return }
    $entry[0]
}

function Get-EventType($Record) {
    if ($Record.ProviderName -eq 'Microsoft-Windows-Winlogon') { return Get-LockKind $Record }
    $entry = $script:EventKinds["$($Record.ProviderName)/$($Record.Id)"]
    # Kernel-Power 42: TargetState 5 = S4 (hibernate), otherwise sleep
    if ($Record.Id -eq 42 -and $Record.Properties -and $Record.Properties[0].Value -eq 5) { return 'Hibernate' }
    # Kernel-Power 506: Reason (POWER_MONITOR_REQUEST_REASON) 12 = IdleTimeout, i.e. the screen turned
    # off after inactivity; other reasons (lid 15, power button 1, sleep button 14, ...) stay Standby
    if ($Record.Id -eq 506 -and $Record.Properties -and $Record.Properties[0].Value -eq 12) { return 'Idle' }
    $entry[1]
}

function Write-EventTrace($Record, [string]$Message) {
    # -Debug output: one line per event and what the session logic did with it
    if ($DebugPreference -eq 'SilentlyContinue') { return }
    $label = '{0} {1} ({2})' -f ($Record.ProviderName -replace '^Microsoft-Windows-'), $Record.Id, (Get-EventType $Record)
    Write-Debug ('{0}  {1,-34} -> {2}' -f $Record.TimeCreated.ToString('G'), $label, $Message)
}

function Get-Duration([datetime]$Start, [datetime]$End) {
    # Real elapsed time, also across a daylight saving change (25 h / 23 h days, 01:30-03:30 = 3 h
    # or 1 h). Subtracting local times directly would ignore the change.
    # Always use this for durations; comparisons (-lt/-gt) stay in local time.
    $End.ToUniversalTime() - $Start.ToUniversalTime()
}

function Format-Span([datetime]$Start, [datetime]$End) {
    $endFormat = if ($Start.Date -eq $End.Date) { 't' } else { 'g' }
    '{0}-{1}' -f $Start.ToString('g'), $End.ToString($endFormat)
}

function Get-OldestEventTime([string]$LogName = 'System') {
    (Get-WinEvent -LogName $LogName -Oldest -MaxEvents 1 -ErrorAction SilentlyContinue).TimeCreated
}

function Get-LockEvent {
    # Reads lock/unlock events (newest records first). Returns nothing if no event matches.
    param(
        [Nullable[datetime]]$After,
        [Nullable[datetime]]$Before,
        [int]$MaxEvents
    )

    $conditions = @('EventID=811')
    if ($After)  { $conditions += "TimeCreated[@SystemTime>='$(ConvertTo-XPathTime $After)']" }
    if ($Before) { $conditions += "TimeCreated[@SystemTime<'$(ConvertTo-XPathTime $Before)']" }

    $params = @{
        LogName     = $script:LockLog
        FilterXPath = "*[System[$($conditions -join ' and ')]] and " +
                      "*[EventData[Data[@Name='SubscriberName']='Sens' and (Data[@Name='Event']=4 or Data[@Name='Event']=5)]]"
        ErrorAction = 'Stop'
    }
    if ($MaxEvents) { $params.MaxEvents = $MaxEvents }

    try { Get-WinEvent @params }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
}

function Get-SystemEvent {
    # Reads System log events (newest records first). Returns nothing if no event matches.
    param(
        [Nullable[datetime]]$After,
        [Nullable[datetime]]$Before,
        [int]$MaxEvents,
        [switch]$Relevant   # only the events in $script:EventKinds
    )

    $conditions = @()
    if ($Relevant) {
        $conditions += '(' + (($script:EventKinds.Keys | ForEach-Object {
            $provider, $id = $_ -split '/'
            "(Provider[@Name='$provider'] and EventID=$id)"
        }) -join ' or ') + ')'
    }
    if ($After)  { $conditions += "TimeCreated[@SystemTime>='$(ConvertTo-XPathTime $After)']" }
    if ($Before) { $conditions += "TimeCreated[@SystemTime<'$(ConvertTo-XPathTime $Before)']" }

    $params = @{
        LogName     = 'System'
        FilterXPath = "*[System[$($conditions -join ' and ')]]"
        ErrorAction = 'Stop'
    }
    if ($MaxEvents) { $params.MaxEvents = $MaxEvents }

    try { Get-WinEvent @params }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
}

function ConvertTo-WorkTimeDate($Value, [string]$ParameterName) {
    # Converts -Date/-From/-To input to a date. The parameters are untyped because PowerShell
    # parses strings for [datetime] parameters with the invariant (US) culture, so "05.10.2026"
    # would silently become May 10th. (An ArgumentTransformation class is not an option: classes
    # used as attributes are not found when the function is called from outside the module.)
    # Accepts: [datetime], 'today', 'yesterday', day offsets (0, -1, ...), day names (most recent
    # such day, today included), or a date string in the current culture or ISO format (yyyy-MM-dd).
    if ($Value -is [datetime]) { return $Value }

    $today = [datetime]::Today
    if ($Value -is [int] -or $Value -is [long]) { return $today.AddDays($Value) }

    $text = "$Value".Trim()
    if ($text -eq 'today')     { return $today }
    if ($text -eq 'yesterday') { return $today.AddDays(-1) }
    if ($text -match '^[+-]?\d{1,4}$') { return $today.AddDays([int]$text) }

    foreach ($culture in [cultureinfo]::CurrentCulture, [cultureinfo]::InvariantCulture) {
        $names = $culture.DateTimeFormat.DayNames + $culture.DateTimeFormat.AbbreviatedDayNames
        for ($i = 0; $i -lt $names.Count; $i++) {
            if ($names[$i].TrimEnd('.') -eq $text.TrimEnd('.')) {
                return $today.AddDays(-((7 + [int]$today.DayOfWeek - ($i % 7)) % 7))
            }
        }
    }

    $date = [datetime]::MinValue
    if ([datetime]::TryParse($text, [cultureinfo]::CurrentCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$date)) {
        return $date
    }
    if ([datetime]::TryParseExact($text, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) {
        return $date
    }

    throw ("Cannot convert '$text' (-$ParameterName) to a date. Use e.g. '$($today.ToString('d'))', " +
           "'$($today.ToString('yyyy-MM-dd'))', 'today', 'yesterday', a day offset like -1, " +
           "or a day name like '$($today.ToString('dddd'))'.")
}

function ConvertTo-TargetTime($Value) {
    # -TargetHours: '8:24' (hours:minutes), 8.4 or '8.4' (hours), or a [TimeSpan]
    $time = $null
    if ($Value -is [TimeSpan]) { $time = $Value }
    elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { $time = [TimeSpan]::FromHours($Value) }
    else {
        $text  = "$Value".Trim()
        $hours = 0.0
        if ($text -match '^\d{1,2}:\d{2}$') { $time = [TimeSpan]::Parse($text) }
        elseif ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$hours) -or
                [double]::TryParse($text, [Globalization.NumberStyles]::Float, [cultureinfo]::CurrentCulture, [ref]$hours)) {
            $time = [TimeSpan]::FromHours($hours)
        }
    }
    if (-not $time -or $time -le [TimeSpan]::Zero -or $time -gt [TimeSpan]::FromHours(24)) {
        throw "Cannot use '$Value' as -TargetHours. Use hours:minutes (e.g. 8:24) or hours (e.g. 8.4), up to 24 hours."
    }
    $time
}

function Test-Weekday([datetime]$Date) {
    $Date.DayOfWeek -ne [DayOfWeek]::Saturday -and $Date.DayOfWeek -ne [DayOfWeek]::Sunday
}

function Get-IsoWeek([datetime]$Date) {
    # ISO 8601 week, e.g. 2026-W11. A week belongs to the year of its Thursday.
    $thursday = $Date.Date.AddDays(3 - (([int]$Date.DayOfWeek + 6) % 7))
    '{0}-W{1:00}' -f $thursday.Year, ([math]::Floor(($thursday.DayOfYear - 1) / 7) + 1)
}

function ConvertTo-XPathTime([datetime]$Time) {
    $Time.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
}

function Get-LatestEvent($Records) {
    # Record order is not strictly time order, so pick the latest by time
    $Records | Sort-Object { $_.TimeCreated.ToUniversalTime() } | Select-Object -Last 1
}

function New-Session {
    # Only creates an object in memory (no system change, so no -WhatIf)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param([datetime]$Start, [datetime]$End, [string]$StartType, [string]$EndType)

    [PSCustomObject]@{
        Start     = $Start
        End       = $End
        StartType = $StartType
        EndType   = $EndType
    }
}

function New-WorkTimeRow {
    # Only creates an object in memory (no system change, so no -WhatIf)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [string]$TypeName,
        [datetime]$Date,
        [System.Collections.IDictionary]$Properties,
        [switch]$Raw
    )

    $row = [ordered]@{
        Day             = $Date.ToString('ddd')
        DayOfWeek       = $Date.DayOfWeek
        DayOfWeekNumber = [int]$Date.DayOfWeek
        Date            = $Date
    }
    foreach ($key in $Properties.Keys) { $row[$key] = $Properties[$key] }

    $obj = [PSCustomObject]$row
    if (-not $Raw) { $obj.PSObject.TypeNames.Insert(0, $TypeName) }
    $obj
}

# Tab completion for the date parameters (any other input is accepted too)
$dateCompleter = {
    $wordToComplete = $args[2]   # PowerShell passes: command name, parameter name, word to complete, ...
    @('today', 'yesterday') + [cultureinfo]::CurrentCulture.DateTimeFormat.DayNames |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_) }
}
foreach ($param in 'Date', 'From', 'To') {
    Register-ArgumentCompleter -CommandName Get-WorkTime -ParameterName $param -ScriptBlock $dateCompleter
}

Export-ModuleMember -Function Get-WorkTime, Export-WorkTime, Measure-WorkTime
