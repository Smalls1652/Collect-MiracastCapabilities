<#PSScriptInfo

.VERSION 1909.08.01

.GUID 30a2eb9a-8ae0-4811-bc0c-9a17644878d1

.AUTHOR Tim Small

.COMPANYNAME Smalls.Online

.COPYRIGHT 2019

.TAGS Miracast systeminformation

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<#
.SYNOPSIS
    Collect Miracast capabilities for the system.
.DESCRIPTION
    Collect Miracast capabilities for the system by analyzing the network adapters, graphics cards, and if Miracast is HDCP capable.
.PARAMETER AllPhysicalAdapters
    Collect all physical network adapters, rather than just wireless network adapters.
.EXAMPLE
    Collect-MiracastCapabilities.ps1
    
    CapableNetAdapters                  CapableGraphicsCards      MiracastCapable HdcpCapable
    ------------------                  --------------------      --------------- -----------
    Intel(R) Dual Band Wireless-AC 8265 Intel(R) UHD Graphics 620            True        True

    (Collects Miracast information for the system.)
.EXAMPLE
    PS C:\> Collect-MiracastCapabilities.ps1 -AllPhysicalAdapters

    CapableNetAdapters                                                              CapableGraphicsCards      MiracastCapable HdcpCapable
    ------------------                                                              --------------------      --------------- -----------
    {Intel(R) Dual Band Wireless-AC 8265, Intel(R) Ethernet Connection (4) I219-LM} Intel(R) UHD Graphics 620            True        True

    (Collects Miracast information for the system, but includes all capable physical network adapters.)
#>
[CmdletBinding()]
param(
    [switch]$AllPhysicalAdapters
)

begin {
    <#
    The filter for collecting network adapters follows two conditions by default:
    1. If the NdisVersion of the adapter is greater than 6.30.
    2. If the network adapter is wireless.

    If the switch parameter '-AllPhysicalAdapters' is provided, then it will return any capable network adapter.
    #>
    switch ($AllPhysicalAdapters) {
        $true {
            Write-Verbose "Config Setting - Collecting all network adapters"
            filter NdisFilter {
                if ((([version]$PSItem.NdisVersion) -ge [version]"6.30")) {
                    $PSItem.InterfaceDescription
                }
            }
        }

        Default {
            Write-Verbose "Config Setting - Only collecting wireless network adapters"
            filter NdisFilter {
                if ((([version]$PSItem.NdisVersion) -ge [version]"6.30") -and ($PSItem.InterfaceName -like "wireless*")) {
                    $PSItem.InterfaceDescription
                }
            }
        }
    }

    <#
    This function runs DxDiag and saves it to a temporary XML file.
    
    DxDiag has information regarding if the system is Miracast capable or not. 
    #>
    function Collect-DxDiagInfo {
        $TempFile = New-TemporaryFile
        $null = Start-Process -FilePath "dxdiag" -ArgumentList @("/dontskip", "/whql:off", "/x $($TempFile.FullName)") -Wait -NoNewWindow
        $DxDiagXml = [xml](Get-Content -Path $TempFile.FullName -Raw)
        $null = Remove-Item -Path $TempFile -Force

        return $DxDiagXml
    }
}

process {
    Write-Verbose "Collecting Miracast capable network adapters."
    $NetAdapters = Get-NetAdapter -Physical | NdisFilter

    switch ($NetAdapters) {
        #If there are no network adapters
        {($NetAdapters | Measure-Object | Select-Object -ExpandProperty "Count") -eq 0} {
            $NetAdapters = "N/A"
        }
    }

    Write-Verbose "Collecting system information from 'dxdiag'."
    $DxDiag = Collect-DxDiagInfo

    Write-Verbose "Finding Miracast capable graphics cards."
    #Utilizing the data from DxDiag, this will check which graphics cards are Miracast capable and store them in the variable.
    $GraphicsCards = foreach ($Display in $DxDiag.DxDiag.DisplayDevices) {
        if ($Display.DisplayDevice.Miracast -eq "Supported") {
            $Display.DisplayDevice.CardName
        }
    }

    switch ($GraphicsCards) {
        #If there are no capable graphics cards
        { ($GraphicsCards | Measure-Object | Select-Object -ExpandProperty "Count") -eq 0 } {
            $GraphicsCards = "N/A"
            $MiracastCapable = $false
            $HdcpCapable = $false
        }

        #If there are capable graphics cards
        Default {
            Write-Verbose "Parsing system information from 'dxdiag' for Miracast support status."
            switch ($DxDiag.DxDiag.SystemInformation.Miracast) {
                #If the 'Miracast' field has 'Available' in it's string
                { $PSItem -like "Available*" } {
                    $MiracastCapable = $true

                    Write-Verbose "Checking if Miracast is HDCP capable."
                    switch ($PSItem) {
                        #If the 'Miracast' field has 'with HDCP' in it's string.
                        { $PSItem -like "*with HDCP" } {
                            $HdcpCapable = $true
                        }

                        #If the 'Miracast' field does not.
                        Default {
                            $HdcpCapable = $false
                        }
                    }
                }

                #If the 'Miracast' field does not.
                Default {
                    $MiracastCapable = $false
                    $HdcpCapable = $false
                }
            }
        }
    }

    #Building the return object with all collected data.
    $ReturnObj = [pscustomobject]@{
        "CapableNetAdapters"   = $NetAdapters;
        "CapableGraphicsCards" = $GraphicsCards;
        "MiracastCapable"      = $MiracastCapable;
        "HdcpCapable"          = $HdcpCapable
    }
}

end {
    return $ReturnObj
}