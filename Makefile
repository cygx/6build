doc: README USAGE
README: 6build; perldoc -otext -d$@ $<
USAGE: 6build; ./$< >$@
