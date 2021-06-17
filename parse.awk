#! /usr/bin/env -S awk -f
# SPDX-License-Identifier: 0BSD
# -----------------------------------------------------------------------------

##
# Grammar
#
# S -> ε               (1)
# S -> ident S integer (2)
#
# Parse Table (LR(1))
#
#         STATE	ident	integer	$	S
#         0	s2		r1	1
#         1			acc	
#         2	s4	r1		3
#         3		s5		
#         4	s4	r1		6
#         5			r2	
#         6		s7		
#         7		r2		
#
# Parse Table (LALR(1))
#
#         STATE	ident	integer	$	S
#         0	s2		r1	1
#         1			acc	
#         2	s2	r1		3
#         3		s4		
#         4		r2	r2	
##

##
# fatal - Print a program error message to stderr(3) and exit with status 1.
#
# @msg: Message string.
#
# @return: None.
#
# NOTE: This function automatically includes the prefix "fatal: " and the final
#       "\n".
function fatal(msg,                                                          f)
{
	printf("fatal: %s\n", msg) >"/dev/stderr"
	exit(1)
}

##
# error - Print a parser error message to stderr(3).
#
# @msg: Message string.
#
# @return: None.
#
# NOTE: This function automatically includes file/line information, the prefix
#       "error: ", and the final "\n".
function error(msg,                                                          f)
{
	if ((f = stack_peek(file_stack)) == -1)
		f = "-"

	printf("%s:%d: error: %s\n", f, lineno, msg) >"/dev/stderr"
}

##
# debug - Print a program debug message to stderr(3).
#
# @msg: Message string.
#
# @return: None.
#
# NOTE: This function automatically includes the prefix "debug: " and the final
#       "\n".
function debug(msg)
{
	if (debug_messages)
		printf("debug: %s\n", msg) >"/dev/stderr"
}

##
# stack_init - Initialise a stack variable.
#
# @stack: Stack to initialise.
#
# @return: None.
function stack_init(stack)
{
	stack["@stack_size"] = 0
}

##
# stack_push - Push a value onto the stack.
#
# @stack: Stack to push to.
# @value: Value to push.
#
# @return: None.
function stack_push(stack, value,                                            n)
{
	n = stack["@stack_size"]++
	stack[n] = value
}

##
# stack_pop - Pop the top value off the stack.
#
# @stack: Stack to pop from.
#
# @return: Value at the top of the stack. This also removes the value from the
#          stack.
function stack_pop(stack,                                                 n, v)
{
	v = -1

	if (stack["@stack_size"] > 0) {
		n = --stack["@stack_size"]
		v = stack[n]
		delete stack[n]
	}

	return v
}

##
# stack_peek - Peek at the top value of the stack.
#
# @stack: Stack to peek at.
#
# @return: Value at the top of the stack. This does not remove the value from
#          the stack.
function stack_peek(stack,                                                   n)
{
	if ((n = stack["@stack_size"]) > 0)
		return stack[n - 1]
	else
		return -1
}

##
# stack_size - Check the size of a given stack.
#
# @stack: Stack to determine the size of.
#
# @return: Number of elements in the provided stack.
function stack_size(stack)
{
	return stack["@stack_size"]
}

##
# queue_init - Initialise a queue variable.
#
# @queue: Queue to initialise.
#
# @return: None.
function queue_init(queue)
{
	queue["@queue_size"] = 0
}

##
# queue_enqueue - Add a value to the queue.
#
# @queue: Queue to add to.
# @value: Value to enqueue.
#
# @return: None.
#
# NOTE: While this behaves mostly like a formal queue, the enqueue operation is
#       _not_ O(1). It is actually O(n) because of how we implement this using
#       an array. For an array-based queue like this, either the "ENQUEUE" or
#       the "DEQUEUE" operation must be O(n). The assumption here is that we
#       want "DEQUEUE" to be the faster of the two operations.
function queue_enqueue(queue, value,                                         i)
{
	for (i = ++queue["@queue_size"]; i > 0; i--) {
		queue[i] = queue[i - 1]
	}

	queue[0] = value
}

##
# queue_dequeue - Remove a value from the front of the queue.
#
# @queue: Queue to dequeue from.
#
# @return: Value at the front of the queue. This also removes the value from
#          the queue.
function queue_dequeue(queue,                                             n, v)
{
	v = -1

	if (queue["@queue_size"] > 0) {
		n = --queue["@queue_size"]
		v = queue[n]
		delete queue[n]
	}

	return v
}

##
# queue_peek - Peek at the front value of the queue.
#
# @queue: Queue to peek at.
#
# @return: Value at the front of the queue. This does not remove the value from
#          the queue.
#
# NOTE: This may formally be called the "FRONT" operation on the queue, but for
#       uniformity with the stack implementation above we use "peek".
function queue_peek(queue)
{
	if (queue["@queue_size"] > 0)
		return queue[0]
	else
		return -1
}

##
# queue_push - Push a value to the front of the queue.
#
# @queue: Queue to push to.
# @value: Value to push.
#
# @return: None.
#
# NOTE: This interface is really only intended to be used for backtracking and
#       to implement token_peek().
function queue_push(queue, value)
{
	n = queue["@queue_size"]++
	queue[n] = value
}

##
# queue_size - Check the size of a given queue.
#
# @queue: Queue to check the size of.
#
# @return: Number of elements in the provided queue.
function queue_size(queue)
{
	return queue["@queue_size"]
}

##
# token_type - Unwrap the type from a given token.
#
# @token: Token to determine the type of.
#
# @return: Type of the provided token.
#
# NOTE: The "type" is just the identifier that token.sed adds to the front of
#       every terminal it recognises.
function token_type(token)
{
	sub(/:.*$/, "", token)
	return token
}

##
# token_value - Unwrap the value from a given token.
#
# @token: Token to determine the value of.
#
# @return: Value of the provided token.
function token_value(token)
{
	sub(/[0-9A-Za-z_]+:'/, "", token)
	sub(/'$/, "", token)
	gsub(/'\\''/, "'", token)
	return token
}

##
# token_push - Push a token onto the front of the token queue.
#
# @token:
#
# @return: None.
#
# NOTE: This is mostly intended to allow for backtracking but is unnecessary
#       for an LR parser. We also use it to implement token_peek().
function token_push(token)
{
	queue_push(token_queue, sprintf("%s:%s", lineno, token))
}

##
# token_file_command - Build a command expression to execute the tokeniser.
#
# @file: Path to file to run the tokeniser on.
#
# @return: Command expression suitable for piping to getline.
function token_file_command(file)
{
	return sprintf("%s \"%s\"", tokeniser, file)
}

##
# token_file_get - Retrieve a token from the token stream.
#
# @return: Token, or -1 if no tokens remain.
function token_file_get(                                               e, f, t)
{
	f = stack_peek(file_stack)

	if (f == -1) {
		# No files on the file stack, so we're done.
		return -1
	}

	e = token_file_command(f) | getline t

	if (e == 0) {
		# Completed this file, synthesise an eof token and pop this
		# file off the stack.
		close(token_file_command(f))
		stack_pop(file_stack)

		return "eof:''"
	} else if (e == -1) {
		fatal("failed to read token stream: %s", f)
	}

	# There are two kinds of lines that the tokeniser will present us with:
	#
	# 1. Line directives, which are of the form "<number>".
	# 2. Tokens, which are of the form "<token-type>:'<token>'".
	if (t ~ /^[0-9]+$/) {
		lineno = t
		return token_file_get()
	}

	return t
}

##
# token_queue_get - Retrieve a token from the token queue.
#
# @return: Token, or -1 if no tokens remain.
function token_queue_get(                                                 t, v)
{
	if ((t = queue_dequeue(token_queue)) != -1) {
		lineno = t
		sub(/:.*$/, "", lineno)
		sub(/^[0-9]+:/, "", t)
	}

	return t
}

##
# token_next - Retrieve the next token.
#
# @return: Token, or -1 if no tokens remain.
function token_next(                                                         t)
{
	if ((t = token_queue_get()) == -1)
		t = token_file_get()

	return t
}

##
# token_peek - Peek at the next token.
#
# @return: Token, or -1 if no tokens remain. This does not advance the token
#          queue.
function token_peek(                                                        t)
{
	t = token_next()

	if (t == -1) {
		return -1
	} else if (t ~ /^[0-9]$/) {
		lineno = t
		return token_peek()
	} else {
		token_push(t)
		return t
	}
}

##
# shift - Generic shift action.
#
# @state: State to shift to.
#
# @return: None.
#
# This function alters the global state and parse stacks.
function shift(state)
{
	debug(sprintf("  shift -> %d", state))
	stack_push(parse_stack, token_next())
	stack_push(state_stack, state)
}

##
# reduce1 - Reduce by application of grammar rule 1.
#
# @return: Final state.
#
# This function alters the global state and parse stacks.
function reduce1()
{
	debug("  reduce S -> ε")

	stack_push(parse_stack, "S:'()'")
	return stack_pop(state_stack)
}

##
# reduce2 - Reduce by application of grammar rule 2.
#
# @return: Final state.
#
# This function alters the global state and parse stacks.
function reduce2(                                                      c, i, s)
{
	debug("  reduce S -> ident S integer")
	for (i = 3; i > 0; i--) {
		c[i - 1] = token_value(stack_pop(parse_stack))
		s = stack_pop(state_stack)
	}

	stack_push(parse_stack, sprintf("S:'(%s,%s) -> %s'", c[0], c[2], c[1]))
	return s
}

##
# reduce - Generic reduce action - apply a given rule and go to the next state.
#
# @action_goto: Table of actions and reduction gotos. Indexed by
#               (state, terminal) for actions and by (state, non-terminal) for
#               gotos.
# @rule:        Production rule to use for reduction.
#
# @return: None.
#
# This function alters the global state and parse stacks.
#
# NOTE: The contract for rule-specific reduce functions is that they (1) reduce
#       the parse and state stacks appropriately and (2) return the state used
#       to look up the goto for this reduce action.
function reduce(action_goto, rule,                                  ns, nt, os)
{
	if (rule == 1)
		os = reduce1()
	else if (rule == 2)
		os = reduce2()

	nt = token_type(stack_peek(parse_stack))
	ns = action_goto[os, nt]

	debug(sprintf("  goto -> %d", ns))
	stack_push(state_stack, ns)
}

##
# main - Entry point.
#
# @argc:        See awk(1) for a description of ARGC.
# @argv:        See awk(1) for a description of ARGV.
# @action_goto: LR parser table containing all actions and gotos, indexed by
#               (state, terminal) for actions and by (state, non-terminal) for
#               gotos. Actions are s[0-9]+, r[0-9]+, and acc, for shift,
#               reduce, and accept, respectively. The number associated with
#               shift actions is the state to shift to and the number
#               associated with reduce actions is the production rule to use
#               for reduction.
#
# @return: None.
function main(argc, argv, action_goto)
{
	if (argc != 2)
		fatal("expected arguments: <file>")
	else if (argv[1] == "-")
		fatal("refusing to parse stdin(3)")

	stack_push(file_stack, argv[1])
	stack_push(state_stack, 0)

	accept = 0

	while (1) {
		state = stack_peek(state_stack)
		lookahead = token_type(token_peek())

		# Throw away any nl tokens since we don't use them in the
		# grammar.
		if (lookahead ~ /^nl$/) {
			token_next()
			continue
		}

		debug(sprintf("state = %d; lookahead = %s", state, lookahead))

		action = action_goto[state, lookahead]
		debug(sprintf("action = %s", action))

		if (action ~ /^acc$/) {
			accept = 1
		} else if (action ~ /^r[0-9]+$/) {
			reduce(action_goto, substr(action, 2))
		} else if (action ~ /^s[0-9]+$/) {
			shift(substr(action, 2))
		} else if (token_peek() == -1) {
			fatal(sprintf("I/O error on file: %s", stack_peek(file_stack)))
		} else {
			error(sprintf("unexpected token: %s", token_value(token_next())))
		}

		if (accept) {
			printf("%s\n", token_value(stack_peek(parse_stack)))
			return
		}
	}
}

BEGIN {
	tokeniser = "sed -Enf \"token.sed\""
	lineno = 1

	queue_init(token_queue)
	stack_init(file_stack)
	stack_init(parse_stack)
	stack_init(state_stack)

	# LR(1)
	#action_goto[0, "ident"] = "s2"
	#action_goto[0, "eof"] = "r1"
	#action_goto[0, "S"] = 1
	#action_goto[1, "eof"] = "acc"
	#action_goto[2, "ident"] = "s4"
	#action_goto[2, "integer"] = "r1"
	#action_goto[2, "S"] = 3
	#action_goto[3, "integer"] = "s5"
	#action_goto[4, "ident"] = "s4"
	#action_goto[4, "integer"] = "r1"
	#action_goto[4, "S"] = 6
	#action_goto[5, "eof"] = "r2"
	#action_goto[6, "integer"] = "s7"
	#action_goto[7, "integer"] = "r2"

	# LALR(1)
	action_goto[0, "ident"] = "s2"
	action_goto[0, "eof"] = "r1"
	action_goto[0, "S"] = 1
	action_goto[1, "eof"] = "acc"
	action_goto[2, "ident"] = "s2"
	action_goto[2, "integer"] = "r1"
	action_goto[2, "S"] = 3
	action_goto[3, "integer"] = "s4"
	action_goto[4, "integer"] = "r2"
	action_goto[4, "eof"] = "r2"

	main(ARGC, ARGV, action_goto)
}

END {
	if (debug_dump_all || debug_dump_state_stack || debug_dump_parse_stack)
		debug_messages = 1

	if (debug_dump_state_stack || debug_dump_all) {
		if ((n = stack_size(state_stack)) == 0) {
			debug("state stack: (empty)")
		} else {
			debug(sprintf("state stack: (%d)", n))

			while ((t = stack_pop(state_stack)) != -1)
				debug(sprintf("  %s", t))
		}
	}

	if (debug_dump_parse_stack || debug_dump_all) {
		if ((n = stack_size(parse_stack)) == 0) {
			debug("parse stack: (empty)")
		} else {
			debug(sprintf("parse stack: (%d)", n))

			while ((t = stack_pop(parse_stack)) != -1)
				debug(sprintf("  %s", t))
		}
	}
}
