@{
    # PSScriptAnalyzer settings for the Stage 1 PowerShell implementation.
    #
    # The rules excluded below are excluded on purpose, not because they are
    # inconvenient:
    #
    # PSAvoidUsingWriteHost - this is a terminal display tool, so writing to
    # the host is the intended output channel rather than a side effect. The
    # repository's other shipped PowerShell module does the same.
    #
    # PSReviewUnusedParameter - PSScriptAnalyzer analyses a .ps1 script's
    # param block separately from the functions in the same file, so it
    # reports TopProcesses, CpuThreshold and MemThreshold as unused even
    # though the functions read them.

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSReviewUnusedParameter'
    )
}
