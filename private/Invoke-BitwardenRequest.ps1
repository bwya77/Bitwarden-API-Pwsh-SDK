Function Invoke-BitwardenRequest {
    [OutputType([PSCustomObject[]], [PSCustomObject], [Void])]
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[^/].*')]
        [string]$Endpoint,

        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,

        [Parameter()]
        [ValidatePattern('^https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}/?.*$')]
        [string]$GatewayBaseURL = 'https://api.bitwarden.com',

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [ValidatePattern('^[^?].*|^$')]
        [string]$FilterQuery,

        [Parameter()]
        [int]$InitialRetryDelaySeconds = 3,

        [Parameter()]
        [string]$Body
    )

    Begin {
        if ($null -eq $script:BitwardenAccessToken) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new('No access token found. Run Connect-Bitwarden first.'),
                    'NoAccessTokenFound',
                    [System.Management.Automation.ErrorCategory]::AuthenticationError,
                    $null
                )
            )
        }
        elseif ([DateTime]::Now -gt $script:BitwardenAccessToken.Expiration) {
            $connectSplat = @{
                ClientId     = $script:BitwardenAccessToken.ClientId
                ClientSecret = $script:BitwardenAccessToken.ClientSecret
                Scope        = $script:BitwardenAccessToken.Scope
                Endpoint     = $script:BitwardenAccessToken.Endpoint
            }
            Connect-Bitwarden @connectSplat
        }
        Write-Verbose -Message  "Beginning Invoke-BitwardenRequest Process"

        # Build base URL
        Write-Verbose -Message  "Building base URL"
        $Uri = "$GatewayBaseURL/$Endpoint"
        Write-Verbose -Message  "Base URL: $Uri"

        # Add filter query if present
        if ($FilterQuery) {
            Write-Verbose -Message  "Filter Query: $FilterQuery"
            $Uri = "$Uri`?$FilterQuery"
            Write-Verbose -Message  "URL with Filter Query: $Uri"
        }

        $InvokeRestMethodParams = @{
            Headers     = @{
                'Ocp-Apim-Subscription-Key' = $script:BitwardenAccessToken.GatewaySubscriptionKey
                'Authorization'             = "Bearer $($script:BitwardenAccessToken.AccessToken)"
                'Content-Type'              = 'application/json'
            }
            Method      = $Method
            URI         = $uri
            ErrorAction = "Stop"  # Changed to Stop to ensure we catch errors
        }
        if ($Null -ne $Body) {
            $InvokeRestMethodParams.Body = $Body
        }
    }

    Process {
        Write-Verbose -Message  "Performing REST method invocation"
        [int]$retryCount = 0
        [bool]$success = $false

        do {
            try {
                $response = Invoke-RestMethod @InvokeRestMethodParams
                $success = $true
            }
            catch {
                $errorMessage  = $_.Exception.Message
                $statusCode    = $_.Exception.Response.StatusCode
                $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue

                if ($statusCode -eq 429) {
                    $retryCount++
                    
                    # Extract retry delay from error message if available
                    $retryDelay = $InitialRetryDelaySeconds
                    if ($errorResponse.detail -match "Try again in (\d+) seconds") {
                        $retryDelay = [int]$matches[1]
                    }

                    # Apply exponential backoff
                    $waitTime = $retryDelay * [Math]::Pow(2, ($retryCount - 1))
                    
                    if ($retryCount -le $MaxRetries) {
                        Write-Warning "Rate limit exceeded. Waiting $waitTime seconds before retry $retryCount of $MaxRetries..."
                        Start-Sleep -Seconds $waitTime
                        continue
                    }
                }
                else {
                    if ($errorResponse.detail) {
                        $errorMessage = $errorResponse.detail
                    }
                    throw "Error Code ${statusCode}: $errorMessage"
                }        
            }
        } while (-not $success -and $retryCount -le $MaxRetries)
    }

    End {
        $response
    }
}