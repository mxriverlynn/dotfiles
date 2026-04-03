@progress.txt
create a well-tested codebase, without overspecifying or creating brittle tests. Follow these steps:
1. Run /test-planning against commits starting with STARTINGSHA, and write all tests that were identified
2. Run all tests and type checks, and fix any issues.
3. Commit changes in a single commit.
4. Append your progress to progress.txt
5. Append all deferred work to deferred.txt
6. Update the github issue ISSUENUMBER with what was done.
Never commit progress.txt
Never commit deferred.txt
