#! /usr/bin/env -S sed -Enf
# SPDX-License-Identifier: 0BSD
# -----------------------------------------------------------------------------

##
# Tokeniser
#
#   We want to produce a stream of tokens to feed to the parser. This is doable
#   with sed(1), since it's Turing-complete [1], but since it is basically like
#   writing funky assembly with two and a half registers [2] we have to dance
#   around a bit.
#
#   Tokens have the form <symbol>:<string> where <symbol> is one of the symbols
#   defined below and <string> is the string associated with <symbol> in a form
#   suitable for evaluation by the shell. (This makes it easier to extract
#   later, even if we don't pass it directly to the shell.)
#
#   The output of this tokeniser will be zero or more lines. Each line will be
#   either a single number, matching ^[0-9]+$ and representing the original
#   line number the following tokens are from, or a token-value pair as
#   described above.
#
#   All comments, empty lines, and lines containing only whitespace and
#   comments are ignored, as well as all "uninteresting" whitespace. Whitespace
#   in strings and newline characters for lines containing tokens are kept.
#
#   NOTE: To make this executable without invoking "sed -Enf <this-file>",
#         assuming the available env(1) doesn't accept -S, change the first
#         line to "#! <absolute-path-to-sed> -Enf" as the OS should split it
#         into two words.
#
#   NOTE: This script cannot tokenise itself properly; it would have to be
#         adjusted to deal specifically with sed(1) syntax. For example, it
#         chokes on unpaired quotes and it fails to deal with constructions
#         like /"(\\"|[^"])*"/. In the latter case, we end up with a sequence
#         of slash-string_s-bracket_close-paren_close-asterisk-invalid, which
#         is utterly useless for parsing. It should not ever find itself in an
#         infinite loop, however.
#
#   [1]: https://catonmat.net/ftp/sed/turing.txt
#   [2]: It has two read-write buffers, a line number buffer that can't be
#        directly interacted with, a comparison operation, unconditional and
#        conditional branch instructions, and a few ways of modifying the
#        contents of the two buffers.
#
# Tokens
#
#   NOTE: We use the convention here that terminals are represented by
#         lowercase identifiers and non-terminals are represented by uppercase
#         identifiers.
#
#     kw_set        ::= "set"
#
#     kw_unset      ::= "unset"
#
#     ident         ::= [[:alpha:]_][[:alnum:]_]*
#
#     float         ::= [0-9]+ "." [0-9]*[Ee][+-][0-9]+
#                     | [0-9]+ "." [0-9]*[Ee][0-9]+
#                     | [0-9]+ "." [0-9]*
#                     | "." [0-9]+[Ee][+-][0-9]+
#                     | "." [0-9]+[Ee][0-9]+
#                     | "." [0-9]+
#
#     integer       ::= "0x" [0-9A-Fa-f]+
#                     | "0" [0-7]*
#                     | [1-9][0-9]*
#
#     string_d      ::= "\"" (\\"|[^"])* "\""
#
#     string_s      ::= "'" ([^'])* "'"
#
#     bracket_open  ::= "["
#
#     bracket_close ::= "]"
#
#     brace_open    ::= "{"
#
#     brace_close   ::= "}"
#
#     paren_open    ::= "("
#
#     paren_close   ::= ")"
#
#     ampersand     ::= "&"
#
#     asterisk      ::= "*"
#
#     backslash     ::= "\"
#
#     caret         ::= "^"
#
#     colon         ::= ":"
#
#     comma         ::= ","
#
#     dollar        ::= "$"
#
#     equal         ::= "="
#
#     minus         ::= "-"
#
#     period        ::= "."
#
#     vert          ::= "|"
#
#     plus          ::= "+"
#
#     question      ::= "?"
#
#     slash         ::= "/"
#
#     semicolon     ::= ";"
#
#     nl            ::= "\n"
##

# Clear out anything in hold space left over from the previous line.
x
s/^.*$//
x

# If the line is empty or only contains a comment, we can just skip it
# immediately.
/^[[:space:]]*(#.*)?$/ {
	$i eof:''
	d
}

# Fold escaped newlines by appending to pattern space, throwing away the
# embedded \n this operation creates.
: fold
/\\$/ {
	N
	s/\\\n//
	t fold
}

# Print the current line number so the parser has at least a faint hope of
# producing helpful error messages.
=

# After processing a token, we want to jump back here to start on the next
# token on the current line.
: top

# Check if there is anything in hold space. If there is, we just processed a
# token and jumped back here. Print it and strip it from the beginning of the
# line before proceeding.
x
/./ {
	s/^([[:alpha:]_]+:'('\\''|[^'])*').*$/\1/
	p
	x
	s/^[[:alpha:]_]+:'('\\''|[^'])*'//

	# Clear out hold space again.
	x
	s/^.*$//
}
x

# Throw away all leading whitespace.
s/^[[:space:]]*//

# If we find a comment or the end of the line, we're done here.
/^(#.*)$/ {
	b done
}

# Okay, after all that preamble, we can start the token-matching rules. The
# contract here is that, once we've recognised a token, we must:
#
# 1. Transform it into the appropriate format: <token-id>:<sh-escaped-value>
# 2. Ensure we haven't touched the rest of the current input line.
# 3. Write the modified line to hold space. (h)
# 4. Branch to the "top" label, which handles extracting the token from the
#    beginning of the line, printing it and shifting to the rest of the line.
#
# NOTE: It's best to do the "simple" tokens last, so they don't cause problems.

# Keywords can either be matched here by the lexer or picked up by the parser,
# which checks each ident token against a list of keywords and rewrites the
# <token-id>. The latter is likely less efficient, but means that this script
# is less verbose since the former means we have to write a matching rule for
# every keyword or do the following hackery:
/^((un)?set)[^[:alnum:]_]?/ {
	# Save the current line to hold space and remove the reserved
	# identifier from the front of it.
	h
	s/^[[:alpha:]_][[:alnum:]_]*//

	# Now swap back and remove everything _but_ the reserved identifier at
	# the front.
	x
	s/^([[:alpha:]_][[:alnum:]_]*).*/kw_\1:'\1'/

	# We only have keywords matching [a-z_]+, but if we don't, we need to
	# lowercase all the characters to follow the convention that terminals
	# are lowercase while non-terminals are uppercase. This is _not_
	# strictly necessary and _will_ cause problems in languages other than
	# English.
	#y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/

	# Now append the remaining portion of the line that we have saved in
	# hold space and throw away the embedded \n this operation creates.
	G
	s/\\\n//

	h
	b top

}

/^[[:alpha:]_][[:alnum:]_]*/ {
	s/^[[:alpha:]_][[:alnum:]_]*/ident:'&'/
	h
	b top
}

/^\.?[0-9]/ {
	/^\.[0-9]/ {
		s/^\.[0-9]+([Ee][+-]?[0-9]+)?/float:'&'/
		h
		b top
	}

	/^[0-9]+\.[0-9]*/ {
		s/^[0-9]+\.[0-9]*([Ee][+-]?[0-9]+)?/float:'&'/
		h
		b top
	}

	/^0x[0-9A-Fa-f]+/ {
		s/^0x[0-9A-Fa-f]+/integer:'&'/
		h
		b top
	}

	/^0[0-7]*/ {
		s/^0[0-7]*/integer:'&'/
		h
		b top
	}

	/^[1-9][0-9]*/ {
		s/^[1-9][0-9]*/integer:'&'/
		h
		b top
	}
}

/^"((\\"|[^"])*)"/ {
	# Save the current line to hold space and remove the string from the
	# front of it.
	h
	s/^"((\\"|[^"])*)"//

	# We have the original line in hold space, so swap pattern and hold
	# space, turn the string into a token, and remove the rest of the line.
	x
	s/^"((\\"|[^"])*)".*$/\1/
	s/'/'\\''/g
	s/^/string_d:'/
	s/$/'/

	# Now append the remaining portion of the line that we have saved in
	# hold space and throw away the embedded \n this operation creates.
	G
	s/\\\n//

	h
	b top
}

/^'([^']*)'/ {
	# Save the current line to hold space and remove the string from the
	# front of it.
	h
	s/^'([^']*)'//

	# We have the original line in hold space, so swap pattern and hold
	# space, turn the string into a token, and remove the rest of the line.
	x
	s/^'([^']*)'.*$/\1/
	s/'/'\\''/g
	s/^/string_s:'/
	s/$/'/

	# Now append the remaining portion of the line that we have saved in
	# hold space.
	G
	s/\\\n//

	h
	b top
}

/^\[/ {
	s/^\[/bracket_open:'&'/
	h
	b top
}

/^\]/ {
	s/^\]/bracket_close:'&'/
	h
	b top
}

/^\{/ {
	s/^\{/brace_open:'&'/
	h
	b top
}

/^\}/ {
	s/^\}/brace_close:'&'/
	h
	b top
}

/^\(/ {
	s/^\(/paren_open:'&'/
	h
	b top
}

/^\)/ {
	s/^\)/paren_close:'&'/
	h
	b top
}

/^\&/ {
	s/^\&/ampersand:'&'/
	h
	b top
}

/^\*/ {
	s/^\*/asterisk:'&'/
	h
	b top
}

/^\\/ {
	s/^\\/backslash:'&'/
	h
	b top
}

/^\^/ {
	s/^\^/caret:'&'/
	h
	b top
}

/^:/ {
	s/^:/colon:'&'/
	h
	b top
}

/^,/ {
	s/^,/comma:'&'/
	h
	b top
}

/^\$/ {
	s/^\$/dollar:'&'/
	h
	b top
}

/^=/ {
	s/^=/equal:'&'/
	h
	b top
}

/^-/ {
	s/^-/minus:'&'/
	h
	b top
}

/^\./ {
	s/^\./period:'&'/
	h
	b top
}

/^\|/ {
	s/^\|/vert:'&'/
	h
	b top
}

/^\+/ {
	s/^\+/plus:'&'/
	h
	b top
}

/^;/ {
	s/^;/semicolon:'&'/
	h
	b top
}

/^\?/ {
	s/^\?/question:'&'/
	h
	b top
}

/^\// {
	s/^\//slash:'&'/
	h
	b top
}

: error
/./ {
	# Just call the rest of the line invalid and let the parser figure out
	# how to deal with it.
	s/'/'\\''/g
	s/^/invalid:'/
	s/$/'/
	p
}

# Only output the "interesting" occurrences of \n.
: done
i nl:''
d
