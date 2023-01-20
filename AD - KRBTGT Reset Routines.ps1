##### JPS ####

<#

NOTE: Extensionattribute10 must be set to Enable along with ExtensionAttribute14 set to 0 (ZERO)
initially in order to kick off rolling restarts, this will be changed in puppet.

#>

### Logging Function ###
[string]$LogPath = "C:\ProgramData\Scripts\KRBTGTResetAutomation" #Path to store the Lofgile
[string]$LogfileName = "KRBTGTResetAutomation" #FileName of the Logfile, no extension.
[int]$DeleteAfterDays = 365 #Time Period in Days when older Files will be deleted

function Write-logging {
    [CmdletBinding()]
    param
    (
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string]$Type,
        [string]$Text
    )

    write-host $Type $Text

    # Set logging path
    if (!(Test-Path -Path $logPath)) {
        try {
            $null = New-Item -Path $logPath -ItemType Directory
            Write-Verbose ("Path: ""{0}"" was created." -f $logPath)
            }
        catch {
            Write-Verbose ("Path: ""{0}"" couldn't be created." -f $logPath)
            }
    }
    else {
        Write-Verbose ("Path: ""{0}"" already exists." -f $logPath)
        }

    #[string]$logFile = $logPath + "\" + $LogfileName + ".log"
    [string]$logFile = '{0}\{1}_{2}.log' -f $logPath, $(Get-Date -Format 'ddMMyyyy'), $LogfileName
    $logEntry = '{0}: <{1}> {2}' -f $(Get-Date -Format MM.dd.yyyy-HH:mm:ss), $Type, $Text
    Add-Content -Path $logFile -Value $logEntry
}


### Import AD PS

try 
    {
    Import-Module -Name ActiveDirectory
    }

catch
    {
    
    if (!(((Get-WindowsFeature RSAT-AD-PowerShell).installed) -eq "True"))
        {
        Import-Module ServerManager 
        Add-WindowsFeature -Name "RSAT-AD-PowerShell" –IncludeAllSubFeature
        }
    Import-Module activedirectory
    }


#### DOMAIN KRBTGT DETAILS
$account = "krbtgt"
$KRBTGTattribs = get-aduser $account -Properties *
$env:userdnsdomain

<#
extensionAttribute10                 : (Enabled/Disabled)
extensionAttribute11                 : 180 (Min day from last pwdlastset frequency)
extensionAttribute12                 : 180123 (Reset1st reset date)
extensionAttribute13                 : 180823 (Reset2nd reset date)
extensionAttribute14                 : 0 ([0], Ready to Evaluate for 1st Reset | [1], 1st Reset Completed | [2], 2nd Reset Completed)
#>

[string]$ResetConfig = $KRBTGTattribs.extensionAttribute10
[int]$ResetInt = $KRBTGTattribs.extensionAttribute11
[string]$Reset1st = $KRBTGTattribs.extensionAttribute12
[string]$Reset2nd = $KRBTGTattribs.extensionAttribute13
[int]$ResetStatus = $KRBTGTattribs.extensionAttribute14
$pwdlastset = $KRBTGTattribs.PasswordLastSet
$ResetDate = ($KRBTGTattribs.PasswordLastSet).AddDays(+$ResetInt)
$Reset2ndDate = ($KRBTGTattribs.PasswordLastSet).AddDays(+7)
$pwdlastsetshort = $KRBTGTattribs.PasswordLastSet.ToString("MMddyy")

### Starting log
Write-logging -Type DEBUG -Text "Task Scheduled Execution"
Write-logging -Type INFO -Text "Domain = $env:userdnsdomain"
Write-logging -Type INFO -Text "PwdLastSet = $pwdlastset"
Write-logging -Type INFO -Text "ResetConfig = $ResetConfig"
Write-logging -Type INFO -Text "ResetInterval = $ResetInt"
Write-logging -Type INFO -Text "Reset1st = $Reset1st"
Write-logging -Type INFO -Text "Reset2nd = $Reset2nd"
Write-logging -Type INFO -Text "ResetStatus (0, Ready | 1, 1st completed | 2, completed) = $ResetStatus"
Write-logging -Type INFO -Text "If Enabled, Next reset available after $ResetDate when ResultStatus = 0"


#### If Disabled, exit 0 ####
if ($KRBTGTattribs.extensionAttribute10 -eq "Disabled")
    {
    Write-logging -Type WARNING -Text "Reset Disabled"
    }

### If Enabled ###

if ($KRBTGTattribs.extensionAttribute10 -eq "Enabled")
    {
    #### Starting First Reset Eval

    <#
    1. Verifies if Pwdlastset is older than calcualted ResetInt date
    2. ResetStatus = 0
    3. No Replication Errors
    4. Run krbtgt password reset
    5. Verify Success against pwdlastset attribute
    6. Set Reset1st date (extensionAttribute12), (MMddyy)
    7. Set ResultStatus to 1 (extensionAttribute14)
    #>

    
    # Calc Reset Date, Lastreset + $ResetInt
    Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] Starting Evaluation of 1st Reset"
    if ($pwdlastset -gt $ResetDate)
        {
        write-host "$pwdlastset -lt $ResetDate"
        Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] krbtgt pwdlastrest $pwdlastset , gt $ResetDate with interval of $ResetInt"
        Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] krbtgt pwdlastrest passes last ad reset interval check"

        if ($ResetStatus -eq 0)
            {
            write-host "$ResetStatus -eq 0"
            Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] Reset Status = $ResetStatus , Reset Status requirements met for first reset"
            
            # Verify successsful AD replication logs
            if (!(Get-ADReplicationFailure -Scope Domain))
                {
                
                Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] AD Domain Replication Failure Check Passed"
                Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] PASSED ALL FIRST RESET PRE-REQS: Replication, Reset Inverval vs pwdlastset, ResetStatus = 0"

                # Run script here for first pass
                Write-logging -Type WARNING -Text "[RESET 1st EVAL] Executing First Reset..."
                
                # Real Execuation for one time reset
                C:\ProgramData\Scripts\KRBTGTReset\Reset-KrbTgt-Password-For-RWDCs-And-RODCs.ps1 -noInfo -modeOfOperation resetModeKrbTgtProdAccountsResetOnce -targetedADforestFQDN $env:userdnsdomain -targetedADdomainFQDN $env:userdnsdomain -targetKrbTgtAccountScope allRWDCs -continueOps
                
                # Canary Sumulation
                #C:\ProgramData\Scripts\KRBTGTReset\Reset-KrbTgt-Password-For-RWDCs-And-RODCs.ps1 -noInfo -modeOfOperation simulModeCanaryObject -targetedADforestFQDN $env:userdnsdomain -targetedADdomainFQDN $env:userdnsdomain -targetKrbTgtAccountScope allRWDCs -continueOps

                # Verify completion with pwdlastset dates, requery AD account.
                # Compares the date only, not time. 
                [String]$date = get-date -Format "MMddyy"
                $KRBTGTattribspost = get-aduser $account -Properties *
                if ($KRBTGTattribspost.PasswordLastSet.ToString("MMddyy") -eq $date)
                    {
                    # Set extensionAttribute14 to 1 for 1st reset completion.
                    write-host $KRBTGTattribspost.PasswordLastSet.ToString("MMddyy") + " matches today's date for first reset... $date"
                                       
                    Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] First Reset completed Successfully, applying 1 to extensionAttribute14 for ResetStatus"

                    IF (!($KRBTGTattribspost.extensionAttribute14)) 
                        {Set-ADUser -Identity $account -Add @{extensionAttribute14=1}}
                    ELSE 
                        {Set-ADUser -Identity $account -Replace @{extensionAttribute14=1} -Verbose}

                    $KRBTGTattrib14 = get-aduser $account -Properties extensionAttribute14 | Select-Object -ExpandProperty extensionAttribute14
                    Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] ResetStatus, extensionAttribute14 now set to $KRBTGTattrib14"
                    
                    # Add Today's Date to Last1stReset, extensionAttribute12
                    Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] First Reset completed Successfully, applying $date to extensionAttribute12 for Reset1st"
                    
                    if (!($KRBTGTattribspost.extensionAttribute12)) 
                        {Set-ADUser -Identity $account -add @{extensionAttribute12=$date} -Verbose} 
                    Else 
                        {Set-ADUser -Identity $account -Replace @{extensionAttribute12=$date} -Verbose}
                        
                    $KRBTGTattrib12 = get-aduser $account -Properties extensionAttribute12 | Select-Object -ExpandProperty extensionAttribute12
                    Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] Reset1st, extensionAttribute12 now set to $KRBTGTattrib12"

                    # End Verification and setting ResetStatus + Last1stReset
                    }
                ELSE
                    {
                    Write-logging -Type ERROR -Text "[RESET 1st EVAL] First Reset completed Successfully, but pwdlastset does not match today's date. Extattrib14 not set to 1"
                    }

                # End replication check
                }
            ELSE
                {
                # Failed replication check
                Write-logging -TYPE WARNING -Text "[RESET 1st EVAL] AD Domain Replication Failure Check Failed, aborting first Reset. Get-ADReplicationFailure -Scope Domain"
                }

            # End if resetstatus -eq 0
            }
        ELSE
            {
            # Failed Reset Status Check
            Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] Reset Status = $ResetStatus , failed to qualify for first reset. status ne 0"
            }

        # End pwdlastset vs resetinterval check
        }
    ELSE
        {
        # Failed account pwdlastset vs resetintveral check
        Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] krbtgt pwdlastrest $pwdlastset , lt qualifying reset date of $ResetDate"
        Write-logging -TYPE DEBUG -Text "[RESET 1st EVAL] krbtgt pwdlastrest failed last ad reset interval check"
        }

    ### END First Reset


    


    ### Starting Second Reset Eval
    
    <#
    1. ResetStatus must = 1, signifing first reset completed.
    2. Reset1st = PwdLastSet, if they match that mean no manual adjustments outside of this script have been made.
    3. Verify No Replication Errors exist.
    4. Run krbtgt password reset.
    5. Verify Success against pwdlastset attribute.
    6. Set Reset2nd date (extensionAttribute13), (MMddyy).
    7. Set ResultStatus to 2 (extensionAttribute14), signifies 2nd reset completed successfully.
    #>

    # Requerying Properties of $account for second eval.
    $KRBTGTattribs = get-aduser $account -Properties *

    [string]$ResetConfig = $KRBTGTattribs.extensionAttribute10
    [int]$ResetInt = $KRBTGTattribs.extensionAttribute11
    [string]$Reset1st = $KRBTGTattribs.extensionAttribute12
    [string]$Reset2nd = $KRBTGTattribs.extensionAttribute13
    [int]$ResetStatus = $KRBTGTattribs.extensionAttribute14
    $pwdlastset = $KRBTGTattribs.PasswordLastSet
    $ResetDate = ($KRBTGTattribs.PasswordLastSet).AddDays(+$ResetInt)
    $Reset2ndDate = ($KRBTGTattribs.PasswordLastSet).AddDays(-7)
    $pwdlastsetshort = $KRBTGTattribs.PasswordLastSet.ToString("MMddyy")

    Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] Starting Evaluation of 2nd Reset"

    if ($ResetStatus -eq 1)
        {
        
        # If pwdlastset matches Reset1st continue
        if ($pwdlastsetshort -eq $Reset1st)
            {
            
            # If today's date is 7 days later than 1st reset date continue
            if ($pwdlastset -lt $Reset2ndDate)
                {
                Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] krbtgt pwdlastrest $pwdlastset , gt $Reset2ndDate (7 days older) qualifying for Second Reset"

                # verify successsful AD replication logs
                if (!(Get-ADReplicationFailure -Scope Domain))
                    {
                
                    Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] AD Domain Replication Failure Check Passed"
                    Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] PASSED ALL Second RESET PRE-REQS: Replication, Reset1st = Pwdlastset, ResetStatus = 1"

                    # Run script here for second pass
                    Write-logging -Type WARNING -Text "[RESET 2nd EVAL] Executing First Reset..."

                    # Real Execuation for one time reset
                    C:\ProgramData\Scripts\KRBTGTReset\Reset-KrbTgt-Password-For-RWDCs-And-RODCs.ps1 -noInfo -modeOfOperation resetModeKrbTgtProdAccountsResetOnce -targetedADforestFQDN $env:userdnsdomain -targetedADdomainFQDN $env:userdnsdomain -targetKrbTgtAccountScope allRWDCs -continueOps
                
                    # Canary Sumulation
                    #C:\ProgramData\Scripts\KRBTGTReset\Reset-KrbTgt-Password-For-RWDCs-And-RODCs.ps1 -noInfo -modeOfOperation simulModeCanaryObject -targetedADforestFQDN $env:userdnsdomain -targetedADdomainFQDN $env:userdnsdomain -targetKrbTgtAccountScope allRWDCs -continueOps


                    [String]$date = get-date -Format "MMddyy"
                    $KRBTGTattribspost = get-aduser $account -Properties *
                    if ($KRBTGTattribspost.PasswordLastSet.ToString("MMddyy") -eq $date)
                        {
                        # Set extensionAttribute14 to 2 for 2nd reset completion.
                        write-host $KRBTGTattribspost.PasswordLastSet.ToString("MMddyy") + " matches today's date for 2nd reset... $date"
                                       
                        Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] Second Reset completed Successfully, applying 2 to extensionAttribute14 for ResetStatus"

                        Set-ADUser -Identity $account -Replace @{extensionAttribute14=2} -Verbose

                        $KRBTGTattrib14 = get-aduser $account -Properties extensionAttribute14 | Select-Object -ExpandProperty extensionAttribute14
                        Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] ResetStatus, extensionAttribute14 now set to $KRBTGTattrib14"
                    
                        # Add Today's Date to Reset2nd, extensionAttribute13
                        Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] Second Reset completed Successfully, applying $date to extensionAttribute13 for Reset2nd"
                    
                        Set-ADUser -Identity $account -Replace @{extensionAttribute13=$date} -Verbose
                        
                        $KRBTGTattrib13 = get-aduser $account -Properties extensionAttribute13 | Select-Object -ExpandProperty extensionAttribute12
                        Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] Reset2nd, extensionAttribute13 now set to $KRBTGTattrib13"

                        # End Verification and setting ResetStatus + Reset2nd
                        }
                    ELSE
                        {
                        Write-logging -Type ERROR -Text "[RESET 2nd EVAL] Second Reset completed Successfully, but pwdlastset does not match today's date. Extattrib14 not set to 2"
                        }
                    }
                ELSE
                    {
                    Write-logging -TYPE WARNING -Text "[RESET 2nd EVAL] AD Domain Replication Failure Check Failed, aborting Second Reset. Get-ADReplicationFailure -Scope Domain"
                    }
                
                # End verifying pwdlastset gt 7 days from today
                }
            ELSE
                {
                Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] krbtgt pwdlastrest $pwdlastset , not lt than $Reset2ndDate (7 days old), does not qualify for Second Reset"
                }

            # End pwd matching Reset1st
            }
        ELSE
            {
            Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] PwdLastSet $pwdlastsetshort does not match Reset1st date of $Reset1st , signals tampering - aborting"
            }

        # End if Resetstatus = 1
        }
    ELSE
        {
        Write-logging -TYPE DEBUG -Text "[RESET 2nd EVAL] ResetStatus = $ResetStatus , skipping 2nd Reset"
        }

    
    ### Starting ResetInt Cleanup ###
    # Meant to resolve issues with manual resets or tampering. After the correct amount of days have expired since pwdlastset, ResetInt (extensionAttribute11)
    # Resetting ResetStatus (extensionAttribute14) to 0 will qualify it to eval 1st reset on next script execution.

    <#
    1. Verifies ResetStatus -ne 0
    2. pwdlastset -lt (today - ResultInt(days), (extensionAttribute11)), pwdlastset attribute on krbtgt must be greater than the min calculated date next reset is applicable.
    3. Set ResetStatus 0, (extensionAttribute14)
    #>
    
    Write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] If ResetStatus -ne 0 eval resetting to zero, ResetStatus = $ResetStatus currently"
    If ($ResetStatus -ne 0)
        {
        
        Write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] Evalulating if ResetStatus should be reset to 0 to resolve issues with manual resets or tampering"
        # Only reset to 0 if pwdlastset exceeds the calcued reset date using ResetInt
        if ($pwdlastset -gt $ResetDate)
            {
            write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] pwdlastset $pwdlastset must be gt $ResetDate to avoid any conflicts with resetting"
            Write-logging -Type WARNING -Text "[RESETSTATUS EVAL] pwdlastset $pwdlastset gt calcualted $ResetDate with ResetInt of $ResetInt, ResetResult will be reset to 0"
            
            IF (!($KRBTGTattribs.extensionAttribute14)) 
                {Set-ADUser -Identity $account -Add @{extensionAttribute14=0} -Verbose}
            ELSE 
                {Set-ADUser -Identity $account -Replace @{extensionAttribute14=0} -Verbose}
            
            $KRBTGTattrib14 = get-aduser $account -Properties extensionAttribute14 | Select-Object -ExpandProperty extensionAttribute14
            Write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] ResetStatus, extensionAttribute14 now set to $KRBTGTattrib14"
            
            # End If pwdlastset exceeds the ResetInt date
            }
        else
            {
            Write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] pwdlastset $pwdlastset must gt the $ResetDate to avoid any conflicts with resetting"
            Write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] pwdlastset $pwdlastset lt calculated reset date of $ResetDate with ResetInt of $ResetInt, ResetResult will NOT be reset"
            }
        
        # End if Resetstats ne 0
        }
    ELSE
        {
        Write-logging -TYPE DEBUG -Text "[RESETSTATUS EVAL] Skipping ResetStatus eval, ResetStatus already = $ResetStatus , ZERO"
        }
    
    
        ### End If Enabled 
    }
    


# Clean Logs
$limit=(Get-Date).AddDays(-$DeleteAfterDays)
$expired = Get-ChildItem -Path $LogPath -Filter "*$LogfileName.log" | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit }
if ($expired)
    {
    Write-logging -TYPE DEBUG -Text "Clean Log Files < $limit"
    Get-ChildItem -Path $LogPath -Filter "*$LogfileName.log" | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit } | Remove-Item -Force -Verbose
    }