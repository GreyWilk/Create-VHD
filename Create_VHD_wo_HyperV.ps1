####
# 
# Create VHD (without Hyper-V installed) and attaches it.
# VHD is created on the local fixed drive with most vailable free space.
# 
####

$UsableVolumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -eq "Fixed" }
$MostFreeSpaceVolume = $UsableVolumes | Sort-Object SizeRemaining -Descending | Select-Object -First 1
$Date = (Get-Date -Format 'yyyy-MM-dd')

## Create diskpart tasks
$DiskPartCommandsFileName = "DISKPART_CMD_$(get-date -format 'yyyy-MM-dd').txt"
$DiskPartCommands = @"
create vdisk file=$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd maximum=2048000 type=expandable
select vdisk file=$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd
attach vdisk
"@

$DiskPartCommands | Out-File "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName" -Encoding ascii

## Execute DISKPART commands
DISKPART /s "$($MostFreeSpaceVolume.DriveLetter):\$DiskPartCommandsFileName" >> "$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.log"

$InitializedDisk = Initialize-Disk -UniqueId (Get-Disk | Where-Object { $_.Location -eq "$($MostFreeSpaceVolume.DriveLetter):\VHD_$Date.vhd" }).UniqueId -PassThru

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

## Create huge file on vdisk for fun
# [io.file]::Create("$($DriveLetterToUse):\bigblob.txt").SetLength((Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$($DriveLetterToUse):'").FreeSpace - 200MB).Close
