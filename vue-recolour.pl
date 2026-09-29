#!/usr/bin/perl

use strict;

my %nodes;
my %links;
my $debug = 0;

while($ARGV[0] =~ /^-/) {
    my $opt = shift @ARGV;

    if($opt eq '--node') {
        my $clr1 = shift @ARGV;
        die "Can only set action for node colour #$clr1 once\n" if exists($nodes{$clr1});
        my $clr2 = shift @ARGV;
        my $xtra = {};
        while($ARGV[0] eq 'text' || $ARGV[0] eq 'border') {
            my $extra = shift(@ARGV);
            die "Can only set node extra \"$extra\" once\n" if exists($xtra->{$extra});
            $xtra->{$extra} = shift(@ARGV);
        }
        $nodes{$clr1} = [$clr2, $xtra];
    }
    elsif($opt eq '--link') {
        my $clr1 = shift @ARGV;
        die "Can only set action for link colour #$clr1 once\n" if exists($links{$clr1});
        my $clr2 = shift @ARGV;
        my $xtra = {};
        while($ARGV[0] eq 'style') {
            my $extra = shift(@ARGV);
            die "Can only set link extra \"$extra\" once\n" if exists($xtra->{$extra});
            $xtra->{$extra} = shift(@ARGV);
        }
        $links{$clr1} = [$clr2, $xtra];
    }
    elsif($opt eq '--node-as') {
        my $clr1 = shift @ARGV;
        die "Can only set action for node colour #$clr1 once\n" if exists($nodes{$clr1});
        my $clr2 = shift @ARGV;
        die "Cannot duplicate behaviour of undefined node colour #$clr2 in #$clr1\n"
            if !exists($nodes{$clr2});
        $nodes{$clr1} = $nodes{$clr2};
    }
    elsif($opt eq '--link-as') {
        my $clr1 = shift @ARGV;
        die "Can only set action for link colour #$clr1 once\n" if exists($links{$clr1});
        my $clr2 = shift @ARGV;
        die "Cannot duplicate behaviour of undefined link colour #$clr2 in $clr1\n"
            if !exists($links{$clr2});
        $links{$clr1} = $links{$clr2};
    }
    elsif($opt eq '--debug') {
        $debug = 1;
    }
    elsif($opt eq '--verbose') {
        $debug = 2;
    }
    else {
        die "Unrecognized option $opt\n";
    }
}

if(scalar(@ARGV) == 0) {
    die "Need a VUE file or - for stdin\n";
}
my $fp = *STDIN;
my $filename = "<stdin>";
if($ARGV[0] ne "-") {
    $filename = shift(@ARGV);
    open($fp, "<", $filename) or die "Cannot read from $filename: $!\n";
}

if($debug) {
    warn "Reading from $filename\n";
    foreach my $key (sort {$a cmp $b} keys(%nodes)) {
        my ($clr, $xtras) = @{$nodes{$key}};
        print STDERR "Substituting #$clr for #$key in nodes";
        if(exists($xtras->{'text'})) {
            print STDERR " and setting text colour to #$xtras->{'text'}";
        }
        if(exists($xtras->{'border'})) {
            print STDERR " and changing border colour to #$xtras->{'border'}";
        }
        print STDERR "\n";
    }
    foreach my $key (sort {$a cmp $b} keys(%links)) {
        my ($clr, $xtras) = @{$links{$key}};
        print STDERR "Substituting #$clr for #$key in links";
        if(exists($xtras->{'style'})) {
            print STDERR " and setting line style to $xtras->{'style'}";
        }
        print STDERR "\n";
    }
}

my $is_vue = 0;
my $in_child = 0;
my $child_type = "none";
my @buffer;
my $extras = {};
my $n_child = 0;
while(my $line = <$fp>) {
    $line =~ s/\s+$//;

    if($line =~ /^<LW-MAP xmlns/) {
        $is_vue = 1;
        while(scalar(@buffer) > 0) {
            print shift @buffer, "\n";
        }
        print "$line\n";
    }
    elsif($is_vue) {
        if($in_child && $line =~ /^\s*\<\/child\>$/) {
            $in_child = 0;
            $child_type = "none";
            $extras = {};
            while(scalar(@buffer) > 0) {
                print shift @buffer, "\n";
            }
            print "$line\n";
            $n_child++;
        }
        elsif(!$in_child && $line =~ /^\s*\<child /) {
            $in_child = 1;
            push(@buffer, $line);
        }
        elsif($in_child && $line =~ /xsi:type="([a-z]+)"/) {
            $child_type = $1;
            warn "Found child with type \"$child_type\"\n" if $debug > 1;
            push(@buffer, $line);
        }
        elsif($in_child && $child_type eq 'node' && $line =~ /fillColor\>#([0-9A-F]+)\</) {
            my $node_clr = $1;
            if(exists($nodes{$node_clr})) {
                my ($new_clr, $xtras) = @{$nodes{$node_clr}};
                $line =~ s/#$node_clr/#$new_clr/;
                $extras = $xtras;
            }
            push(@buffer, $line);
        }
        elsif($in_child && $child_type eq 'node' && exists($extras->{'text'})
            && $line =~ /textColor\>#([0-9A-F]+)\</)
        {
            my $text_clr = $1;
            my $new_clr = $extras->{'text'};
            $line =~ s/#$text_clr/#$new_clr/;
            push(@buffer, $line);
        }
        elsif($in_child && $child_type eq 'node' && exists($extras->{'border'})
            && $line =~ /strokeColor\>#([0-9A-F]+)\</)
        {
            my $border_clr = $1;
            my $new_clr = $extras->{'border'};
            $line =~ s/#$border_clr/#$new_clr/;
            push(@buffer, $line);
        }
        elsif($in_child && $child_type eq 'link' && $line =~ /strokeColor\>#([0-9A-F]+)\</) {
            my $link_clr = $1;
            if(exists($links{$link_clr})) {
                my ($new_clr, $xtras) = @{$links{$link_clr}};
                $line =~ s/#$link_clr/#$new_clr/;
                $extras = $xtras;
            }
            if(exists($extras->{'style'})) {
                my $link_style = $extras->{'style'};
                my $subs_style = 0;
                for(my $i = 0; $i <= $#buffer; $i++) {
                    if($buffer[$i] =~ /strokeStyle/) {
                        $buffer[$i] =~ s/strokeStyle=".+"/strokeStyle="$link_style"/;
                        $subs_style = 1;
                    }
                }
                if($subs_style == 0) {
                    for(my $i = 0; $i <= $#buffer; $i++) {
                        if($buffer[$i] =~ /autoSized/) {
                            $buffer[$i] =~ s/autoSized/strokeStyle="$link_style" autoSized/;
                        }
                    }
                }
            }
            push(@buffer, $line);
        }
        else {
            push(@buffer, $line);
        }
    }
    else {
        push(@buffer, $line);
    }
}

close $fp;
warn "Found $n_child nodes/links\n" if $debug;
if($is_vue) {
    while(scalar(@buffer) > 0) {
        print shift @buffer, "\n";
    }
}
else {
    die "$filename not detected as a VUE format XML file\n";
}
exit 0;