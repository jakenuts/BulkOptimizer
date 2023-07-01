<#
    .SYNOPSIS
        Optimizes image file size for all PNG and JPG images in a Microsoft Azure blob storage
        container by processing them locally and replacing their content with the optimized result.

    .DESCRIPTION
        Image files are often needlessly oversized and can be compressed without quality loss using
        widely-available utilities. Microsoft Azure provides a blob storage service that can be used
        to host publicly-accessible images for websites or other purposes. For containers with large
        numbers of suboptimal images or for bulk optimization, this script optimizes all images in
        a blob storage container with a single action.

        When run the script prompts for Azure credentials if not already present in the PowerShell session.
        It then connects and interactively allows the user to select a subscription, storage account, and container
        where the images reside. It then downloads each file (those blobs with png or jpg/jpeg extensions),
        optimizes using jpegtran.exe and optipng.exe utilities, and uploads the result to the blob.

        Upon upload the blob is marked as optimized using custom metadata. This allows the script to be run
        again without reprocessing optimzed images.

        The open source jpegtran.exe and optipng.exe executable files must exist in the same directory
        as the script. In addition, the Azure PowerShell module must be installed.

    .PARAMETER  PromptCredentials
        By default the script will connect to Azure with any existing credentials that have been used
        in previous connections. By including this switch, the script will always prompt for credentials.
    
    .EXAMPLE
        To run from a PowerShell prompt:
        
        .\Optimize-AzureBlobImages.ps1

    .EXAMPLE
        To run from a PowerShell prompt with credentials prompt:
        
        .\Optimize-AzureBlobImages.ps1 -PromptCredentials

    .INPUTS
        None.

    .OUTPUTS
        No objects returned.

    .NOTES
        For more details and implementation guidance, see the associated documentation at https://automys.com
#>

[CmdletBinding()]
Param(
    [switch]$PromptCredentials = $false,

    $Command # Placeholder parameter to workaround Windows 7 right-click run bug. Not used.
)

Write-Host Hello

# Verify Azure module installed/loaded
# if($null -ne (Get-Module -ListAvailable "Azure"))
# {
#     Import-Module Azure
# }insta
# else
# {
#     Write-Host "ERROR: PowerShell module for Microsoft Azure not found. Please install as described at http://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/" -ForegroundColor Red
#     Read-Host "Press [Enter] to exit..."
#     return
# }

# Verify optimization executable files present

$imageOptimizer = 'optimizt'

<# if(-not (Test-Path "$PSScriptRoot\optipng.exe"))
{
    Write-Host "Could not find the file optipng.exe in the script file folder [$PSScriptRoot]. Please download from [http://optipng.sourceforge.net/] and copy it there. Exiting script." -ForegroundColor Red
    Read-Host "Press [Enter] to exit..."
    return
}
if(-not (Test-Path "$PSScriptRoot\jpegtran.exe"))
{
    Write-Host "Could not find the file jpegtran.exe in the script file folder [$PSScriptRoot]. Please download from [http://jpegclub.org/jpegtran/] and copy it there. Exiting script." -ForegroundColor Red
    Read-Host "Press [Enter] to exit..."
    return
} #>

# Prompt for credentials if none are stored or user specified to prompt
Write-Host Connecting to Azure...
$loginContext = Get-AzContext
if($PromptCredentials -eq $true -or $null -eq $loginContext -or $null -eq $loginContext.Subscription)
{
    Login-AzAccount | Out-Null
}

# Get subscriptions
$subscriptions = @()
$subscriptions += Get-AzSubscription

if($subscriptions.Count -eq 0)
{
    Write-Host "No subscriptions were found for this account" -ForegroundColor Red
    Read-Host "Press [Enter] to exit..."
    return
}

# If more than one subscription available, show a selection prompt to user
if($subscriptions.Count -gt 1)
{
    $choices = @()
    $i = 0
    foreach($subscription in $subscriptions)
    {
        $choice = New-Object System.Management.Automation.Host.ChoiceDescription "&$i. $($subscription.Name)","Use this subscription"
        $choices += $choice
        $i++
    }

    $cancelChoice = New-Object System.Management.Automation.Host.ChoiceDescription "(&Cancel)","Exits the script"
    $choices += $cancelChoice

    # Prompt the user select subscription
    $title = "Select Azure Subscription"
    $message = "More than one Azure subscription is available. Which one contains the target storage account?"
    $selectionIndex = $host.ui.PromptForChoice($title, $message, $choices, 0) 

    if($choices[$selectionIndex].Label -eq "(&Cancel)")
    {
        Write-Host Script cancelled
        return
    }

    $targetSubscription = $subscriptions[$selectionIndex].Name
}
else
{
    $targetSubscription = $subscriptions[0].Name
    Write-Host Defaulting to only subscription found
}

# Set current subscription
Set-AzContext -SubscriptionId $targetSubscription | Out-Null
Write-Host "Using subscription: $targetSubscription" -ForegroundColor Green

# Get available storage accounts
$storageAccounts = @()
$storageAccounts += Get-AzStorageAccount -WarningAction SilentlyContinue

if($storageAccounts.Count -eq 0)
{
    Write-Host "No storage accounts were found in the subscription [$targetSubscription.Name]. Exiting script." -ForegroundColor Red
    Read-Host "Press [Enter] to exit..."
    return
}

# If more than one storage account available, show a selection prompt to user
if($storageAccounts.Count -gt 1)
{
    $choices = @()
    $i = 0
    foreach($storageAccount in $storageAccounts)
    {
        $choice = New-Object System.Management.Automation.Host.ChoiceDescription "&$i. $($storageAccount.StorageAccountName)","Use this storage account"
        $choices += $choice
        $i++
    }

    $cancelChoice = New-Object System.Management.Automation.Host.ChoiceDescription "(&Cancel)","Exits the script"
    $choices += $cancelChoice

    # Prompt the user select subscription
    $title = "Select storage account"
    $message = "More than one storage account is available in subscription [$targetSubscription]. Which one has the target storage container?"
    $selectionIndex = $host.ui.PromptForChoice($title, $message, $choices, 0) 

    if($choices[$selectionIndex].Label -eq "(Cancel)")
    {
        Write-Host Script cancelled
        return
    }

    $targetStorageAccount = $storageAccounts[$selectionIndex].StorageAccountName
	$targetResourceGroupName = $storageAccounts[$selectionIndex].ResourceGroupName
    
}
else
{
    $targetStorageAccount = $storageAccounts[0].StorageAccountName
	$targetResourceGroupName = $storageAccounts[0].ResourceGroupName
    Write-Host Defaulting to only storage account found
}

# Set current storage account
$key = (Get-AzStorageAccountKey -ResourceGroupName $targetResourceGroupName -name $targetStorageAccount)[0].value
$context = New-AzStorageContext -StorageAccountName $targetStorageAccount -StorageAccountKey $key
Write-Host "Using storage account: [$targetStorageAccount]" -ForegroundColor Green

# Get available storage containers
$storageContainers = @()
$storageContainers += Get-AzStorageContainer -Context $context

if($storageContainers.Count -eq 0)
{
    Write-Host "No containers were found in the storage account [$targetStorageAccount]. Exiting script." -ForegroundColor Red
    Read-Host "Press [Enter] to exit..."
    return
}

# If more than one storage account available, show a selection prompt to user
if($storageContainers.Count -gt 1)
{
    $choices = @()
    $i = 0
    foreach($storageContainer in $storageContainers)
    {
        $choice = New-Object System.Management.Automation.Host.ChoiceDescription "&$i. $($storageContainer.Name)","Optimize images in this container"
        $choices += $choice
        $i++
    }

    $cancelChoice = New-Object System.Management.Automation.Host.ChoiceDescription "(&Cancel)","Exits the script"
    $choices += $cancelChoice

    # Prompt the user select subscription
    $title = "Select storage container"
    $message = "More than one container exists in the storage account. Which one has the images to optimize?"
    $selectionIndex = $host.ui.PromptForChoice($title, $message, $choices, 0) 

    if($choices[$selectionIndex].Label -eq "(Cancel)")
    {
        Write-Host Script cancelled
        return
    }

    $targetStorageContainer = $storageContainers[$selectionIndex].Name
}
else
{
    $targetStorageContainer = $storageContainers[0].Name
    Write-Host Defaulting to only container in the storage account
    
}

Write-Host "Selected storage container: [$targetStorageContainer]" -ForegroundColor Green

$sourceImages = @()

# Get PNG images 
$sourceImages += Get-AzStorageBlob -Container $targetStorageContainer -Blob "*png" -Context $context

# Get JPG images 
$sourceImages += Get-AzStorageBlob -Container $targetStorageContainer -Blob "*jp*g" -Context $context

$totalImageCount = $sourceImages.Count

if($totalImageCount -eq 0)
{
    Write-Host "No PNG or JPG images found in the container. Exiting script." -ForegroundColor Cyan
    Read-Host "Press [Enter] to exit..."
    return
}

# Filter to only those not marked as previously optimized
$sourceImages = $sourceImages | where {!$_.ICloudBlob.Metadata.ContainsKey("optimized")}

if($sourceImages.Count -eq 0)
{
    Write-Host "All [ $totalImageCount ] images in the container are marked as previously optimized (with 'optimized = true' custom metadata value). Exiting script" -ForegroundColor Cyan
    Read-Host "Press [Enter] to exit..."
    return
}

# Prompt the user for confirmation
if($ConfirmPreference -eq "High")
{
    $title = "Confirm Optimization"
    $message = "Do you want to optimize and overwrite [ $($sourceImages.Count) ] PNG and JPG image blobs in the container [$targetStorageAccount\$targetStorageContainer]?"
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Performs optimization"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Cancels the script"
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $result = $host.ui.PromptForChoice($title, $message, $options, 0) 

    switch ($result)
    {
        0 {
            Write-Host "`nOK, giddy up...`n"
        }
        1 {
            Write-Host "`nNo worries. Action cancelled."
            return
        }
    }
}

$tempDirectory = $env:TEMP

foreach($image in $sourceImages)
{
    $optimized = $false

    # Download image blob to file
    $imageFilePath = "$tempDirectory\$($image.Name)"
    $image | Get-AzStorageBlobContent -Destination $tempDirectory -Force | Out-Null
    $initialSize = Get-ChildItem $imageFilePath | select -ExpandProperty Length

    Write-Host Processing $image.Name ...

    if($image.Name -like "*png")
    {
        # Optimize with optipng.exe and save output to variable
        &"$PSScriptRoot\optipng.exe" $imageFilePath 2>&1 | Tee-Object -Variable result | Out-Null
        if(($result -match "Input file size|already optimized" | Measure | select -ExpandProperty Count) -gt 0)
        {
            $optimized = $true
        }
    }
    elseif($image.Name -like "*jp*g") 
    {
        # Optimize with jpegtran.exe and save output to variable
        &"$PSScriptRoot\jpegtran.exe" -optimize -verbose $imageFilePath $imageFilePath 2>&1 | Tee-Object -Variable result | Out-Null
        if(($result -match "End of Image" | Measure | select -ExpandProperty Count) -gt 0)
        {
            $optimized = $true
        }
    }
    else
    {
        Write-Host "Skipping file with unexpected extension: [$imageFilePath]" -ForegroundColor Yellow
    }

    $processedSize = Get-ChildItem $imageFilePath | select -ExpandProperty Length
    [int]$savingsPercent = ($initialSize - $processedSize) / $initialSize * 100


    if($savingsPercent -ge 0) {
        Write-Host `tSaved ($initialSize - $processedSize) bytes [ $savingsPercent% ]
        
        if($optimized -eq $true)
        {
            # Upload optimized file to replace blob, retaining all existing metadata and adding a custom "optimized=true" marker to prevent future attempts
            $metadata = @{"optimized" = "true"}
            #Set-AzureStorageBlobContent -File $imageFilePath -Container $targetStorageContainer -Metadata $metadata -Force | Out-Null
            Set-AzStorageBlobContent -File $imageFilePath -Container $targetStorageContainer -Blob $image.Name -Metadata $metadata -Force -Context $context | Out-Null
        }
    }
    else {
        Write-Host `tImage ignored
    }


    # Remove temp file
    Remove-Item $imageFilePath
}

Write-Host `nOptimization complete! -ForegroundColor Green