# awklr

Manually write LR parsers in `awk(1)` – with a little help from `sed(1)`.

This is mostly just an example of a thing you _can_ do, rather than something
that's likely to be useful. Although, Aho, Kernighan, and Weinberger _did_
write:

> Awk is good for designing and experimenting with little languages. If a
> design proves suitable, a production version can be recoded in a more
> efficient systems language like C. In some cases, the prototype version
> itself may be suitable for production use. These situations typically involve
> sugar-coating or specializing an existing tool.
>
> – The Awk Programming Language, §6.2, p. 139

## Example

The `parse.awk` script contains an example grammar and `test.txt` contains
example input. Try `make test` or `awk -f parse.awk test.txt` to see that the
parser does, in fact, function.

## FAQ

### Should I use this?

Absolutely not. What's wrong with you?

Actually, it might be useful for very small languages with something on the
order of 10—30 LALR(1) states or for configuration parsing for programs using
only the shell and other POSIX-specified tools, but I suspect it would be
easier to implement an ad-hoc `*.ini` parser rather than specifying a grammar,
manually constructing the tables, implementing all the reduction actions, and
producing sensible output.

### This is awful. Why would you do this?

I'm bored, depressed, and interested in compilers.
