#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 1;     # Main test module; run this many tests

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 file-upload);

{
    my $message = "no option, no argument";
    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    {
        $message .= " smoke test";
        ok( $obj->do_file_upload() );
    }
}
