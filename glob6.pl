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
    local $_ = shift;
    my (@ops, @part);

    for (;;) {
        if (/^$/) {
            push @ops, 'FILE', scalar(@part), @part;
            last;
        }
        elsif (/^\/$/) {
            push @ops, 'DIR', scalar(@part), @part;
            last;
        }
        elsif (/^\(\/\)$/) {
            push @ops, 'FILE|DIR', scalar(@part), @part;
            last;
        }
        elsif (s/^\///) {
            push @ops, 'SUBDIR', scalar(@part), @part;
            @part = ();
        }
        elsif (s/^\?//) {
            push @part, 'QUERY';
        }
        elsif (s/^\*\*//) {
            die "subtree wildcard '**' invalid within filename" if @part;
            push @ops, 'SUBTREE';
            @part = ('STAR');
        }
        elsif (s/^\*//) {
            push @part, 'STAR';
        }
        elsif (s/^\(//) {
            push @part, 'OPT', glob6_parse_string_to(')');
        }
        elsif (s/^\[//) {
            my $chars = glob6_parse_string_to(']');
            die "empty character class '[]'" unless length $chars;
            push @part, 'CLASS', $chars;
        }
        elsif (/^\{/) {
            my @alt;
            push @alt, glob6_parse_string_to('}') while s/^\{//;
            push @part, 'ALT', scalar(@alt), @alt;
        }
        else {
            my @toks;
            while (length) {
                if    (s/^\\(.[^\\\/\?\*\(\)\[\]\{\}]*)//) { push @toks, $1 }
                elsif (s/^([^\\\/\?\*\(\)\[\]\{\}]+)//) { push @toks, $1 }
                else { last }
            }
            push @part, 'STR', join('', @toks);
        }
    }

    \@ops;
}

sub glob6_rx {
    my @rx;

    while (@_) {
        my $tok = shift;
        if    ($tok eq 'STR' )  { push @rx, quotemeta(shift) }
        elsif ($tok eq 'QUERY') { push @rx, '.' }
        elsif ($tok eq 'STAR' ) { push @rx, '.*' }
        elsif ($tok eq 'OPT')   { push @rx, '(?:', quotemeta(shift), ')?' }
        elsif ($tok eq 'CLASS') { push @rx, '[', quotemeta(shift), ']' }
        elsif ($tok eq 'ALT') {
            my $n = shift;
            push @rx, '(?:', join('|', map(quotemeta, splice(@_, 0, $n))), ')';
        }
        else { die "unknown token '$tok'" }
    }

    my $rx = join '', @rx;
    qr/^$rx$/;
}

sub glob6_tree {
    my ($tree, $dir) = @_;
    push @$tree, $dir;

    opendir my $dh, $dir or die "$dir: $!";
    my @nodes = readdir $dh;
    closedir $dh;
    
    for (@nodes) {
        my $path = "$dir/$_";
        glob6_tree($tree, $path) if !/^\./ && -d $path;
    }
}

sub glob6_exec {
    my $res = shift;
    my $dir = shift;
    local $_;

    my $op = shift;
    if ($op eq 'FILE' || $op eq 'DIR' || $op eq 'FILE|DIR') {
        my $n = shift;
        my $rx = glob6_rx splice(@_, 0, $n);

        opendir my $dh, $dir or die "$dir: $!";
        while (readdir $dh) {
            if (/$rx/) {
                my $path = "$dir/$_";
                push @$res, $path
                    if ($op eq 'FILE' && -f $path) ||
                       ($op eq 'DIR'  && -d $path) ||
                       (-f $path || -d $path);
            }
        }
        closedir $dh;
    }
    elsif ($op eq 'SUBDIR') {
        my $n = shift;
        my $rx = glob6_rx splice(@_, 0, $n);

        opendir my $dh, $dir or die "$dir: $!";
        my @nodes = readdir $dh;
        closedir $dh;

        for (@nodes) {
            if (/$rx/) {
                my $path = "$dir/$_";
                glob6_exec($res, $path, @_) if -d $path;
            }
        }
    }
    elsif ($op eq 'SUBTREE') {
        my @subdirs;
        glob6_tree(\@subdirs, $dir);
        glob6_exec($res, $_, @_) for @subdirs;
    }
    else { die "unknown operation '$op'" }
}

sub glob6 {
    my @res;

    for (@_) {
        my $ops = glob6_parse($_);
        glob6_exec(\@res, '.', @$ops);
    }

    @res;
}
