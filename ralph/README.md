# River's PowerRalph9000

This is all based on [AI Hero's Getting Started with Ralph](https://www.aihero.dev/getting-started-with-ralph).

## The Loop

`ralph-loop 10` - runs 10 iterations of the loop:

0. Loop Start
   0. Find work ticket
   0. Work it, then update progress.txt and deferred.txt
   0. Write tests for it, then update progress.txt and deferred.txt
   0. Code Review it, then update progress.txt and deferred.txt
   0. Repeat
0. Repeat loop until iterations complete or no work left
0. Read progress.txt and codify lessons learned
0. Read deferred.txt and create or update issue tickets w/ `deferred` label
