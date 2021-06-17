all: test

test:
	awk -f parse.awk test.txt

.PHONY: all test
