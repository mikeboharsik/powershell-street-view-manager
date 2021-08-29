[CmdletBinding(SupportsShouldProcess)]
Param(
	[Parameter(Mandatory = $true)]
	[string] $ClientId,

	[Parameter(Mandatory = $true)]
	[string] $ClientSecret,

	[Parameter(Mandatory = $true)]
	[string] $RedirectUri,

	[string] $ConfigDir = $PSScriptRoot,
	[switch] $Header,
	[switch] $ForceGetToken
)

$ConfigDir = Resolve-Path $ConfigDir
$ConfigPath = "$ConfigDir/config.json"

function Get-OAuthUri {
	[CmdletBinding()]
	Param()

	$oauthParams = @(
		"scope=https://www.googleapis.com/auth/streetviewpublish"
		"access_type=offline"
		"include_granted_scopes=true"
		"response_type=code"
		"redirect_uri=$RedirectUri"
		"client_id=$ClientId"
	)

	$oauthUri = "https://accounts.google.com/o/oauth2/v2/auth?$($oauthParams -Join '&')"

	return $oauthUri
}

function Get-OAuthAccessTokenUri {
	[CmdletBinding()]
	Param([string] $Code)

	$oauthAccessTokenParams = @(
		"client_secret=$clientSecret"
		"client_id=$clientId"
		"code=$Code"
		"redirect_uri=$redirectUri"
		"grant_type=authorization_code"
	)

	$oauthAccessTokenUri = "https://oauth2.googleapis.com/token?$($oauthAccessTokenParams -Join '&')"

	return $oauthAccessTokenUri
}

function Get-OAuthRefreshTokenUri {
	[CmdletBinding()]
	Param([string] $RefreshToken)

	$oauthRefreshTokenParams = @(
		"client_secret=$clientSecret"
		"client_id=$clientId"
		"refresh_token=$RefreshToken"
		"grant_type=refresh_token"
	)

	$oauthRefreshTokenUri = "https://oauth2.googleapis.com/token?$($oauthRefreshTokenParams -Join '&')"

	return $oauthRefreshTokenUri
}

function Invoke-OAuthFlow {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	try {
		if ($PSCmdlet.ShouldProcess('Send OAuth request and handle response')) {
			Write-Verbose "Sending OAuth request to $oauthUri"
		
			Start-Process (Get-OAuthUri)
		
			$listener = New-Object System.Net.HttpListener
			$listener.Prefixes.Add($RedirectUri + "/") # listener URI must end with '/'
			$listener.Start()
		
			$context = $listener.GetContext() 
			
			$data = $context.Request.Url.ToString().Split('?') `
				| ForEach-Object { $_.Split('&') } `
				| Select-Object -Skip 1 `
				| ForEach-Object {
					$out = @{}
					$tmp = $_.Split("=")
					$out[$tmp[0]] = $tmp[1]
					return $out
				}
		
			$content = [System.Text.Encoding]::UTF8.GetBytes((Get-Content "$PSScriptRoot/oauth.html"))
			$context.Response.OutputStream.Write($content, 0, $content.Length)
			$context.Response.Close()
		
			$tokenData = Invoke-RestMethod `
				-Uri (Get-OAuthAccessTokenUri -Code $data.code) `
				-Method 'POST'

			Write-Verbose "Raw token data is: $tokenData"
		
			$config = @{}
			if (Test-Path $ConfigPath) {
				$config = (Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable)
			}

			$now = Get-Date -AsUTC
			$expires = $now.AddSeconds([int]$tokenData.expires_in)

			Write-Verbose "Token expires in $($tokenData.expires_in) seconds, setting expires to '$expires'"

			Add-Member -InputObject $tokenData -MemberType NoteProperty -Name expires -Value $expires
			$tokenData.PSObject.Properties.Remove("expires_in")
			$config.tokenData = $tokenData
			Set-Content $ConfigPath (ConvertTo-Json -Depth 10 $config)
		
			return $tokenData.access_token
		} else {
			return "MOCK_ACCESS_TOKEN"
		}
	} finally {
		if ($null -ne $listener) {
			$listener.Stop()
		}
	}
}

function Get-CachedToken {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	if (!$ForceGetToken) {
		if ($PSCmdlet.ShouldProcess("Check for existing token at '$ConfigDir'")) {
			$configExists = Test-Path $ConfigPath
			if ($configExists) {
				$content = (Get-Content $ConfigPath | ConvertFrom-Json)

				if (!$content.tokenData) {
					return $null
				}

				$now = Get-Date -AsUTC
				$expires = (Get-Date $content.tokenData.expires)
				if ($now -ge $expires) {
					Write-Verbose "Stored token expired '$expires'"

					return $null
				} else {
					Write-Verbose "Got existing token from '$ConfigPath'"

					return $content.tokenData.access_token
				}
			}
		}
	}
}

function Get-AccessToken {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	$token = Get-CachedToken
	if (!$token) {
		$token = Invoke-OAuthFlow
		
		Write-Verbose "Got new token from OAuth flow"
	}

	if ($PSCmdlet.ShouldProcess(("Set script token and return"))) {
		return $token
	} else {
		return "MOCK_ACCESS_TOKEN"
	}
}

function Get-AuthorizationHeader {
	[CmdletBinding(SupportsShouldProcess)]
	Param()

	$header = @{ "Authorization" = "Bearer $(Get-AccessToken)" }

	Write-Verbose "Using Authorization header: $(ConvertTo-Json $header)"

	return $header
}

if ($Header) {
	$res = Get-AuthorizationHeader
} else {
	$res = Get-AccessToken
}

return $res