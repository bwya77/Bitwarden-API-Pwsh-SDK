function Get-BitwardenMembers {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    begin {
        $Params = @{
            Endpoint = "public/members"
            Method   = "GET"
        }
    }

    process {
        (Invoke-BitwardenRequest @Params).data
    }
}