@{
    # PSScriptAnalyzer settings for the Module 6 PowerShell implementation.

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSReviewUnusedParameter'
    )
}
