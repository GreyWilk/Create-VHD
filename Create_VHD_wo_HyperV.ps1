[CmdletBinding(SupportsShouldProcess)]
param (
    [int][validateset("2","5","10","50","100","250","500")]$VHDSizeInGB,
    [bool]$AttachVHDToLocalComputer = $false
)

####
# 
# Create VHD (without Hyper-V installed) and attaches it.
# VHD is created on the local fixed drive with most vailable free space.
# 
####

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

## Create diskpart tasks
$DiskPartCommandsFileName = "DISKPART_CMD_$(get-date -format 'yyyy-MM-dd').txt"

if( $AttachVHDToLocalComputer -eq $false ) {
$DiskPartCommands = @"
create vdisk file=$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd maximum=$($VHDSizeInGB*1024) type=expandable
"@
} else {
$DiskPartCommands = @"
create vdisk file=$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd maximum=$($VHDSizeInGB*1024) type=expandable
select vdisk file=$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd
attach vdisk
"@
}

$DiskPartCommands | Out-File "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName" -Encoding ascii

## Execute DISKPART commands
DISKPART /s "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName" >> "$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.log"

if( $AttachVHDToLocalComputer -eq $true ) {
    Start-Sleep 2
    $DiskInfo = (Get-Disk | Where-Object { $_.Location -eq "$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd" })
    Write-Host "UniqueID of disk is: $([string]$DiskInfo.UniqueId)"
    $InitializedDisk = Initialize-Disk -UniqueId $([string]$DiskInfo.UniqueId) -PassThru

    ## Find first unused drive letter
    $DriveLetterToUse = $null
    $UsedDriveLetters = ((Get-Volume | Select-Object DriveLetter).DriveLetter)
    68..90 | ForEach-Object {
        If ($UsedDriveLetters -notcontains [char]$PSItem) {
            $DriveLetterToUse = [char]$PSItem
            break
        }
    }
    
    ## Create new partition and format VHD to NTFS
    $NewPartition = New-Partition -InputObject $InitializedDisk -UseMaximumSize -DriveLetter $DriveLetterToUse
    Format-Volume -DriveLetter $($NewPartition.DriveLetter) | Out-Null
    Set-Volume -DriveLetter $($NewPartition.DriveLetter) -NewFileSystemLabel "vDisk_$DriveLetterToUse"
}
