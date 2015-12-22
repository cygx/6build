use strict;
use warnings;

sub glob6_parse_string_to {
    my $end = shift;
    my @toks;

    for (;;) {
        if (!length) { die "missing terminator '$end'" }
        elsif (s/^\\(.[^\\\/\?\*\(\)\[\]\{\}]*)//) { push @toks, $1 }
        elsif (s/^([^\\\/\?\*\(\)\[\]\{\}]+)//) { push @toks, $1 }
        elsif (s/^\Q$end\E//) { last }
        else {
            my $c = substr($_, 0, 1);
            die "unescaped special char '$c'";
        }
    }

    join '', @toks;
}

sub glob6_parse {
    my @out;

    local $_ = shift;
    for (;;) {
        if    (/^$/)       { push @out, '0'; last }
        elsif (/^\/$/)     { push @out, '/0'; last }
        elsif (/^\(\/\)$/) { push @out, '(/)0'; last }
        elsif (s/^\///)    { push @out, '/' }
        elsif (s/^\?//)    { push @out, '?' }
        elsif (s/^\*\*//)  { push @out, '**' }
        elsif (s/^\*//)    { push @out, '*' }
        elsif (s/^\(//)    { push @out, '()', glob6_parse_string_to(')') }
        elsif (s/^\[//) {
            my $chars = glob6_parse_string_to(']');
            die "empty character class" unless length $chars;
            push @out, '[]', $chars;
        }
        elsif (/^\{/) {
            my @alt;
            push @alt, glob6_parse_string_to('}') while s/^\{//;
            push @out, '{}', scalar(@alt), @alt;
        }
        else {
            my @toks;
            while (length) {
                if    (s/^\\(.[^\\\/\?\*\(\)\[\]\{\}]*)//) { push @toks, $1 }
                elsif (s/^([^\\\/\?\*\(\)\[\]\{\}]+)//) { push @toks, $1 }
                else { last }
            }
            push @out, '_', join('', @toks);
        }
    }

    \@out;
}

sub glob6_rx {
    my @in = @{glob6_parse(shift)};
    my @out;

    while (@in) {
        my $tok = shift @in;
        if    ($tok eq '_' ) { push @out, quotemeta(shift @in) }
        elsif ($tok eq '/' ) { push @out, '[/\\\\]' }
        elsif ($tok eq '?' ) { push @out, '[^/\\\\]' }
        elsif ($tok eq '*' ) { push @out, '[^/\\\\]*?' }
        elsif ($tok eq '**') { push @out, '.*?' }
        elsif ($tok eq '()') { push @out, '(?:', quotemeta(shift @in), ')?' }
        elsif ($tok eq '[]') { push @out, '[', quotemeta(shift @in), ']' }
        elsif ($tok eq '{}') {
            my $n = shift @in;
            push @out, '(?:', join('|', map(quotemeta, splice(@in, 0, $n))), ')';
        }
        elsif ($tok eq '0' )   { push @out, '$' }
        elsif ($tok eq '/0')   { push @out, '[/\\\\]$' }
        elsif ($tok eq '(/)0') { push @out, '[/\\\\]?$' }
        else { die "unknown token '$tok'" }
    }

    my $rx = '^'.join('', @out);
    qr/$rx/;
}

sub glob6 {}
