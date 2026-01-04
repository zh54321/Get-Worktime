<#
.SYNOPSIS
Displays system-on time summaries from the Windows System event log, including inferred end times after crashes.

.DESCRIPTION
Get-WorkTime reads boot/wake and shutdown/sleep/hibernate events from the local System log
for the last N days (default 7). By default it shows a daily summary table with the first
start and last end per day (short day name + pretty date). If -All is used, it shows
the detailed in-day sessions (each Start → End pair with UpTime), merging tiny gaps
between sessions (e.g., quick reboot) within a configurable window.

If no proper shutdown/sleep/hibernate event is found for a past day (e.g. due to a system crash),
the end time is inferred from the last available System event of that day and marked with an
asterisk (*). The current day is never inferred.

The cmdlet returns structured PowerShell objects with a default table view,
making the output suitable for both interactive use and further processing.

.PARAMETER Days
How many days back to include, including today. Default: 7.

.PARAMETER All
If specified, show ONLY the detailed per-session table (no daily summary).

.PARAMETER MergeGapMinutes
When -All is used, a Start that occurs within this many minutes after the last End is
considered a continuation of the previous session. Default: 3.

.PARAMETER Raw
Return clean, pipeline-friendly objects (DateTime/TimeSpan/$null) without presentation markers like '-' or '*'.

.OUTPUTS
Formatted PSObjects

.NOTES
Day names and dates are localized based on your system culture (e.g., “Mi” and 12.11.2025 on de-CH).
Start events considered: 12 (Kernel-General), 6005 (EventLog), 1 (Power-Troubleshooter), 107 (Kernel-Power)
End events considered:   13 (Kernel-General), 6006 (EventLog), 42 (Kernel-Power), 1074 (USER32)

.EXAMPLE
Get-WorkTime
Shows the default daily summary table for the last 7 days.

.EXAMPLE
Get-WorkTime -Days 14
Shows the daily summary table for the last 14 days.

.EXAMPLE
Get-WorkTime -All
Shows ONLY the detailed per-session table (start, end, UpTime) for the last 7 days.

.EXAMPLE
Get-WorkTime -All -Days 10 -MergeGapMinutes 2
Shows per-session details for the last 10 days; merges gaps ≤ 2 minutes between sessions.
#>

function Get-WorkTime {
    [CmdletBinding()]
    param(
        [int]   $Days = 7,
        [switch]$All,
        [int]   $MergeGapMinutes = 3,
        [switch]$Raw
    )

    $startEventIds = @(12,6005,1,107)   # boot/wake/resume
    $endEventIds   = @(13,6006,42,1074) # shutdown/sleep/hibernate

    $today     = (Get-Date).Date
    $startDate = $today.AddDays(-[Math]::Max($Days,1) + 1)
    $endDate   = $today.AddDays(1)

    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        StartTime = $startDate
        EndTime   = $endDate
        Id        = ($startEventIds + $endEventIds)
    }

    if (-not $events) { return }

    # All System events in range (needed to infer crash end-time from "last event of the day")
    $allSystemEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        StartTime = $startDate
        EndTime   = $endDate
    } | Select-Object TimeCreated

    # Map: Date -> last System event time that day
    $lastEventByDate = @{}
    $allSystemEvents |
        Group-Object { $_.TimeCreated.Date } |
        ForEach-Object {
            $d = $_.Group[0].TimeCreated.Date
            $lastEventByDate[$d] = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        }

    $dailyRows   = New-Object System.Collections.Generic.List[object]
    $sessionRows = if ($All) { New-Object System.Collections.Generic.List[object] } else { $null }

    $groups = $events | Group-Object { $_.TimeCreated.Date }

    foreach ($g in $groups) {
        $dayEvents = $g.Group | Sort-Object TimeCreated
        $dateDT    = $dayEvents[0].TimeCreated.Date

        # --- Daily summary ---
        if (-not $All) {
            $upTimeTotal = $null
            $first = $dayEvents | Where-Object { $startEventIds -contains $_.Id } | Select-Object -First 1
            $last  = $dayEvents | Where-Object { $endEventIds   -contains $_.Id } | Sort-Object TimeCreated -Descending | Select-Object -First 1

            # End string + an effective end time for Overall/UpTime calculations
            $endStr = '-'
            $endTimeForCalc = $null

            if ($dateDT.Date -eq $today.Date) {
                # never show an End / UpTime / Overall for today in daily summary view
                $endStr = '-'
                $endTimeForCalc = $null
            }
            elseif ($last) {
                $endTimeForCalc = $last.TimeCreated
                $endStr = $endTimeForCalc.ToString('HH:mm')
            }
            elseif ($lastEventByDate.ContainsKey($dateDT.Date)) {
                $endTimeForCalc = $lastEventByDate[$dateDT.Date]
                $endStr = $endTimeForCalc.ToString('HH:mm') + '*'
            }

            # Overall = first start -> last end
            $overallStr = '-'
            if ($first -and $endTimeForCalc -and $endTimeForCalc -gt $first.TimeCreated) {
                $overallStr = "{0:hh\:mm}" -f ($endTimeForCalc - $first.TimeCreated)
            }

            # UpTime = sum of all sessions
            $upTimeStr = '-'
            if ($dateDT.Date -ne $today.Date) {
                $upTimeTotal  = [TimeSpan]::Zero
                $sStart       = $null
                $sLastEndTime = $null

                foreach ($ev in $dayEvents) {
                    if ($startEventIds -contains $ev.Id) {
                        $st = $ev.TimeCreated

                        # merge tiny gaps
                        if ($sLastEndTime -and ($st - $sLastEndTime).TotalMinutes -le $MergeGapMinutes) {
                            continue
                        }

                        if (-not $sStart) { $sStart = $st }
                        continue
                    }

                    if ($endEventIds -contains $ev.Id) {
                        if ($sStart) {
                            $et = $ev.TimeCreated
                            $d  = $et - $sStart
                            if ($d.TotalSeconds -gt 0) { $upTimeTotal += $d }
                            $sLastEndTime = $et
                            $sStart = $null
                        } else {
                            $sLastEndTime = $ev.TimeCreated
                        }
                    }
                }

                # If day ended without a proper end event, close with inferred end time
                if ($sStart -and $endTimeForCalc -and $endTimeForCalc -gt $sStart) {
                    $upTimeTotal += ($endTimeForCalc - $sStart)
                }

                if ($upTimeTotal -gt [TimeSpan]::Zero) {
                    $upTimeStr = "{0:hh\:mm}" -f $upTimeTotal
                }
            }

            # --- Build raw/pretty daily row ---
            $startTimeDT = if ($first) { $first.TimeCreated } else { $null }
            $endTimeDT   = $null
            $isInferred  = $false

            if ($dateDT.Date -ne $today.Date) {
                if ($last) {
                    $endTimeDT  = $last.TimeCreated
                    $isInferred = $false
                }
                elseif ($lastEventByDate.ContainsKey($dateDT.Date)) {
                    $endTimeDT  = $lastEventByDate[$dateDT.Date]
                    $isInferred = $true
                }
            }

            # typed totals for Raw
            $overallTS = $null
            if ($startTimeDT -and $endTimeDT -and $endTimeDT -gt $startTimeDT) {
                $overallTS = $endTimeDT - $startTimeDT
            }

            # UpTime total in TimeSpan for Raw (reuse your already-calculated numbers)
            $upTimeTS = $null
            if ($dateDT.Date -ne $today.Date) {
                if ($upTimeTotal -and $upTimeTotal -gt [TimeSpan]::Zero) {
                    $upTimeTS = $upTimeTotal
                }
            }

            if ($Raw) {
                $dailyRows.Add([PSCustomObject]@{
                    PSTypeName      = 'GetWorkTime.Daily.Raw'
                    _SortKey        = $dateDT
                    Day             = $dateDT.ToString('ddd')   # display
                    DayOfWeek       = $dateDT.DayOfWeek         # typed enum
                    DayOfWeekNumber = [int]$dateDT.DayOfWeek    # 0–6
                    Date            = $dateDT.Date
                    StartTime       = $startTimeDT
                    EndTime         = $endTimeDT
                    UpTime          = $upTimeTS
                    Overall         = $overallTS
                    IsInferred      = $isInferred
                }) | Out-Null
            }

            else {
                $dailyRows.Add([PSCustomObject]@{
                    PSTypeName = 'GetWorkTime.Daily'
                    _SortKey   = $dateDT
                    Day        = $dateDT.ToString('ddd')
                    Date       = $dateDT.ToString('d')
                    Start      = if ($first) { $first.TimeCreated.ToString('HH:mm') } else { '-' }
                    End        = $endStr
                    UpTime     = $upTimeStr
                    Overall    = $overallStr
                }) | Out-Null
            }

            continue
        }

        # --- Detailed sessions (when -All is used) ---
        $currentStart = $null
        $lastEndTime  = $null
        $idx = 0

        foreach ($ev in $dayEvents) {
            if ($startEventIds -contains $ev.Id) {
                $startTime = $ev.TimeCreated

                # Merge small gaps as one session
                if ($lastEndTime -and ($startTime - $lastEndTime).TotalMinutes -le $MergeGapMinutes) {
                    continue
                }

                if (-not $currentStart) { $currentStart = $startTime }
                continue
            }

            if ($endEventIds -contains $ev.Id) {
                if ($currentStart) {
                    $endTime = $ev.TimeCreated
                    $upTime  = $endTime - $currentStart

                    if ($upTime.TotalSeconds -gt 0) {
                        $idx++
                        if ($Raw) {
                            $sessionRows.Add([PSCustomObject]@{
                                PSTypeName      = 'GetWorkTime.Session.Raw'
                                _SortKey        = $dateDT
                                Day             = $dateDT.ToString('ddd')
                                DayOfWeek       = $dateDT.DayOfWeek
                                DayOfWeekNumber = [int]$dateDT.DayOfWeek
                                Date            = $dateDT.Date
                                Session         = $idx
                                StartTime       = $currentStart
                                EndTime         = $endTime
                                UpTime          = $upTime
                                IsInferred      = $false
                            }) | Out-Null
                        }
                        else {
                            $sessionRows.Add([PSCustomObject]@{
                                PSTypeName = 'GetWorkTime.Session'
                                _SortKey   = $dateDT
                                Day        = $dateDT.ToString('ddd')
                                Date       = $dateDT.ToString('d')
                                Session    = $idx
                                Start      = $currentStart.ToString('HH:mm')
                                End        = $endTime.ToString('HH:mm')
                                UpTime     = "{0:hh\:mm}" -f $upTime
                            }) | Out-Null
                        }
                        $lastEndTime = $endTime
                    } else {
                        $lastEndTime = $endTime
                    }

                    $currentStart = $null
                } else {
                    $lastEndTime = $ev.TimeCreated
                }
            }
        }

        if ($currentStart) {
            $idx++

            # If the machine crashed, use the last System-log event of that day as end (except today)
            $fallbackEndTime = $null
            if ($dateDT.Date -ne $today.Date) {
                if ($lastEventByDate.ContainsKey($dateDT.Date)) { $fallbackEndTime = $lastEventByDate[$dateDT.Date] }
            }

            if ($fallbackEndTime -and $fallbackEndTime -gt $currentStart) {
                $endTime   = $fallbackEndTime
                $upTime    = $endTime - $currentStart
                $endStr    = $endTime.ToString('HH:mm') + '*'
                $upTimeStr = "{0:hh\:mm}" -f $upTime
            } else {
                $endStr    = '-'
                $upTimeStr = '-'
            }

            if ($Raw) {
                $sessionRows.Add([PSCustomObject]@{
                    PSTypeName      = 'GetWorkTime.Session'
                    _SortKey        = $dateDT
                    Day             = $dateDT.ToString('ddd')
                    DayOfWeek       = $dateDT.DayOfWeek
                    DayOfWeekNumber = [int]$dateDT.DayOfWeek
                    Date            = $dateDT.Date
                    Session         = $idx
                    StartTime       = $currentStart
                    EndTime         = if ($fallbackEndTime -and $fallbackEndTime -gt $currentStart) { $fallbackEndTime } else { $null }
                    UpTime          = if ($fallbackEndTime -and $fallbackEndTime -gt $currentStart) { ($fallbackEndTime - $currentStart) } else { $null }
                    IsInferred      = [bool]($fallbackEndTime -and $fallbackEndTime -gt $currentStart)
                }) | Out-Null
            }

            else {
                $sessionRows.Add([PSCustomObject]@{
                    PSTypeName = 'GetWorkTime.Session'
                    _SortKey   = $dateDT
                    Day        = $dateDT.ToString('ddd')
                    Date       = $dateDT.ToString('d')
                    Session    = $idx
                    Start      = $currentStart.ToString('HH:mm')
                    End        = $endStr
                    UpTime     = $upTimeStr
                }) | Out-Null
            }
           

        }
    }

    # ---- Output ----
    if ($All) {
        if ($Raw) {
            $sessionRows |
                Sort-Object _SortKey, Session |
                Select-Object Day, DayOfWeek, DayOfWeekNumber, Date, Session, StartTime, EndTime, UpTime, IsInferred
        } else {
            $sessionRows | Sort-Object _SortKey, Session
        }
    }
    else {
        if ($Raw) {
            $dailyRows |
                Sort-Object _SortKey |
                Select-Object Day, DayOfWeek, DayOfWeekNumber, Date, StartTime, EndTime, UpTime, Overall, IsInferred
        } else {
            $dailyRows | Sort-Object _SortKey
        }
    }




    $inferredNote = '* = inferred from last System log event (e.g. after crash)'
    if ($Raw) {
        $hasInferred =
            ($dailyRows   -and ($dailyRows   | Where-Object { $_.IsInferred } | Select-Object -First 1)) -or
            ($sessionRows -and ($sessionRows | Where-Object { $_.IsInferred } | Select-Object -First 1))
    }
    else {
        $hasInferred =
            ($dailyRows   -and ($dailyRows   | Where-Object { $_.End -match '\*' } | Select-Object -First 1)) -or
            ($sessionRows -and ($sessionRows | Where-Object { $_.End -match '\*' } | Select-Object -First 1))
    }



    if ($hasInferred) {
        Write-Verbose $inferredNote
    }
}

Export-ModuleMember -Function Get-WorkTime
