[CmdletBinding(SupportsShouldProcess)]
param (
    [int][validateset("2","5","10","50","100","250","500")]$VHDSizeInGB,
    [bool]$AttachVHDToLocalComputer = $false,
    [switch]$RunCleanup
)

####
# 
# Create VHD (without Hyper-V installed) and attaches it.
# VHD is created on the local fixed drive with most vailable free space.
# 
####

function Write-timeLog {
    param(
        [parameter(Mandatory=$true)]$logText,
        [parameter(Mandatory=$false)][validateSet('Cyan','Yellow','Red','Green','Gray')]$logColor,
        [parameter(Mandatory=$false)][validateSet('Info','Warning','Error','Debug')]$logType
    )
    $logOutput = $null
    $logOutput += "[$(Get-Date -Format 'HH:mm:ss')] "

    if( -not $logColor -and -not $logType ){
        $logColor = "Cyan"
        $logTypeString = "[INFO] "
    } elseif( -not $logColor -and $logType ){
        switch( $logType ){
            'Info'      { $logTypeString = "[INFO] "; $logColor = "Cyan" }
            'Warning'   { $logTypeString = "[WRNG] "; $logColor = "Yellow" }
            'Error'     { $logTypeString = "[ERR]  "; $logColor = "Red" }
            'Debug'     { $logTypeString = "[DBG]  "; $logColor = "Gray" }
            default     { $logTypeString = "[INFO] "; $logColor = "White" }
        }
    } else {
        switch( $logType ){
            'Info'      { $logTypeString = "[INFO] " }
            'Warning'   { $logTypeString = "[WRNG] " }
            'Error'     { $logTypeString = "[ERR]  " }
            'Debug'     { $logTypeString = "[DBG]  " }
            default     { $logTypeString = "[INFO] " }
        }
    }

    $logOutput += $logTypeString
    $logOutput += $logText
    Write-Host -ForegroundColor $logColor -Object $logOutput
}

try{
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())


    If ( -not $(Get-Item C:\windows\system32\diskpart.exe -ErrorAction SilentlyContinue) ){
        Throw "Unable to locate DISKPART @ location c:\windows\system32\ !"
    }
    If ( -not $($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) ){
        Throw "Script not running as Admin!"
    }

    $UsableVolumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq "Fixed" }
    $MostFreeSpaceVolume = $UsableVolumes | Sort-Object SizeRemaining -Descending | Select-Object -First 1
    $Date = (Get-Date -Format 'yyyy-MM-dd')
    $GUID = (New-Guid).Guid.Substring(0,8)
    $VHDName = ("VHD_" + $Date + "_" + $GUID)

    ## Create diskpart tasks
    $DiskPartCommandsFileName = "DISKPART_CMD_$(get-date -format 'yyyy-MM-dd')_$GUID.txt"
    $DiskPartCommandsFile = New-Item -ItemType File -Path "$($MostFreeSpaceVolume.DriveLetter):\" -Name $DiskPartCommandsFileName

    if( $AttachVHDToLocalComputer -eq $false ) {
        Write-timeLog  -logType Debug -logText "Creating run file for DISKPART (no attach)."
        "create vdisk file=$($MostFreeSpaceVolume.DriveLetter):\$VHDName.vhd maximum=$($VHDSizeInGB*1024) type=expandable" | Out-File -FilePath $DiskPartCommandsFile.FullName -Encoding ascii -Append
    } else {
        Write-timeLog  -logType Debug -logText "Creating run file for DISKPART (with attach)."
        "create vdisk file=$($MostFreeSpaceVolume.DriveLetter):\$VHDName.vhd maximum=$($VHDSizeInGB*1024) type=expandable" | Out-File -FilePath $DiskPartCommandsFile.FullName -Encoding ascii -Append
        "select vdisk file=$($MostFreeSpaceVolume.DriveLetter):\$VHDName.vhd" | Out-File -FilePath $DiskPartCommandsFile.FullName -Encoding ascii -Append
        "attach vdisk" | Out-File -FilePath $DiskPartCommandsFile.FullName -Encoding ascii -Append
    }

    #$DiskPartCommands | Out-File "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName" -Encoding ascii

    ## Execute DISKPART commands
    Write-timeLog  -logType Debug -logText "Running DISKPART."
    DISKPART /s "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName" >> "$($MostFreeSpaceVolume.DriveLetter):\$VHDName.log"

    if( $AttachVHDToLocalComputer -eq $true ) {
        $DiskInfo = (Get-Disk | Where-Object { $_.Location -eq "$($MostFreeSpaceVolume.DriveLetter):\$VHDName.vhd" })
        Write-timeLog -logType Debug -logText "UniqueID of disk is: $([string]$DiskInfo.UniqueId)"
        Write-timeLog -logType Debug -logText "Initializing disk..."
        $InitializedDisk = Initialize-Disk -UniqueId $([string]$DiskInfo.UniqueId) -PassThru
        If( $InitializedDisk ) {
            Write-timeLog -logType Debug -logText "Initializing disk completed."

            ## Find first unused drive letter
            $DriveLetterToUse = $null
            $UsedDriveLetters = ((Get-Volume | Select-Object DriveLetter).DriveLetter)
            68..90 | ForEach-Object {
                If ($UsedDriveLetters -notcontains [char]$PSItem -and $DriveLetterToUse -eq $null) {
                    $DriveLetterToUse = [char]$PSItem
                }
            }
            
            ## Create new partition and format VHD to NTFS
            Write-timeLog -logType Debug -logText "Creating partition."
            $NewPartition = New-Partition -InputObject $InitializedDisk -UseMaximumSize -DriveLetter $DriveLetterToUse
            Format-Volume -DriveLetter $($NewPartition.DriveLetter) | Out-Null
            Set-Volume -DriveLetter $($NewPartition.DriveLetter) -NewFileSystemLabel "vDisk_$DriveLetterToUse"

        } else {
            Write-timeLog -logType Debug -logText "Failed to initalize disk"
        }

        
    }

    if( $RunCleanup ) {
        Write-timeLog -logType Debug -logText "Running cleanup!"
        Write-timeLog -logType Debug -logText "Removing DISKPART command file."
        Remove-Item -Path "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName"
        Write-timeLog -logType Debug -logText "Removing VHD create log."
        Remove-Item -Path "$($MostFreeSpaceVolume.DriveLetter):\$VHDName.log"
    }
} catch {
    Write-timeLog -logType Error -logText "Error creating VHD."
    Write-timeLog -logType Error -logText  $error[0].Exception
    Write-timeLog -logType Error -logText  $error[0].InvocationInfo.PositionMessage
    $Error.remove($Error[0])
    }
## Create huge file on vdisk for fun
# [io.file]::Create("$($DriveLetterToUse):\bigblob.txt").SetLength((Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$($DriveLetterToUse):'").FreeSpace - 200MB).Close
