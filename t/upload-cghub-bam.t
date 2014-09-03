#! /usr/bin/env perl

use strict;
use warnings;
use Test::Script::Run;
use Test::More 'tests' => 3;     # Main test module; run this many subtests

use Bio::SeqWare::Uploads::CgHub::Bam;
my $APP = 'upload-cghub-bam';

{
    my $message = "Correct shebang line";
    my $perlExec = 'blib/script/upload-cghub-bam';
    if (! -f $perlExec) {
        diag("$perlExec does not exist");
    }
    open my $fh, '<', $perlExec or die "$perlExec: $!";
    chomp(my $line = <$fh>);
    close $fh or die "$perlExec: $!";
    {
        like( $line, qr/^#!\s?\/usr\/bin\/env perl/, $message);
    }
}
{
   run_ok( $APP, [], "Minimal run succeeds");
}
{
    my $version = $Bio::SeqWare::Uploads::CgHub::Bam::VERSION;
    my @app_out_lines = ("upload-cghub-bam v$version",);
    my @app_args = qw(--version);
    {
        run_output_matches( $APP, \@app_args, \@app_out_lines, []);
    }
}