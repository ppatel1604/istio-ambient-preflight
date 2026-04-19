function Format-Finding {
    <#
    .SYNOPSIS
        Constructs the canonical finding object emitted by every check.

    .DESCRIPTION
        Every ambient-compatibility check in IstioAmbientPreflight returns zero or
        more finding objects via this factory. Centralizing construction keeps the
        finding schema stable across checks and gives the report writer a single
        shape to format.

        The returned object is a [pscustomobject] with PSTypeName
        'IstioAmbientPreflight.Finding' and the following properties:

            Severity  - 'Blocker' | 'Warning' | 'Info'
            Category  - Free-form grouping label (e.g. 'Labels', 'Network', 'Ingress')
            CheckId   - Stable identifier for the check (e.g. 'N-01', 'C-02')
            Resource  - Human-readable descriptor of the affected Kubernetes resource
            Message   - Plain-English explanation of the problem and recommended action
            DocLink   - URL to the authoritative public documentation that justifies the check

    .PARAMETER Severity
        One of 'Blocker', 'Warning', 'Info'. Drives report grouping and the overall
        readiness verdict.

    .PARAMETER Category
        Grouping label for the report's table of contents. Examples: 'Labels',
        'Network', 'Ingress'.

    .PARAMETER CheckId
        Stable identifier for the check, matching the IDs in ROADMAP.md
        (e.g. 'N-01', 'C-02'). Used for cross-referencing and for users to suppress
        specific checks in future versions.

    .PARAMETER Resource
        Descriptor of the affected Kubernetes resource, such as
        'NetworkPolicy/allow-frontend in namespace payments'.

    .PARAMETER Message
        Plain-English explanation: why ambient mode cares, what happens if the
        user does not address it, and what the recommended action is.

    .PARAMETER DocLink
        HTTPS URL to authoritative public documentation (istio.io, docs.cilium.io,
        gateway-api.sigs.k8s.io, etc.) supporting the finding.

    .EXAMPLE
        PS> Format-Finding -Severity Blocker -Category Network -CheckId 'C-02' `
        >>     -Resource 'NetworkPolicy/allow-frontend in namespace payments' `
        >>     -Message 'Policy does not allow ztunnel traffic on port 15008. Add an ingress rule for port 15008 or mesh traffic will be dropped after migration.' `
        >>     -DocLink 'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'

        Returns a finding object ready to be piped into the report writer.
    #>
    [CmdletBinding()]
    [OutputType('IstioAmbientPreflight.Finding')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Blocker', 'Warning', 'Info')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z]+-\d{2,}$')]
        [string]$CheckId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidatePattern('^https?://')]
        [string]$DocLink
    )

    [pscustomobject]@{
        PSTypeName = 'IstioAmbientPreflight.Finding'
        Severity   = $Severity
        Category   = $Category
        CheckId    = $CheckId
        Resource   = $Resource
        Message    = $Message
        DocLink    = $DocLink
    }
}
