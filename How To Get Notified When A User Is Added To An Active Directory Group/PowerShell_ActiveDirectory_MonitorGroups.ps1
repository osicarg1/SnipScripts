#region demo
Throw "This is a demo, dummy!"
#endregion

#region clean
Function Prompt(){}
Clear-Host
#endregion

#region Grabbing memberships of a group

$group = 'Domain Users'

#Retrieve group memberships
Get-ADGroupMember $group | Format-Table Name

#Convert to a savable object
$CurrentMemberships = @()
ForEach($member in Get-ADGroupMember $group){
    $CurrentMemberships += [pscustomobject]@{
        GroupName = $group
        Member = $member.SamAccountName
    }
}

#Export to CSV
$CSVPath = 'C:\Users\techsnips\Desktop\ADGroupMemberships.csv'
$CurrentMemberships | Export-Csv $CSVPath -NoTypeInformation -Force
. $CSVPath

#endregion

#region Comparing memberships

#Import CSV from before
$PreviousMemberships = Import-Csv $CSVPath

#Create user to test comparison
New-ADUser MembershipTest

#Build similar object
$CurrentMemberships = @()
ForEach($member in Get-ADGroupMember $group){
    $CurrentMemberships += [pscustomobject]@{
        GroupName = $group
        Member = $member.SamAccountName
    }
}

#Check for members that were removed
ForEach($previousMember in $previousMemberships){
    If($CurrentMemberships.Member -notContains $previousMember.Member){
        Write-Host "$($previousMember.Member) was removed."
    }
}

#Check for members that were added
ForEach($currentMember in $currentMemberships){
    If($PreviousMemberships.Member -notcontains $currentMember.Member){
        Write-Host "$($currentMember.Member) was added."
    }
}

#endregion

#region Make it a reusable function

Function Compare-ADGroupMemberships {
    [cmdletbinding()]
    Param(
        [Parameter(
            Mandatory = $true
        )]
        [string[]]$GroupNames
        ,
        [Parameter(
            Mandatory = $true
        )]
        [string]$CSVPath
        ,
        [bool]$RemoveUnusedPreviousGroups = $true
        ,
        [string]$EmailRecipient
        ,
        [string]$SMTPServer = ''
    )
    Begin{
        #Variables
        $EmailString = ""
        $SkippedGroupMemberships = @()

        #Import previous memberships
        $AllPreviousMemberships = Import-Csv $CSVPath

        #Store all groups from previous memberships
        $PreviousGroups = $AllPreviousMemberships.GroupName | Select-Object -Unique

        #If we are going to remove previous groups
        ForEach($group in $PreviousGroups){
            If($GroupNames -notcontains $group){
                If($RemoveUnusedPreviousGroups){
                    #remove $group from $previousMemberships
                    Write-Verbose "Removing $group from csv file"
                    $AllPreviousMemberships = $AllPreviousMemberships | Where-Object GroupName -ne $group
                }Else{
                    #save it for later
                    Write-Verbose "$group was not in parameter GroupNames"
                    $SkippedGroupMemberships += $AllPreviousMemberships | Where-Object GroupName -eq $group
                }
            }
        }
    }
    Process{
        $AllCurrentMemberships = @()
        #Main foreach
        ForEach($group in $GroupNames){
            $CurrentMemberships = @()
            If($PreviousGroups -notcontains $group){
                #Nothing to compare
                Write-Verbose "No historical data for $group."
                ForEach($member in Get-ADGroupMember $group){
                    $CurrentMemberships += [pscustomobject]@{
                        GroupName = $group
                        Member = $member.SamAccountName
                    }
                }
            }Else{
                #Stuff to compare!
                Write-Verbose "Comparing memberships for $group."
                ForEach($member in Get-ADGroupMember $group){
                    $CurrentMemberships += [pscustomobject]@{
                        GroupName = $group
                        Member = $member.SamAccountName
                    }
                }

                $previousMemberships = $AllPreviousMemberships | Where-Object GroupName -eq $group

                #Check for members that were removed
                ForEach($previousMember in $previousMemberships){
                    If($CurrentMemberships.Member -notContains $previousMember.Member){
                        Write-Verbose "$($previousMember.Member) was removed."
                        $emailString += "$($previousMember.Member) was removed from $group.`n"
                    }
                }

                #Check for members that were added
                ForEach($currentMember in $currentMemberships){
                    If($previousMemberships.Member -notcontains $currentMember.Member){
                        Write-Verbose "$($currentMember.Member) was added."
                        $emailString += "$($currentMember.Member) was added to $group.`n"
                    }
                }
            }
            #build our object to export
            $AllCurrentMemberships += $CurrentMemberships
        }
    }
    End{
        #Email
        If($emailString){
            $EmailSplat = @{
                SMTPServer = $SMTPServer
                From = (Get-ADUser $env:UserName -Properties EmailAddress).EmailAddress
                To = $EmailRecipient
                Body = $emailString
                Subject = 'AD Group Monitoring Report'
            }
            #Send-MailMessage @EmailSplat
        }
        Write-Verbose $emailString
        If(!($RemoveUnusedPreviousGroups)){
            $AllCurrentMemberships = $AllCurrentMemberships + $SkippedGroupMemberships
        }
        $AllCurrentMemberships | Export-Csv $CSVPath -NoTypeInformation -Force
    }
}

#endregion