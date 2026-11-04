@{
    # PSScriptAnalyzer settings for the module 3 PowerShell implementation.
    #
    # The rules excluded below are excluded on purpose, not because they are
    # inconvenient:
    #
    # PSAvoidUsingWriteHost - this is a terminal display tool, so writing to
    # the host is the intended output channel rather than a side effect. The
    # repository's other shipped PowerShell modules do the same.
    #
    # PSReviewUnusedParameter - PSScriptAnalyzer analyses a .ps1 script's
    # param block separately from the functions in the same file, so it
    # reports the script's parameters as unused even though the functions
    # read them.
    #
    # PSAvoidUsingPlainTextForPassword - the -DbPassword parameter is the
    # backwards-compatible CLI contract and receives the password as a plain
    # string by design. The recommended channel is the DB_BACKUP_PASSWORD
    # environment variable (see SPECS: never read the password from argv in
    # production). A SecureString migration is a deliberate, breaking change
    # tracked separately; suppressing here rather than on the parameter
    # because PSScriptAnalyzer honours suppressions on script-level param
    # blocks inconsistently across hosts.

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSReviewUnusedParameter'
        'PSAvoidUsingPlainTextForPassword'
    )
}
