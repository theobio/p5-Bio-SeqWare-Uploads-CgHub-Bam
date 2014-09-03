#! /usr/bin/env perl

use strict;
use warnings;
use Test::Script::Run;
use Test::More 'tests' => 2;     # Main test module; run this many subtests

run_ok( 'upload-cghub-bam', [], "Minimal run succeeds");

{
    my $perlExec = 'blib/script/upload-cghub-bam';
    if (! -f $perlExec) {
        diag("$perlExec does not exist");
    }
    open my $fh, '<', $perlExec or die "$perlExec: $!";
    chomp(my $line = <$fh>);
    close $fh or die "$perlExec: $!";
    {
        like( $line, qr/^#!\s?\/usr\/bin\/env perl/, "Correct shebang line");
    }
}