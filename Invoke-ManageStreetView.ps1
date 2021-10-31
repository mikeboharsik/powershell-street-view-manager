<#
	.SYNOPSIS
	Provides functionality for managing photos uploaded to Google Street View.

	.PARAMETER ConfigDir
	Specifies the directory in which script-related data should be read and written.

	.PARAMETER NewPhotoPath
	The fully qualified path to a photo to upload. Runs the script specifically to upload a new photo.

	.EXAMPLE
	PS> ./Invoke-ManageStreetView -NewPhotoPath "C:\Pictures\pano_01.jpg"

	.LINK
	https://www.github.com/mikeboharsik/powershell-street-view-manager

	.LINK
	https://mobisoftinfotech.com/tools/plot-multiple-points-on-map/
#>

[CmdletBinding(SupportsShouldProcess)]
Param(
	[string] $ConfigDir = $PSScriptRoot,
	[string] $NewPhotoPath = $null,
	[string] $GetPhotoId = $null,
	[string] $DeletePhotoId = $null,

	[switch] $ListPhotos,
	[switch] $SavePhotoList,
	[switch] $ForceGetToken,

	[switch] $Interactive,
	[switch] $I,

	[switch] $Help,
	[switch] $H
)

$apiReferenceUri = "https://developers.google.com/streetview/publish/reference/rest"

if ($H) {
	$Help = $true
}

if ($Help) {
	Start-Process $apiReferenceUri

	return 0
}

if ($I) {
	$Interactive = $true
}

$ConfigDir = Resolve-Path $ConfigDir
$ConfigPath = "$ConfigDir/config.json"

$BaseUri = "https://streetviewpublish.googleapis.com"

$DefaultConfig = @{
	clientId = "<ENTER CLIENTID HERE>"
	clientSecret = "<ENTER CLIENT SECRET HERE>"
	redirectUri = "<ENTER REDIRECT URI HERE>"
};

function SeedConfig {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	if (!(Test-Path $ConfigPath)) {
		$serializedConfig = $DefaultConfig | ConvertTo-Json -Depth 10

		Set-Content $ConfigPath $serializedConfig

		throw "A default config.json file has been created. Populate this with the necessary info before running this script again."
	}
}

function Get-Config {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	if($PSCmdlet.ShouldProcess("Read config file '$ConfigDir'")) {
		$config = Get-Content $ConfigPath -Raw
	}

	if($PSCmdlet.ShouldProcess("Convert config file content from JSON")) {
		$config = ConvertFrom-Json $config
	}

	if ($DefaultConfig.clientId -eq $config.clientId) {
		throw "Populate the clientId in config.json"
	}

	if ($DefaultConfig.clientSecret -eq $config.clientSecret) {
		throw "Populate the clientSecret in config.json"
	}

	if ($DefaultConfig.redirectUri -eq $config.redirectUri) {
		throw "Populate the redirectUri in config.json"
	}

	return $config
}

function Get-AuthHeader {
	[CmdletBinding()]
	Param()

	Write-Verbose "Creating auth header with auth token '$script:AuthToken'"

	return @{
		Authorization = "Bearer $script:AuthToken"
	}
}

function Get-Photos {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	if ($PSCmdlet.ShouldProcess("Get list of photos")) {
		[hashtable[]] $photos = @()

		do
		{
			# despite what the API reference claims, pageSize is required to get a usable response
			$uri = "$BaseUri/v1/photos?view=INCLUDE_DOWNLOAD_URL&pageSize=100"

			if ($nextPageToken) {
				$uri += "&pageToken=$nextPageToken"
			}

			Write-Host $uri

			$res = Invoke-RestMethod `
				-Uri $uri `
				-Headers (Get-AuthHeader)
				| ForEach-Object { $_ | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable }

			$photos += $res.photos
			$nextPageToken = $res.nextPageToken
		} while ($nextPageToken)

		if ($SavePhotoList) {
			Set-Content "$ConfigDir/photos.json" (ConvertTo-Json -Depth 10 $photos)
		}

		return $photos
	} else {
		return @{
			photos = @((Get-Photo))
			nextPageToken = $null
		}
	}
}

function Get-Photo {
	[CmdletBinding(SupportsShouldProcess)]
	Param([string] $PhotoId = "CAoSLEFGMVFpcFAzc1doV0QyamFsY0JZLVBQR0gtcjVJV0VLUThZWXpENEcyRVZI")

	if ($PSCmdlet.ShouldProcess("Get photo '$PhotoId'")) {
		$uri = "$BaseUri/v1/photo/$($PhotoId)?view=INCLUDE_DOWNLOAD_URL"

		return Invoke-RestMethod `
			-Uri $uri `
			-Headers (Get-AuthHeader)
			| ForEach-Object { $_ | ConvertTo-Json | ConvertFrom-Json -AsHashtable }
	} else {
		return @{
			photoId = @{
				id = "MOCK_PHOTO_ID"
			}
			uploadReference = @{
				uploadUrl = "MOCK_UPLOAD_URL"
			}
			downloadUrl = "MOCK_DOWNLOAD_URL"
			thumbnailUrl = "MOCK_THUMBNAIL_URL"
			shareLink = "MOCK_SHARE_LINK"
			pose = @{
				latLngPair = @{
					latitude = 0.0
					longitude = 0.0
				}
				altitude = 0.0
				heading = 0.0
				pitch = 0.0
				roll = 0.0
				level = @{
					number = 0
					name = "MOCK_LEVEL_NAME"
				}
				accuracyMeters = 0.0
			}
			connections = @(
				@{
					target = @{
						id = "MOCK_PHOTO_ID"
					}
				}
			)
			captureTime = "1970-01-01 00:00:00"
			places = @(
				@{
					placeId = "MOCK_PLACE_ID"
				}
			)
			viewCount = 0
			transferStatus = "NEVER_TRANSFERRED"
			mapsPublishStatus = "MOCK_MAPS_PUBLISH_STATUS"
		}
	}
}

function Get-ExistingUploadRef {
	[CmdletBinding()]
	Param([Parameter(Mandatory = $true)][string] $PhotoPath)

	if (!(Test-Path "$PSScriptRoot/data.json")) {
		return
	}

	$data = (Get-Content "$PSScriptRoot/data.json") | ConvertFrom-Json -AsHashtable
	$uploadRefs = $data.uploadRefs

	$existingUploadRef = $uploadRefs
		| Where-Object { $_.photoPath -eq $PhotoPath }
		| Select-Object -First 1

	return $existingUploadRef
}

function Validate-PhotoAttributes {
	[CmdletBinding()]
	Param([string] $PhotoPath)

	$exifTags = @{
		CreateDate = @{}
		CroppedAreaImageHeightPixels = @{ Required = $true }
		CroppedAreaImageWidthPixels = @{ Required = $true }
		CroppedAreaLeftPixels = @{ DefaultVal = 0; Required = $true	}
		CroppedAreaTopPixels = @{	DefaultVal = 0; Required = $true }
		DateTimeOriginal = @{ SameValueAs = @( "CreateDate" ); Required = $true } # Google seems to assume that this is local time and auto-converts to UTC on upload
		FirstPhotoDate = @{ SameValueAs = @( "DateTimeOriginal", "CreateDate" ) }
		FullPanoHeightPixels = @{ Required = $true }
		FullPanoWidthPixels = @{ Required = $true }
		GPSLatitude = @{}
		GPSLongitude = @{}
		LastPhotoDate = @{ SameValueAs = @( "DateTimeOriginal", "CreateDate" ) }
		PoseHeadingDegrees = @{	DefaultVal = 0; Required = $true }
		ProjectionType = @{ DefaultVal = "equirectangular"; Required = $true }
		StitchingSoftware = @{}
	}

	[string[]] $relevantExifTags = $exifTags.Keys
	[string[]] $requiredExifTags = $exifTags.Keys | Where-Object { $exifTags[$_].Required -eq $true }

	Write-Verbose "Required EXIF tags = $($requiredExifTags -Join ', ')"

	$exiftoolArgs = $relevantExifTags | ForEach-Object { "-$_" }
	$exiftoolArgs += "-json"
	$exiftoolArgs += $PhotoPath

	$result = exiftool.exe @exiftoolArgs
	$resultParsed = $result | ConvertFrom-Json -AsHashtable
	Write-Verbose "Initial tags:`n$($resultParsed | ConvertTo-Json)"

	[string[]] $missing = @()
	[string[]] $repairs = @()
	$relevantExifTags | ForEach-Object {
		$curTag = $_

		$curVal = $resultParsed[$curTag]
		Write-Verbose "Photo current $curTag = $curVal"

		if ($null -eq $curVal) {
			$curTagDefaultVal = $exifTags[$curTag].DefaultVal
			if ($null -ne $curTagDefaultVal) {
				$repairs += "-$curTag=$curTagDefaultVal"
				return
			}

			$curTagSameValueAs = $exifTags[$curTag].SameValueAs
			if ($null -ne $curTagSameValueAs) {
				for ($i = 0; $i -lt $curTagSameValueAs.Length; $i++) {
					$otherTag = $curTagSameValueAs[$i]
					$otherTagValue = $resultParsed[$otherTag]
					if ($null -ne $otherTagValue) {
						$repairs += "-$curTag=$otherTagValue"
						return
					}
				}
			}

			if ($exifTags[$curTag].Required -eq $true) {
				$missing += $curTag
			}
		}
	}

	Write-Verbose "repairs = $repairs"
	if ($repairs.Length -ne 0) {
		$repairs += $PhotoPath
		$exiftoolSecondaryArgs = $repairs
		if ($PSCmdlet.ShouldProcess("Apply missing default values via 'exiftool.exe $exiftoolSecondaryArgs'")) {
			exiftool.exe @exiftoolSecondaryArgs
		}
	}

	if ($PSCmdlet.ShouldProcess("Output updated image tags")) {
		$result = exiftool.exe @exiftoolArgs
		$resultParsed = $result | ConvertFrom-Json -AsHashtable
		Write-Verbose "Final tags:`n$($resultParsed | ConvertTo-Json)"
	}

	if ($missing.Length -ne 0) {
		throw "Missing the followed required tags: [$($missing -Join ', ')]"
	}
}

function Start-Upload {
	[CmdletBinding(SupportsShouldProcess)]
	Param([Parameter(Mandatory = $true)][string] $PhotoPath)

	Validate-PhotoAttributes -PhotoPath $PhotoPath

	$existingUploadRef = Get-ExistingUploadRef -PhotoPath $PhotoPath
	if ($existingUploadRef) {
		Write-Verbose "An unused uploadRef for '$PhotoPath' already exists, using that instead"

		return $existingUploadRef
	}

	if ($PSCmdlet.ShouldProcess("Initiate upload")) {
		$uploadRef = Invoke-RestMethod `
			-Uri "$BaseUri/v1/photo:startUpload" `
			-Method POST `
			-Headers (Get-AuthHeader)
			| ForEach-Object { $_ | ConvertTo-Json | ConvertFrom-Json -AsHashtable }

		$uploadRef.photoPath = $PhotoPath

		if (!(Test-Path "$PSScriptRoot/data.json")) {
			Set-Content "$PSScriptRoot/data.json" "{}"
		}

		$data = (Get-Content "$PSScriptRoot/data.json") | ConvertFrom-Json -AsHashtable
		if ($null -eq $data) {
			$data = @{}
		}

		if (!$data.uploadRefs) {
			$data.uploadRefs = @($uploadRef)
		} else {
			$data.uploadRefs += $uploadRef
		}

		Set-Content "$PSScriptRoot/data.json" (ConvertTo-Json -Depth 10 $data)

		return $uploadRef
	} else {
		return @{
			photoPath = "MOCK_PHOTO_PATH"
			uploadUrl = "MOCK_UPLOAD_URL"
		}
	}
}

function Invoke-UploadPhoto {
	[CmdletBinding(SupportsShouldProcess)]
	Param($UploadRef)

	$uploadUrl = $UploadRef.uploadUrl
	$photoPath = $UploadRef.photoPath

	if ($PSCmdlet.ShouldProcess("Upload image data from '$photoPath' to '$uploadUrl'")) {
		$headers = Get-AuthHeader
		$headers['Content-Type'] = "image/jpeg"
	
		Invoke-RestMethod `
			-Uri $uploadUrl `
			-Method POST `
			-Headers $headers `
			-InFile $photoPath
			| ForEach-Object { $_ | ConvertTo-Json | ConvertFrom-Json -AsHashtable }
	}
}

function Invoke-CreatePhoto {
	[CmdletBinding(SupportsShouldProcess)]
	Param($UploadRef)

	$body = ConvertTo-Json -Depth 10 @{ uploadReference = @{ uploadUrl = $UploadRef.uploadUrl } }

	$headers = Get-AuthHeader
	$headers['Content-Type'] = "application/json"

	if ($PSCmdlet.ShouldProcess("Create photo using body '$body'")) {
		Invoke-RestMethod `
			-Uri "$BaseUri/v1/photo" `
			-Method POST `
			-Headers $headers `
			-Body $body
			| ForEach-Object { $_ | ConvertTo-Json | ConvertFrom-Json -AsHashtable }
	}
}

function Invoke-NewPhotoFlow {
	[CmdletBinding(SupportsShouldProcess)]
	Param([string] $NewPhotoPath)

	$uploadRef = Start-Upload -PhotoPath $NewPhotoPath

	Invoke-UploadPhoto -UploadRef $uploadRef

	$photo = Invoke-CreatePhoto -UploadRef $uploadRef

	$data = (Get-Content "$PSScriptRoot/data.json") | ConvertFrom-Json -AsHashtable
	$data.uploadRefs = ($data.uploadRefs | Where-Object { $_.photoPath -ne $NewPhotoPath }) ?? @()
	if (!$data.photos) {
		$data.photos = @()
	}
	$data.photos += $photo
	Set-Content "$PSScriptRoot/data.json" (ConvertTo-Json -Depth 10 $data)

	return ($photo | ConvertTo-Json -Depth 10)
}

function Invoke-DeletePhoto {
	[CmdletBinding(SupportsShouldProcess)]
	Param([string] $PhotoId)

	if ($PSCmdlet.ShouldProcess("Delete photo '$PhotoId'")) {
		Invoke-RestMethod `
			-Uri "$BaseUri/v1/photo/$PhotoId" `
			-Method DELETE `
			-Headers (Get-AuthHeader)
			| ForEach-Object { $_ | ConvertTo-Json | ConvertFrom-Json -AsHashtable }

		$data = (Get-Content "$PSScriptRoot/data.json") | ConvertFrom-Json -AsHashtable
		if ($data.photos) {
			$data.photos = [hashtable[]]($data.photos | Where-Object { $_.photoId.id -ne $PhotoId }) ?? @()
		}
		Set-Content "$PSScriptRoot/data.json" (ConvertTo-Json -Depth 10 $data)
	}
}

function Invoke-GetPhotoInteractive {
	[CmdletBinding()]
	Param()

	Clear-Host

	$data = (Get-Content "$PSScriptRoot/data.json" | ConvertFrom-Json -AsHashtable)

	[string[]] $photoIds = $data.photos
		| Select-Object -ExpandProperty photoId
		| Select-Object -ExpandProperty id

	for ($i = 0; $i -lt $photoIds.Length; $i++) {
		$cur = $photoIds[$i]

		Write-Host "$($i+1). $cur"
	}

	[int] $res = Read-Host "`nGet which photo?"

	$photoId = $photoIds[$res-1]

	if (!$photoId) {
		throw "Invalid photo"
	}

	Write-Host ""
	Write-Host (Get-Photo -PhotoId $photoId | ConvertTo-Json -Depth 10)

	Read-Host "`nPress any key to continue"
}

function Invoke-DeletePhotoInteractive {
	[CmdletBinding()]
	Param()

	Clear-Host

	$data = (Get-Content "$PSScriptRoot/data.json" | ConvertFrom-Json -AsHashtable)

	[string[]] $photoIds = $data.photos
		| Select-Object -ExpandProperty photoId
		| Select-Object -ExpandProperty id

	for ($i = 0; $i -lt $photoIds.Length; $i++) {
		$cur = $photoIds[$i]

		Write-Host "$($i+1). $cur"
	}

	[int] $res = Read-Host "`nDelete which photo?"

	$photoId = $photoIds[$res-1]

	if (!$photoId) {
		throw "Invalid photo"
	}

	Write-Host ""
	Invoke-DeletePhoto -PhotoId $photoId

	Read-Host "`nDeleted '$photoId', press any key to continue"
}

function Invoke-GetPhotosInteractive {
	[CmdletBinding()]
	Param()

	Clear-Host

	Write-Host (Get-Photos | ConvertTo-Json -Depth 10)

	Read-Host "`nPress any key to continue"
}

function Invoke-Interactive {
	[CmdletBinding()]
	Param()

	while ($true) {
		Clear-Host

		Write-Host "1. Get photo`n2. Delete photo`n3. List photos"

		$res = Read-Host "`nWhat would you like to do?"

		switch ($res) {
			'1' { Invoke-GetPhotoInteractive }
			'2' { Invoke-DeletePhotoInteractive }
			'3' { Invoke-GetPhotosInteractive }
			'h' { Start-Process $apiReferenceUri; return }
			'q' { return }
			default { Write-Host "Invalid input" }
		}
	}
}

function main {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	SeedConfig

	$config = Get-Config

	$clientId = $config.clientId
	$clientSecret = $config.clientSecret
	$redirectUri = $config.redirectUri

	if ($PSCmdlet.ShouldProcess("Get OAuth token")) {
		$script:AuthToken = & "./Get-OAuthToken.ps1" -ClientId $clientId -ClientSecret $clientSecret -RedirectUri $redirectUri -ForceGetToken:$ForceGetToken
	} else {
		$script:AuthToken = "MOCK_AUTH_TOKEN"
	}

	if ($Interactive) {
		return Invoke-Interactive
	} elseif ($ListPhotos) {
		return Get-Photos
	} elseif ($DeletePhotoId) {
		return Invoke-DeletePhoto -PhotoId $DeletePhotoId
	} elseif ($GetPhotoId) {
		return Get-Photo -PhotoId $GetPhotoId
	}	elseif ($NewPhotoPath) {
		return Invoke-NewPhotoFlow -NewPhotoPath $NewPhotoPath
	}
}

return main
