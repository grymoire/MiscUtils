# Backup Folders - Bruce Barnett
# inspirations from 
# michael@techguy.at
# This PowerShell script first examines a timeestamp file in a backup directory, and then examines a set of folders, 
# and if any file in those folders were updated since that timestamp file was updated, that new file is backed up onto the backup folder.

# Note that if you have multiple backp drives, each drive will have a unique timestamp, and you can backup to a number of drives, making copies of all new filees into all drives.
# You can have a personal drive for backups as well.

# Changes
# Include hidden folders
# SKip around folders like MY DOcuments. My Music (i.e. Juntion points)
# Copied from TDrive
# 
# 4/20/2016 - add code to detect current folder without having to hard-code it in script. Renamed Varable TopDirecotory to Directory


#System Variable for backup Procedure

# Where to look for new files to backup
# $src = ("C:\Users\Security\Desktop\", "C:\Users\Security\Documents\", "C:\ProgramData\HP\HP WebInspect\" )
$src = ("C:\Users\BBarnett\Desktop\", "C:\Users\BBarnett\Documents\", "C:\mybin\") 

$UUID=(get-wmiobject Win32_ComputerSystemProduct).UUID 

#We have to put all functions up in front of the main code because PowerShell doesn;t have a 2-pass parser. Reminds me of the C-Shell
# Parse Configuration file
function ParseConfig([string]$filename) {
	try {
		$file = Get-Item -Path $filename 
		if ($file.Exists) {
			$cfg = ( Get-Content  -Path $filename )
			return $cfg
		} else {
			Write-Host "Warning: The configuration file "$filename" does not exist" -ForegroundColor Yellow
		}
	}
	catch {
		Write-Host "Warning - Cannot load configuration file "$filename -ForegroundColor Red
	}
	return $null
}




# Where to backup the  files
# I used to use a hardcoded path
#$parent = "D:\BackupsByMachine\Bruce_Windows"
# I now use one of these methods
#$parent = (Get-Item -Path ".\" -Verbose).FullName
$invocation = (Get-Variable MyInvocation).Value
$parent = Split-Path $invocation.MyCommand.Path
$settings=$parent + "/config.txt"

$HowFarBack=-30 # How far back do I want to backfg up. 
$HowFarBackFull=-365 # If I ask for a full backup - how far back do I go.

 
 echo "This Computer is $UUID"
 echo "---"

 # echo "settings: $settings"
 $cfg = ParseConfig "$settings"
 


Get-Content $settings | Select-String -pattern $UUID -simplematch | ForEach-Object {
    Write-Host "Line:", $_
}
 echo "good to go?"
exit

$intro_message = @("This powershell script will perform a backup of a system.")
$intro_message+="The following boxes have a special meaning:"
$intro_message+="ABORT: - Cancel the command"
$intro_message+="Full: - Back up all files that have been modified in the last $HowFarBackFull days"
$intro_message+="None: - Back up all files that have been modified in the last $HowFarBack days, but don't put them in a project folder"
$intro_message+="New: - Prompt for a project folder name"
$intro_message+="All other boxes are project folder names:"

[system.windows.forms.messagebox]::show(($intro_message -join "`n"), "message") 


$Projects = [System.Collections.ArrayList]@()
$Projects += "ABORT"   # do not backup
$Projects += ,"Full"   # Backup everything
$Projects += ,"None"   # No project
$Projects += ,"OSC"    # Project 1
$Projects += ,"ePay"   # Project 2
$Projects += ,"HealthHome" # Project 3
# Add new projects here...
$Projects += ,"New..." # Ask for new project folder

$LoggingLevel="3" #LoggingLevel only for Output in Powershell Window, 1=smart, 3=Heavy


# I use Dirk Bremen's Get-Choice from https://github.com/DBremen/PowerShellScripts/blob/master/functions/Get-Choice.ps1
. ".\GetChoice.ps1"
$Project=Get-Choice  "Which Project?" ($Projects) 1 

if ($Project -eq "ABORT") {
    Write-Host "Never mind...."
    exit
} elseif ($Project -eq "None") {
    $Project=""
} elseif ($Project -eq "New...") {
    $Project = read-host -Prompt "What project Folder should I create?"
} else {
    #$Project="$Project\" # Do nothing
}

# If a project is supplied, then change the destination directory

if ($Project.length -gt 0 ) {
    $parent="$parent\$Project"
}

# Here are some files we access - the log file and the timestamp file
$date = Get-Date -Format yyyy.MM.dd
$BackupDir = "$parent\$date" # Where I put it...
$Log = "$BackupDir\Log.txt"
$timestamp="$parent\timestamp.txt"

echo "Backupdir is $BackupDir, timestamp is $timestamp"


 # and the rest should be left alone normally

#----------------------------- 
#FUNCTIONS
#Logging - log the filename, etc.
Function Logging ($State, $Message) {
    # Log function
    $Datum=Get-Date -format dd.MM.yyyy-HH:mm:ss

    if (!(Test-Path -Path $Log)) {
        New-Item -Path $Log -ItemType File | Out-Null
    }
    $Text="$Datum - $State"+":"+" $Message"
    # Note that the message "was copied" is special
    # Do we display it i the console, 
    if ($LoggingLevel -eq "1") {
        if ($Message -notmatch "was copied") {Write-Host $Text} # write to console any messages other than the "copied" messages
    }
    if ($LoggingLevel -eq "3") {
        # if ( $Message -match "was copied") {Write-Host $Text} # only write names of copied files
        Write-Host $Text # only write names of copied files
    }
    # Now log this to the log file
    add-Content -Path $Log -Value $Text
}


#Create Backupdir 
Function Create-Backupdir {
# Creates backup directory, and create log file inside that diectory
 
    VerifyDirectory($BackupDir)
    if ((Test-Path $Log) -eq $false) {
        New-Item -Path $Log -ItemType File 
        # Move-Item -Path $Log -Destination $Backupdir
        Logging "INFO" "Log file $Log created"
    }
    # Set-Location $Backupdir
    Logging "INFO" "Continue with Log File at $Backupdir"
}


# Verify Directory exists - if it does not exist, create it
Function VerifyDirectory($dir) {
    # See if the target dirctory exists, and if not, create it
    if ((Test-path $dir) -eq $false) {
        Write-Host "Create Backupdir $dir"
        New-Item -Path $dir -ItemType Directory | Out-Null
    } else {
       Write-Host "Directory $dir already created"
    }

}

# Make it easy to modify by creating a copy function that handles all of the errors that can occur
Function MyCopy($file, $toDir, $to) {
    # file = file object we are copying
    # toDir = the destyination directory
    # restpath - the name of the file in the destination directory
    if ($to -eq $null) {
        Write-Host "Error: file destination name has zero length"
        exit
    }
    from=$file.fullname
    Write-host "Copy $from -> (", $toDir, ") $to"
    
    if ( $file.PSIsContainer ) { # is the file a container?
       Write-Host "File $File is a DIR"
       if ( (Test-Path $CopyThere) -eq $false )  { # Is the dirctory I want to copy to already there?
          # No - it's not there. I have to create it.
          If ($file.Attributes.ToString().Contains("ReparsePoint")) {
              # Skip It
          } else {
              Write-Host "I NEED to create the target directory $CopyThere"
              MyCopy $file $CopyToDir $CopyThere
          }


       } else {
          Write-Host "Directory  $CopyThere already exists"
       }
   # Else - do nothing - it's not a directory 
   } else {
         # MyCopy $file $CopyToDir $CopyThere
   	 New-Item -ItemType File -Path $to -Force | Out-Null
   	 Copy-Item  -Path $from -Destination $to -Force -ErrorAction SilentlyContinue 
   	 # This seems to work: except I get "Copy-Item : Could not find a part of the path"
   	 #Copy-Item  $from $to -Force -ErrorAction SilentlyContinue 
   	 # did not work right:
   	 #Copy-Item  $from $to -WhatIf -Force -ErrorAction SilentlyContinue 
   	 Logging "INFO" "$from was copied to $to"

   }

}

# Create the backup directory at start of the script
Create-Backupdir

Logging "INFO" "+---------------------+"
Logging "INFO" "|  Start the Script   |"
Logging "INFO" "+---------------------+"

 # $ppath = test-Path $parent

 
 $Curr_date = get-date

 VerifyDirectory $BackupDir


$FirstTime=$true
# Now determine the date used as comparison
 if ((Test-Path $timestamp) -eq $true) {
    # get the timestamp of the file
    $b = Get-ChildItem $timestamp
    $compareDate=$b.LastWriteTime.AddDays(0) # have some overlap?
    $FirstTime=$false # second time or third, 
} else {
    $compareDate=get-date
    if ($Project -eq "Full") {
        $compareDate=$compareDate.AddDays($HowFarBackFull) # 
        Write-host "Backing Up Files",  (-1*$HowFarBackFull), "days old, i.e.", $compareDate
    } else {
        $compareDate=$compareDate.AddDays($HowFarBack) # 
        Write-host "Backing Up Files",  (-1*$HowFarBack), "days old, i.e.", $compareDate
    }

}

# Now let's examine all files


    foreach ($BackupFromHere in $src) {
        Logging "INFO" "+---------------------------------------------------"
        Logging "INFO" "| Looking for files to backup under $BackupFromHere"
        Logging "INFO" "+---------------------------------------------------"
        $TopDirectory = Split-Path $BackupFromHere -leaf #Get Desktop, Document, or whatever the top directory is in the source directory
        $Index=$BackupFromHere.LastIndexOf("\")
        $SplitBackup=$BackupFromHere.substring(0,$Index)
        #Echo "Split is $SplitBackup and end is $TopDirectory, index is $Index"
        $NewBackup= $($BackupDir + "\" + $TopDirectory)
        VerifyDirectory $NewBackup
        # Orig
        #$Files = Get-ChildItem -Path $BackupFromHere  -File -Directory -System -Hidden  -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $compareDate }  

        $Files = Get-ChildItem -Path $BackupFromHere  -Recurse -ErrorAction SilentlyContinue  | Where-Object { $_.LastWriteTime -gt $compareDate }  
        write-host "number of files since", $compareDate, "is", $Files.count

        
        foreach ($File in $Files) {

     
            #Write-Host "File is $File"

            if ($file.Name.length -gt 0) {
            
                if ($File.fullname.contains("logs")) {
                    Write-Host "File is $File - fullname", $File.fullname
                    #        exit
                }
            #Echo  "file is $File, filename is ", $File.fullname, "splitbackup is $SplitBackup", "Fname length", $File.Name.length
            $restpath=$file.fullname.replace($SplitBackup,"")
            #Echo "backup: $BackupDir Top: $Directory Rest: $restpath"            
            # Copy-Item -Path $_.fullname -Destination $BackupDir

            $CopyThere= $($BackupDir + "\" + $Directory + $restpath)
            $CopyToDir= $($BackupDir + "\" + $Directory )
            #Echo "CopyThere: $CopyThere, CopyToDir: $CopyToDir"
            # I have to add something that prevents me from copying (creating)  a directory to the new location (making a directory inside a directory)
            if ( $file.PSIsContainer ) { # is the file a container?
                Write-Host "File $File is a DIR"
                if ( (Test-Path $CopyThere) -eq $false )  { # Is the dirctory I want to copy to already there?
                    # No - it's not there. I have to create it.
                    If ($file.Attributes.ToString().Contains("ReparsePoint")) {
                        # Skip It
                    } else {
                        Write-Host "I NEED to create the target directory $CopyThere"
                        MyCopy $file $CopyToDir $CopyThere
                    }


                } else {
                 Write-Host "Directory  $CopyThere already exists"
                }
                # Else - do nothing - it's 
            } else {
                MyCopy $file $CopyToDir $CopyThere
            }
                #|Out-Null 
        }
        } # End foreach

    }


 
 # Done - create the timestamp file
 if ($FirstTime -eq $false) {
    # if we have done this before
    Remove-Item $timestamp
 }
 New-Item -Path $parent -name "timestamp.txt" -type file  | Out-Null
Logging "INFO" "+---------------------+"
Logging "INFO" "|   End the Script    |"
Logging "INFO" "+---------------------+"
Read-Host -Prompt "Press Enter to exit" # Give them a chance to see everything
