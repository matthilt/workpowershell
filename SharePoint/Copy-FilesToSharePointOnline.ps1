# Will need SharePoint Online Powershell module installed.

[CmdletBinding()]
Param(
	[Parameter(Mandatory = $True)]
	[string]$SourceFiles, # Location of files to migrate. Can be file share.

	[Parameter(Mandatory = $True)]
	[string]$TargetWebURL, # Root of SharePoint Online site. Make sure has trailing "/"
	
	[Parameter(Mandatory = $True)]
	[string]$MigrationStoragePath, # Location to store migration files. Logs and additional files will go here. Will be around the size of the files to be copied.

	[Parameter(Mandatory = $True)]
	[string]$AdminUser, # User with admin rights in SharePoint Online
	
	[Parameter(Mandatory = $True)]
	[string]$AdminPassword, # Password for the admin user. (I know it should be a Secure String)

	[Parameter(Mandatory = $True)]
	[string]$AdminSharePointSite, # Admin SharePoint Online site

	[Parameter(Mandatory = $True)]
	[string]$TargetDocumentLibraryPath, # The Document Library where the files will be stored.

	[Parameter(Mandatory = $False)]
	[string]$TargetDocumentLibrarySubFolderPath # The subfolder path to store the migrated files
)

$DirectoryPath = "$MigrationStoragePath\$(Get-Date -Format yyMMddHHmmss)" # Creates a subfolder based on the date to store migration files
New-Item $DirectoryPath -type directory
$LogPath = $DirectoryPath + "\Log.txt" # Log

"Start Time:         " + $(Get-Date) | Out-File $LogPath -Append
"Source Files:       " + $sourcefiles | Out-File $LogPath -Append
"TargetWebURL:       " + $TargetWebUrl | Out-File $LogPath -Append

$Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AdminUser, $(ConvertTo-SecureString $AdminPassword -AsPlainText -Force)

"Connect-SPOService"
Connect-SPOService -Url $AdminSharePointSite -Credential $Credentials

$PackageFolderLocation = $DirectoryPath + "\Package" # Location of New-SPOMigrationPackage data
$ConvertedPackagePath = $DirectoryPath + "\ConvertedPackage" # Location of ConvertTo-SPOMigrationTargetedPackage data (will be big)

$Site = Get-SPOSite -Identity ($TargetWebURL.Substring(0, $TargetWebURL.Length - 1))

"Set-SPOUser"
# Sets admin user to Site Collection admin for SharePoint Online Site
Set-SPOUser `
	-Site $site.Url `
	-LoginName $AdminUser `
	-IsSiteCollectionAdmin $true
	
"New-SPOMigrationPackage"
# Creates a new migration package based on source files
New-SPOMigrationPackage `
	-SourceFilesPath $sourceFiles `
	-OutputPackagePath $PackageFolderLocation `
	-TargetWebUrl $targetWebUrl `
	-TargetDocumentLibraryPath $TargetDocumentLibraryPath `
	-TargetDocumentLibrarySubFolderPath $TargetDocumentLibrarySubFolderPath `
	-IgnoreHidden `
	-ReplaceInvalidCharacters

"ConvertTo-SPOMigrationTargetedPackage"
# Converts to targeted package and pulls in actual files
ConvertTo-SPOMigrationTargetedPackage `
	-SourceFilesPath $sourceFiles `
	-SourcePackagePath $PackageFolderLocation `
	-OutputPackagePath $ConvertedPackagePath `
	-TargetWebUrl $targetWebUrl `
	-TargetDocumentLibraryPath $TargetDocumentLibraryPath `
	-TargetDocumentLibrarySubFolderPath $TargetDocumentLibrarySubFolderPath `
	-Credentials $Credentials
		
"Invoke-SPOMigrationEncryptUploadSubmit"
# Uploads and submits package data to create a new migration job
$UploadData = `
	Invoke-SPOMigrationEncryptUploadSubmit `
	-SourceFilesPath $sourceFiles `
	-SourcePackagePath $ConvertedPackagePath `
	-Credentials $Credentials `
	-TargetWebUrl $targetWebUrl

#Information about job
$JobID = $UploadData.JobId
$JobReportingQueueURI = $UploadData.ReportingQueueUri.AbsoluteUri

"JobId:              " + ($UploadData.JobId) | Out-File $LogPath -Append
"ReportingQueueURI:  " + ($UploadData.ReportingQueueUri.AbsoluteUri) | Out-File $LogPath -Append
"Encryption Key:     " + ($UploadData.Encryption.EncryptionKey) | Out-File $LogPath -Append

"Get-SPOMigrationJobProgress"
$Progress = Get-SPOMigrationJobProgress -AzureQueueUri $JobReportingQueueURI -Credentials $Credentials -TargetWebUrl $targetWebUrl -JobIds $JobID -EncryptionParameters ($UploadData.Encryption)
$Progress | Out-File $LogPath -Append

"End Time:           " + $(Get-Date) | Out-File $LogPath -Append

#"Get-SPOMigrationJobStatus"
#Get-SPOMigrationJobStatus -TargetWebUrl $targetWebUrl -Credentials $Credentials -JobId $JobID
